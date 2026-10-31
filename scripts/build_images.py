#!/usr/bin/env python3
"""A-17: 商品画像のビルドスクリプト（macOS）。

`originals/` の原本（商品IDと同名のファイル）と、アプリが書き出した
商品マスタ CSV を突合し、次の成果物を再生成する。

アプリの「機能メニュー → 商品マスタ → 画像の保存先」で `originals/` を
選ぶと、商品編集画面で撮影・選択した写真が `originals/<商品ID>.jpg` に
保存される。カメラ撮影もファイル選択も同じフォルダを使う。

- レジ用サムネイル: Craftill/Craftill/Images/<商品ID>.jpg
- Web 用画像:       web/public/images/<商品ID>.jpg
- 対応一覧:         web/public/images/manifest.csv
- 画像の版識別子:   Craftill/Craftill/ImageBuildInfo.swift と
                    web/public/images/version.txt

原本は変更しない。出力は毎回作り直す。macOS 標準の `sips` と `shasum`
だけを使う（追加のライブラリ不要）。

使い方:
    python3 scripts/build_images.py --csv ~/Downloads/products.csv
    python3 scripts/build_images.py --csv products.csv --strict

`--strict` を付けると、欠落・余剰・読み込めない画像がある場合に終了コード 1
を返す。既定は警告のみ（Q18 の「ビルドを止めるか警告か」は未決定のため）。
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_ORIGINALS = ROOT / "originals"
DEFAULT_APP_OUT = ROOT / "Craftill" / "Craftill" / "Images"
DEFAULT_WEB_OUT = ROOT / "web" / "public" / "images"
INFO_SWIFT = ROOT / "Craftill" / "Craftill" / "ImageBuildInfo.swift"

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".tif", ".tiff", ".webp"}
ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")


@dataclass
class Issue:
    kind: str
    detail: str


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def read_product_ids(csv_path: Path) -> List[str]:
    if not csv_path.exists():
        raise SystemExit(f"商品マスタ CSV が見つかりません: {csv_path}")
    with csv_path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            raise SystemExit(f"CSV にヘッダがありません: {csv_path}")
        # product_id 列を大文字小文字を無視して探す。
        key = next((h for h in reader.fieldnames if h.strip().lower() == "product_id"), None)
        if key is None:
            raise SystemExit("CSV に product_id 列がありません。アプリの商品マスタ CSV を使ってください。")
        ids: List[str] = []
        seen = set()
        for row in reader:
            raw = (row.get(key) or "").strip()
            if not raw:
                continue
            if raw in seen:
                eprint(f"警告: product_id が重複しています: {raw}")
                continue
            seen.add(raw)
            ids.append(raw)
    return ids


def index_originals(originals: Path) -> Tuple[Dict[str, Path], List[Issue]]:
    issues: List[Issue] = []
    found: Dict[str, Path] = {}
    if not originals.exists():
        issues.append(Issue("originals", f"原本ディレクトリがありません: {originals}"))
        return found, issues

    for path in sorted(originals.rglob("*")):
        if not path.is_file() or path.name.startswith("."):
            continue
        # 置き場所の説明ファイルは画像ではないので、警告にしない。
        if path.name.lower() in {"readme.md", "readme.txt"}:
            continue
        if path.suffix.lower() not in IMAGE_EXTENSIONS:
            issues.append(Issue("unsupported", f"画像として扱わない拡張子: {path.name}"))
            continue
        stem = path.stem
        if stem in found:
            issues.append(Issue("duplicate", f"同じ商品IDの原本が複数あります: {found[stem].name} / {path.name}"))
            continue
        found[stem] = path
    return found, issues


def image_info(path: Path) -> Optional[Tuple[int, int]]:
    """`sips` でピクセル幅・高さを取得する。読めなければ None。"""
    try:
        out = subprocess.run(
            ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
            check=True, capture_output=True, text=True,
        ).stdout
    except (subprocess.CalledProcessError, OSError):
        return None
    width = height = None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("pixelWidth:"):
            width = int(line.split(":", 1)[1].strip())
        elif line.startswith("pixelHeight:"):
            height = int(line.split(":", 1)[1].strip())
    if not width or not height:
        return None
    return width, height


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def make_jpeg(source: Path, destination: Path, max_pixels: int) -> bool:
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        subprocess.run(
            ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "85",
             "-Z", str(max_pixels), str(source), "--out", str(destination)],
            check=True, capture_output=True, text=True,
        )
    except (subprocess.CalledProcessError, OSError) as e:
        detail = getattr(e, "stderr", "") or str(e)
        eprint(f"エラー: 画像を変換できません: {source.name}: {detail.strip()}")
        return False
    return destination.exists() and destination.stat().st_size > 0


def swift_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def write_info_swift(path: Path, version: str, generated_at: str, image_count: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "// このファイルは scripts/build_images.py が生成します。手で編集しないでください。\n"
        "// A-17: アプリと B で画像の版識別子を目視照合するために使う。\n"
        "import Foundation\n\n"
        "enum ImageBuildInfo {\n"
        f"    static let version = \"{swift_string(version)}\"\n"
        f"    static let generatedAt: String? = \"{swift_string(generated_at)}\"\n"
        f"    static let imageCount = {image_count}\n"
        "}\n",
        encoding="utf-8",
    )


def clean_stale(directory: Path, keep: set) -> None:
    if not directory.exists():
        return
    for path in directory.glob("*.jpg"):
        if path.name not in keep:
            path.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description="A-17 商品画像ビルド")
    parser.add_argument("--csv", required=True, type=Path,
                        help="アプリが書き出した商品マスタ CSV（product_id 列を含む）")
    parser.add_argument("--originals", type=Path, default=DEFAULT_ORIGINALS,
                        help=f"原本ディレクトリ（既定: {DEFAULT_ORIGINALS}）")
    parser.add_argument("--app-out", type=Path, default=DEFAULT_APP_OUT,
                        help=f"レジ用画像の出力先（既定: {DEFAULT_APP_OUT}）")
    parser.add_argument("--web-out", type=Path, default=DEFAULT_WEB_OUT,
                        help=f"Web 用画像の出力先（既定: {DEFAULT_WEB_OUT}）")
    parser.add_argument("--info-swift", type=Path, default=INFO_SWIFT,
                        help=f"版識別子を書き込む Swift ファイル（既定: {INFO_SWIFT}）")
    parser.add_argument("--register-max", type=int, default=600,
                        help="レジ用画像の長辺ピクセル数（既定: 600）")
    parser.add_argument("--web-max", type=int, default=1200,
                        help="Web 用画像の長辺ピクセル数（既定: 1200）")
    parser.add_argument("--strict", action="store_true",
                        help="欠落・余剰・読み込めない画像があれば終了コード 1")
    args = parser.parse_args()

    product_ids = read_product_ids(args.csv)
    originals, issues = index_originals(args.originals)
    known = set(product_ids)

    for pid in product_ids:
        if not ID_PATTERN.match(pid):
            issues.append(Issue("invalid_id", f"ファイル名に使えない商品ID: {pid}"))

    missing = [pid for pid in product_ids if pid not in originals]
    for pid in missing:
        issues.append(Issue("missing", f"原本がありません: {pid}"))

    extra = sorted(set(originals) - known)
    for pid in extra:
        issues.append(Issue("extra", f"商品マスタにない原本: {originals[pid].name}"))

    args.app_out.mkdir(parents=True, exist_ok=True)
    args.web_out.mkdir(parents=True, exist_ok=True)

    rows: List[Dict[str, str]] = []
    source_hashes: List[str] = []
    produced_app: set = set()
    produced_web: set = set()
    converted = 0

    for pid in product_ids:
        source = originals.get(pid)
        has_image = "0"
        source_hash = ""
        if source is not None:
            size = image_info(source)
            if size is None:
                issues.append(Issue("unreadable", f"画像として読み込めません: {source.name}"))
            else:
                width, height = size
                if width / height > 4 or height / width > 4:
                    issues.append(Issue("aspect", f"極端な縦横比です: {source.name} ({width}x{height})"))
                if source.stat().st_size > 20 * 1024 * 1024:
                    issues.append(Issue("large", f"ファイルサイズが20MBを超えています: {source.name}"))
                register_name = f"{pid}.jpg"
                web_name = f"{pid}.jpg"
                if (make_jpeg(source, args.app_out / register_name, args.register_max)
                        and make_jpeg(source, args.web_out / web_name, args.web_max)):
                    has_image = "1"
                    source_hash = sha256(source)
                    source_hashes.append(f"{pid}:{source_hash}")
                    produced_app.add(register_name)
                    produced_web.add(web_name)
                    converted += 1
        rows.append({
            "product_id": pid,
            "register_file": f"{pid}.jpg" if has_image == "1" else "",
            "web_file": f"{pid}.jpg" if has_image == "1" else "",
            "has_image": has_image,
            "source_sha256": source_hash,
        })

    clean_stale(args.app_out, produced_app)
    clean_stale(args.web_out, produced_web)

    manifest = args.web_out / "manifest.csv"
    with manifest.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["product_id", "register_file", "web_file", "has_image", "source_sha256"])
        writer.writeheader()
        writer.writerows(rows)

    version = hashlib.sha256("\n".join(sorted(source_hashes)).encode("utf-8")).hexdigest()[:12]
    if not source_hashes:
        version = "no-images"
    generated_at = __import__("datetime").datetime.now().astimezone().isoformat(timespec="seconds")
    (args.web_out / "version.txt").write_text(version + "\n", encoding="utf-8")
    write_info_swift(args.info_swift, version, generated_at, converted)

    print(f"商品 {len(product_ids)}件 / 画像 {converted}件 / 版 {version}")
    print(f"  レジ用: {args.app_out}")
    print(f"  Web用:  {args.web_out}")
    print(f"  対応一覧: {manifest}")

    if issues:
        print("")
        print(f"確認が必要な項目: {len(issues)}件")
        for issue in issues:
            print(f"  [{issue.kind}] {issue.detail}")
        if args.strict:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
