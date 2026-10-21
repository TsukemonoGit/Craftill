#!/usr/bin/env python3
"""base/ の正となるコードがswiftで動くか、期待される出力と一致するかを確認する。

    python3 verify.py            # 型・標準ロジック・カート編集・状態機械・保存
    python3 verify.py types      # 型だけ
    python3 verify.py logic      # 型＋標準ロジック＋通しの確認
    python3 verify.py cart       # 型＋カート編集＋通しの確認
    python3 verify.py flow       # 型＋標準ロジック＋状態機械＋通しの確認
    python3 verify.py 08         # 追加lessonのコードも確認

    python3 verify.py bless logic   # 実行結果を「期待される出力」ブロックに書き込む
    python3 verify.py bless types|cart|flow|save

## bless について

`bless` は「いまの実行結果」を期待値として md に保存する。
**保存前に、出力が仕様どおりか目視で確認すること**（バグを期待値にしないため）。
標準ロジックは 3_標準ロジック.md §9 の表（確認できること）と照合する。

## コードブロックの書き方

` ```swift ` … コンパイル対象。このファイル内では**名前を重複させない**こと。
` ```swift NG ` … **わざと間違う例**。スキップする（直らないのが目的）。
` ```swift 断片 ` … 本文用の切りはし。スキップする。
` ```swiftui ` … SwiftUI。スキップする（`swift ファイル.swift` では動かない）。

## セクション名（3_標準ロジック.md）

標準ロジックの swift ブロックは、1行目の `// @section: 名前` で識別する。
PRELUDE ではブロック番号ではなく名前で指定し、依存（DEPS）は自動で補う。
ブロックが増減しても、番号がずれない。

何をしているか:
  1. `2_型定義.md` / `3_標準ロジック.md` / `5_カート編集.md` の中の
     コンパイル対象ブロックを連結して1本のswiftファイルにする
  2. `swiftc -typecheck` で型チェック
  3. `swift` で実行し、出力を「期待される出力」と1行ずつ照合する
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional

BASE = Path(__file__).resolve().parent

# 実行するタイムゾーン。**期待される出力は JST で書いたもの**（A-19-5 のローカル日付）。
# 検証端末のタイムゾーンに左右されないよう、固定します。
#   （1_700_000_000 = 2023-11-14 22:13 UTC。JST なら 2023-11-15、UTC なら 2023-11-14）
TZ = "Asia/Tokyo"

# 期待値が未生成のときに md へ置くプレースホルダ
PLACEHOLDER = "（未生成）"

LG = "3_標準ロジック.md"


def swift_env() -> dict:
    """swift を呼ぶときの環境変数。タイムゾーンを固定する。"""
    env = dict(os.environ)
    env["TZ"] = TZ
    return env


# 自動検証の対象外（理由は NO_VERIFY）
#   03_レッスン.md … レッスン1〜8 が1つのファイルに混在し、
#                    Swift基本／SwiftUI／永続化で文法が違うため1本に連結できない
NO_VERIFY = {"03_レッスン.md"}

# 標準ロジックのセクション依存。左のセクションを使うと、右も自動で連結される
DEPS = {
    "stock":   ["helpers"],
    "commit":  ["method", "stock"],
    "suspend": ["method"],
    "edit":    ["helpers"],
    "csv":     ["helpers", "edit", "stock"],
    "summary": ["day"],
    "period":  ["summary", "day"],
    "refund":  ["helpers"],
}

# レッスンを検証するとき、先に置く base の正となるコード
#   (ファイル名, 使うブロック) のリスト
#     [0, 1]              … 0番目と1番目（番号）
#     ["totals", "stock"] … セクション名（3_標準ロジック.md のみ。依存は自動）
#     "all_but_last"      … 最後の1つ（通しの確認）を除く
PRELUDE = {
    "10_野良商品を追加する": [
        ("2_型定義.md", [0, 1]),
        ("5_カート編集.md", "all_but_last"),
        (LG, ["stock"]),
    ],
    "07_カートの種類ごとの追加ルール": [
        ("2_型定義.md", [0, 1]),
        ("5_カート編集.md", "all_but_last"),
    ],
    "09_カートを編集する": [
        ("2_型定義.md", [0, 1]),
        ("5_カート編集.md", "all_but_last"),
    ],
    "31_全角のIDを半角にする": [
        ("2_型定義.md", [0, 1]),
        ("5_カート編集.md", "all_but_last"),
    ],
    "22_在庫を手動調整する": [
        ("2_型定義.md", [0, 1]),
        (LG, ["stock", "method", "adjust"]),
    ],
    "12_会計を完了させる": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "method", "stock", "commit", "suspend", "void", "adjust", "summary"]),
    ],
    "18_販売を取り消す": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "method", "stock", "commit", "suspend", "void", "day", "summary"]),
    ],
    "15_カート画面をSwiftUIで作る": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals"]),
        ("5_カート編集.md", "all_but_last"),
    ],
    "16_現金の会計画面": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "method", "stock", "commit"]),
        ("6_会計の状態機械.md", "all_but_last"),
    ],
    "58_総合問題2_レジ画面を1本にする": [
        ("2_型定義.md", [0, 1]),
        ("5_カート編集.md", "all_but_last"),
        (LG, ["totals", "method", "stock", "commit", "suspend", "day", "summary"]),
        ("6_会計の状態機械.md", "all_but_last"),
    ],
    "41_在庫変動ログを記録する": [
        ("2_型定義.md", [0, 1]),
        (LG, ["method", "stock", "commit", "void", "adjust"]),
    ],
    "38_日時をISO8601にする": [
        ("2_型定義.md", [0, 1]),
    ],
    "47_SQLiteで在庫を保存する": [
        ("2_型定義.md", [0, 1]),
        (LG, ["method", "stock", "commit"]),
    ],
    "57_総合問題1_ロジックを1本にまとめる": [
        ("2_型定義.md", [0, 1]),
        ("5_カート編集.md", "all_but_last"),
        (LG, ["totals", "method", "stock", "commit", "suspend", "void", "adjust", "day", "summary"]),
    ],
    "08_在庫を減らす": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "method", "stock", "commit"]),
    ],
    "11_支払方法と合計の内訳": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "method"]),
        ("6_会計の状態機械.md", "all_but_last"),
    ],
    "20_公開用スナップショットを作る": [
        ("2_型定義.md", [0, 1]),
        (LG, ["snapshot"]),
    ],
    "40_販売記録を書き出す": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "method", "stock", "commit", "suspend", "day", "summary"]),
    ],
    "17_集計する": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "method", "stock", "day", "summary"]),
    ],
    "28_一点物型の重複を防ぐ": [
        ("2_型定義.md", [0, 1]),
        ("5_カート編集.md", "all_but_last"),
    ],
    "29_在庫超過を防ぐ": [
        ("2_型定義.md", [0, 1]),
        ("5_カート編集.md", "all_but_last"),
    ],
    "30_SOLD OUTを判定する": [
        ("2_型定義.md", [0, 1]),
        ("5_カート編集.md", "all_but_last"),
    ],
    "56_会計の状態を切り替える": [
        ("2_型定義.md", [0, 1]),
        (LG, "all_but_last"),
        ("6_会計の状態機械.md", "all_but_last"),
    ],
    "19_会計状態をまるごと保存する": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "stock"]),
        ("6_会計の状態機械.md", "all_but_last"),
    ],
    "24_IDを採番する": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "method", "stock", "commit"]),
    ],
    "25_オプショナルを「―（現金）」にする": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "method"]),
    ],
    "32_属性ラベルを取り出す": [
        # 型（ProductType.attrLabel1〜3 / Product.attr1〜3 / attrs / attrText(in:)）だけで足りる
        ("2_型定義.md", [0, 1]),
    ],
    "33_お釣りと確定ボタンを作る": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "method"]),
        ("6_会計の状態機械.md", "all_but_last"),
    ],
    "34_併用合計の請求額を計算する": [
        ("2_型定義.md", [0, 1]),
        (LG, ["totals", "method"]),
        ("6_会計の状態機械.md", "all_but_last"),
    ],
}

RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
OFF = "\033[0m"

SECTION_RE = re.compile(r"\A\s*// @section: (\w+)")
EXPECT_MARK = "**期待される出力**"


def swift_blocks(md: Path):
    """```swift だけを取り出す。

```swift NG / ```swift 断片 / ```swiftui は落とす
    （info のうしろに補足があるものは対象外）。
    """
    out = []
    for m in re.finditer(r"```(\S*)([^\n]*)\n(.*?)```", md.read_text(encoding="utf-8"), re.S):
        if m.group(1) == "swift" and not m.group(2).strip():
            out.append(m.group(3))
    return out


def section_name(block: str) -> Optional[str]:
    m = SECTION_RE.match(block)
    return m.group(1) if m else None


def resolve_sections(blocks, names):
    """セクション名の指定（と依存）から、ファイル内の並び順でブロックを返す"""
    by_name = {}
    for b in blocks:
        n = section_name(b)
        if n:
            by_name[n] = b
    want = set()
    stack = list(names)
    while stack:
        n = stack.pop()
        if n in want:
            continue
        if n not in by_name:
            raise SystemExit(f"{RED}NG{OFF} セクション '{n}' が見つからない"
                             f"（有効: {', '.join(by_name)}）")
        want.add(n)
        stack.extend(DEPS.get(n, []))
    return [b for b in blocks if section_name(b) in want]


def pick_blocks(name: str, which):
    blocks = swift_blocks(BASE / name)
    if which == "all_but_last":
        return blocks[:-1]
    if which and isinstance(which[0], str):
        return resolve_sections(blocks, which)
    return [blocks[i] for i in which]


def prelude_src(lesson_stem: str) -> str:
    """レッスンの土台になる base のコードを連結して返す"""
    spec = PRELUDE.get(lesson_stem)
    if not spec:
        return ""
    parts = []
    for name, which in spec:
        parts.append("\n\n".join(pick_blocks(name, which)))
    return "\n\n".join(parts) + "\n\n"


def expected_after(md: Path, heading: str):
    """見出しのあとにある「期待される出力」コードブロックを返す"""
    text = md.read_text(encoding="utf-8")
    i = text.find(heading)
    if i < 0:
        return None
    j = text.find(EXPECT_MARK, i)
    if j < 0:
        return None
    m = re.search(r"```\n(.*?)```", text[j:], re.S)
    return m.group(1).rstrip() if m else None


def write_expected(md: Path, heading: str, got: str) -> bool:
    """見出しのあとの「期待される出力」ブロックを、実行結果で置き換える"""
    text = md.read_text(encoding="utf-8")
    i = text.find(heading)
    j = text.find(EXPECT_MARK, i) if i >= 0 else -1
    if j < 0:
        print(f"{RED}NG{OFF} {md.name}: 「{EXPECT_MARK}」が見つからず、書き込めない")
        return False
    m = re.compile(r"```\n(.*?)```", re.S).search(text, j)
    if not m:
        print(f"{RED}NG{OFF} {md.name}: 期待出力のコードブロックが見つからず、書き込めない")
        return False
    new = text[:m.start(1)] + got + "\n" + text[m.end(1):]
    md.write_text(new, encoding="utf-8")
    print(f"{YELLOW}BLESS{OFF} {md.name}: 期待される出力を更新（{len(got.splitlines())}行）。"
          "内容を目視で確認すること")
    return True


def typecheck_run(src: str, label: str):
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "Main.swift"
        f.write_text(src, encoding="utf-8")
        r = subprocess.run(["swiftc", "-typecheck", str(f)],
                           capture_output=True, text=True, env=swift_env())
        if r.returncode != 0:
            print(f"{RED}NG{OFF} {label}: 型チェックでエラー")
            print("\n".join(r.stderr.split("\n")[:20]))
            return None
        print(f"{GREEN}OK{OFF} {label}: 型チェック")
        r2 = subprocess.run(["swift", str(f)], capture_output=True, text=True, env=swift_env())
        if r2.returncode != 0:
            print(f"{RED}NG{OFF} {label}: 実行でエラー")
            print("\n".join(r2.stderr.split("\n")[:20]))
            return None
        return r2.stdout.rstrip()


def diff_lines(got: str, want: str):
    g = got.split("\n")
    w = want.split("\n")
    bad = []
    for i in range(max(len(g), len(w))):
        a = g[i] if i < len(g) else "<行が無い>"
        b = w[i] if i < len(w) else "<行が無い>"
        if a != b:
            bad.append((i + 1, b, a))
    return bad


def check(label: str, src: str, want: Optional[str],
          bless_to: Optional[tuple] = None, strict: bool = False):
    """型チェック → 実行 → 期待値と照合。

    bless_to=(md, heading) で、`bless` 指定時に結果を書き込む。
    strict=True（base の基準ファイル）では、期待値が無い・未生成なら失敗にする。
    """
    got = typecheck_run(src, label)
    if got is None:
        return 1

    if BLESS and bless_to:
        print(got)
        return 0 if write_expected(bless_to[0], bless_to[1], got) else 1

    if want is None or want.strip() == PLACEHOLDER:
        if strict:
            print(f"{RED}NG{OFF} {label}: 期待される出力が未生成。"
                  f"出力を目視確認後、`python3 verify.py bless <対象>` で生成する")
            return 1
        print(f"{YELLOW}--{OFF} {label}: 「期待される出力」が見つからない（照合をスキップ）")
        return 0

    bad = diff_lines(got, want)
    if bad:
        print(f"{RED}NG{OFF} {label}: 出力が {len(bad)} 行違う")
        for n, w, a in bad[:15]:
            print(f"  {n}行目 期待: {w}")
            print(f"        実際: {a}")
        return 1
    print(f"{GREEN}OK{OFF} {label}: 出力も一致（{len(want.split(chr(10)))}行）")
    return 0


ARGS = [a for a in sys.argv[1:] if a != "bless"]
BLESS = "bless" in sys.argv[1:]


def main() -> int:
    what = ARGS[0] if ARGS else "all"
    fail = 0

    t_md = BASE / "2_型定義.md"
    t_blocks = swift_blocks(t_md)
    # 2_型定義.md の swift ブロック = [型, JSON方針, 動作確認]
    if what in ("all", "types"):
        fail += check("Types.swift", "\n".join(t_blocks[:3]),
                      expected_after(t_md, "動作確認"),
                      bless_to=(t_md, "動作確認"), strict=True)

    if what in ("all", "logic"):
        l_md = BASE / LG
        l_blocks = swift_blocks(l_md)
        src = t_blocks[0] + "\n" + t_blocks[1] + "\n\n" + "\n\n".join(l_blocks)
        fail += check("3_標準ロジック.md（通し）", src,
                      expected_after(l_md, "## 9. 通しの確認"),
                      bless_to=(l_md, "## 9. 通しの確認"), strict=True)

    if what in ("all", "flow"):
        f_md = BASE / "6_会計の状態機械.md"
        f_blocks = swift_blocks(f_md)
        l_blocks = swift_blocks(BASE / LG)
        src = t_blocks[0] + "\n" + t_blocks[1] + "\n\n" + "\n\n".join(l_blocks[:-1]) \
              + "\n\n" + "\n\n".join(f_blocks)
        fail += check("6_会計の状態機械.md（通し）", src,
                      expected_after(f_md, "通しの確認"),
                      bless_to=(f_md, "通しの確認"), strict=True)

    if what in ("all", "save"):
        sv_md = BASE.parent / "19_会計状態をまるごと保存する.md"
        src = prelude_src(sv_md.stem) + "\n".join(swift_blocks(sv_md))
        fail += check(sv_md.name, src, expected_after(sv_md, "通しの確認"),
                      bless_to=(sv_md, "通しの確認"))

    if what in ("all", "cart"):
        c_md = BASE / "5_カート編集.md"
        c_blocks = swift_blocks(c_md)
        src = t_blocks[0] + "\n" + t_blocks[1] + "\n\n" + "\n\n".join(c_blocks)
        fail += check("5_カート編集.md（通し）", src,
                      expected_after(c_md, "通しの確認"),
                      bless_to=(c_md, "通しの確認"), strict=True)

    if what not in ("all", "types", "logic", "cart", "flow", "save"):
        p = BASE.parent / (what if what.endswith(".md") else what + ".md")
        if not p.exists():
            print(f"{RED}NG{OFF} {p.name} が見つからない")
            return 1
        if p.name in NO_VERIFY:
            print(f"{YELLOW}--{OFF} {p.name}: 自動検証対象外（NO_VERIFY）")
            return 0
        blocks = swift_blocks(p)
        if not blocks:
            print(f"{YELLOW}--{OFF} {p.name}: ```swift ブロックなし"
                  "（base/ の正を参照するレッスン）")
            return 0
        src = prelude_src(p.stem) + "\n".join(blocks)
        fail += check(p.name, src, expected_after(p, "#"))

    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())