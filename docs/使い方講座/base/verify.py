#!/usr/bin/env python3
"""base/ の正となるコードがswiftで動くか、期待される出力と一致するかを確認する。

    python3 verify.py            # 両方
    python3 verify.py types      # 型だけ
    python3 verify.py logic      # 型＋標準ロジック＋通しの確認
    python3 verify.py 08         # 追加lessonのコードも確認

何をしているか:
  1. `2_型定義.md` / `3_標準ロジック.md` の中の ```swift ブロックを連結して
     1本のswiftファイルにする
  2. `swiftc -typecheck` で型チェック
  3. `swift` で実行し、出力を「期待される出力」と1行ずつ照合する
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Optional

BASE = Path(__file__).resolve().parent
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
OFF = "\033[0m"


def swift_blocks(md: Path):
    return re.findall(r"```swift\n(.*?)```", md.read_text(encoding="utf-8"), re.S)


def expected_after(md: Path, heading: str):
    """見出しのあとにある「期待される出力」コードブロックを返す"""
    text = md.read_text(encoding="utf-8")
    i = text.find(heading)
    if i < 0:
        return None
    j = text.find("**期待される出力**", i)
    if j < 0:
        return None
    m = re.search(r"```\n(.*?)```", text[j:], re.S)
    return m.group(1).rstrip() if m else None


def typecheck_run(src: str, label: str):
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "Main.swift"
        f.write_text(src, encoding="utf-8")
        r = subprocess.run(["swiftc", "-typecheck", str(f)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"{RED}NG{_OFF} {label}: 型チェックでエラー")
            print("\n".join(r.stderr.split("\n")[:20]))
            return None
        print(f"{GREEN}OK{OFF} {label}: 型チェック")
        r2 = subprocess.run(["swift", str(f)], capture_output=True, text=True)
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


def check(label: str, src: str, want: Optional[str]):
    got = typecheck_run(src, label)
    if got is None:
        return 1
    if want is None:
        print(f"{YELLOW}--{OFF} {label}: 「期待される出力」が見つからない（照合をスキップ）")
        return 0
    bad = diff_lines(got, want)
    if bad:
        print(f"{RED}NG{_OFF} {label}: 出力が {len(bad)} 行違う")
        for n, w, a in bad[:15]:
            print(f"  {n}行目 期待: {w}")
            print(f"        実際: {a}")
        return 1
    print(f"{GREEN}OK{OFF} {label}: 出力も一致（{len(want.split(chr(10)))}行）")
    return 0


def main() -> int:
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    fail = 0

    t_md = BASE / "2_型定義.md"
    t_blocks = swift_blocks(t_md)
    # 2_型定義.md の swift ブロック = [型, JSON方針, 動作確認]
    if what in ("all", "types", "logic"):
        if what != "logic":
            fail += check("Types.swift", "\n".join(t_blocks[:3]),
                          expected_after(t_md, "## 4. 動作確認"))

    if what in ("all", "logic"):
        l_md = BASE / "3_標準ロジック.md"
        l_blocks = swift_blocks(l_md)
        # ロジックのブロックの最後が「通しの確認」。型・JSON方針 Definitionsと抱き合わせる
        src = t_blocks[0] + "\n" + t_blocks[1] + "\n\n" + "\n\n".join(l_blocks)
        fail += check("3_標準ロジック.md（通し）", src,
                      expected_after(l_md, "## 9. 通しの確認"))

    if what not in ("all", "types", "logic"):
        p = BASE / (what if what.endswith(".md") else what + ".md")
        if not p.exists():
            print(f"{RED}NG{_OFF} {p.name} が見つからない")
            return 1
        fail += check(p.name, "\n".join(swift_blocks(p)),
                      expected_after(p, "#"))

    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())