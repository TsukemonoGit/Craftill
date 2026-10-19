#!/usr/bin/env python3
"""base/ の正となるコードがswiftで動くか、期待される出力と一致するかを確認する。

    python3 verify.py            # 型・標準ロジック・カート編集
    python3 verify.py types      # 型だけ
    python3 verify.py logic      # 型＋標準ロジック＋通しの確認
    python3 verify.py cart       # 型＋カート編集＋通しの確認
    python3 verify.py flow       # 型＋標準ロジック＋状態機械＋通しの確認
    python3 verify.py 08         # 追加lessonのコードも確認

## コードブロックの書き方

` ```swift ` … コンパイル対象。このファイル内では**名前を重複させない**こと。
` ```swift NG ` … **わざと間違う例**。スキップする（直らないのが目的）。
` ```swift 断片 ` … 本文用の切りはし。スキップする。
` ```swiftui ` … SwiftUI。スキップする（`swift ファイル.swift` では動かない）。

何をしているか:
  1. `2_型定義.md` / `3_標準ロジック.md` / `5_カート編集.md` の中の
     コンパイル対象ブロックを連結して1本のswiftファイルにする
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

# 実行するタイムゾーン。**期待される出力は JST で書いたもの**（A-19-5 のローカル日付）。
# 検証端末のタイムゾーンに左右されないよう、固定します。
#   （1_700_000_000 = 2023-11-14 22:13 UTC。JST なら 2023-11-15、UTC なら 2023-11-14）
TZ = "Asia/Tokyo"


def swift_env() -> dict:
    """swift を呼ぶときの環境変数。タイムゾーンを固定する。"""
    import os
    env = dict(os.environ)
    env["TZ"] = TZ
    return env

# 自動検証の対象外（理由は NO_VERIFY）
#   03_レッスン.md … レッスン1〜8 が1つのファイルに混在し、
#                    Swift基本／SwiftUI／永続化で文法が違うため1本に連結できない
NO_VERIFY = {"03_レッスン.md"}

# レッスンを検証するとき、先に置く base の正となるコード
#   (ファイル名, 使うブロック) のリスト
#     [0, 1]         … 0番目と1番目
#     "all_but_last" … 最後の1つ（通しの確認）を除く
PRELUDE = {
    "10_野良商品を追加する": [
        ("2_型定義.md", [0, 1]),
        ("5_カート編集.md", "all_but_last"),
        ("3_標準ロジック.md", [2]),
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
        # base/3 §3 在庫検証 / §2 販売記録（§5 が依存）/ §6 手動調整
        ("3_標準ロジック.md", [2, 1, 6]),
    ],
    "12_会計を完了させる": [
        ("2_型定義.md", [0, 1]),
        # base/3 §1 合計 / §2 販売記録 / §3 在庫検証 / §4 確定 / §5 中断 / §6 調整 / §7 集計
        #        （7 は §6-0「集計の対象日」。12 では使わないので飛ばす）
        ("3_標準ロジック.md", [0, 1, 2, 3, 4, 5, 6, 8]),
    ],
    "18_販売を取り消す": [
        ("2_型定義.md", [0, 1]),
        # base/3 §1 合計 / §2 販売記録 / §3 在庫検証・減算 / §4 確定 / §5-1 中断 / §5-2 取消 / §6-0 対象日 / §7 集計
        ("3_標準ロジック.md", [0, 1, 2, 3, 4, 5, 7, 8]),
    ],
    "15_カート画面をSwiftUIで作る": [
        ("2_型定義.md", [0, 1]),
        # base/3 §1 合計 / base/5 §1〜§6（追加・編集・削除）
        ("3_標準ロジック.md", [0]),
        ("5_カート編集.md", "all_but_last"),
    ],
    "16_現金の会計画面": [
        ("2_型定義.md", [0, 1]),
        # base/3 §1 合計 / §2 販売記録 / §3 在庫検証・減算 / §4 確定
        ("3_標準ロジック.md", [0, 1, 2, 3]),
        # base/6 §1〜§7（遷移・文脈・イベント・遷移表・確認ダイアログ・適用・導出）
        ("6_会計の状態機械.md", "all_but_last"),
    ],
    "58_総合問題2_レジ画面を1本にする": [
        ("2_型定義.md", [0, 1]),
        # base/5 §1〜§6
        ("5_カート編集.md", "all_but_last"),
        # base/3 §1 合計 / §2 販売記録 / §3 在庫検証・減算 / §4 確定 / §5 中断と取消
        #        §6-0 対象日 / §7 集計
        ("3_標準ロジック.md", [0, 1, 2, 3, 4, 7, 8]),
        # base/6 §1〜§8（通しの確認は要らない）
        ("6_会計の状態機械.md", "all_but_last"),
    ],
    "41_在庫変動ログを記録する": [
        ("2_型定義.md", [0, 1]),
        # base/3 §2 販売記録 / §3 在庫検証・減算（initial・sale のログ）
        #        §4 確定 / §5-2 販売取消（void のログ）/ §6 手動調整（adjust のログ）
        ("3_標準ロジック.md", [1, 2, 3, 5, 6]),
    ],
    "38_日時をISO8601にする": [
        # base/2 §型 ＋ §10-A jsonEncoder / jsonDecoder（ISO 8601・タイムゾーン付き）
        ("2_型定義.md", [0, 1]),
    ],
    "47_SQLiteで在庫を保存する": [
        ("2_型定義.md", [0, 1]),
        # base/3 §2 販売記録 / §3 在庫検証・減算 / §4 確定
        ("3_標準ロジック.md", [1, 2, 3]),
    ],
    "57_総合問題1_ロジックを1本にまとめる": [
        ("2_型定義.md", [0, 1]),
        ("5_カート編集.md", "all_but_last"),
        # base/3 §1 合計 / §2 販売記録 / §3 在庫検証・減算 / §4 確定
        #        §5 中断と取消 / §6 手動調整 / §6-0 対象日 / §7 集計
        ("3_標準ロジック.md", [0, 1, 2, 3, 4, 5, 6, 7, 8]),
    ],
    "08_在庫を減らす": [
        ("2_型定義.md", [0, 1]),
        # base/3 §1 合計 / §2 販売記録 / §3 在庫検証・減算 / §4 確定
        ("3_標準ロジック.md", [0, 1, 2, 3]),
    ],
    "11_支払方法と合計の内訳": [
        ("2_型定義.md", [0, 1]),
        # base/3 §1 合計の表示2行 / §2 販売記録の組み立て（resolveMethod）
        ("3_標準ロジック.md", [0, 1]),
        # base/6 §1〜§7（canPayBySats を使う遷移表・cashDueJpy）
        ("6_会計の状態機械.md", "all_but_last"),
    ],
    "20_公開用スナップショットを作る": [
        ("2_型定義.md", [0, 1]),
        # base/3 §8 B 送信用スナップショットと送信ログ
        ("3_標準ロジック.md", [9]),
    ],
    "40_販売記録を書き出す": [
        ("2_型定義.md", [0, 1]),
        # base/3 §1 合計 / §2 販売記録 / §3 在庫検証・減算 / §4 確定
        #        §5-1 中断 / §6-0 対象日 / §7 集計
        ("3_標準ロジック.md", [0, 1, 2, 3, 4, 7, 8]),
    ],
    "17_集計する": [
        ("2_型定義.md", [0, 1]),
        # base/3 §1 合計 / §2 販売記録 / §3 在庫検証 / §6-0 対象日 / §7 集計
        ("3_標準ロジック.md", [0, 1, 2, 7, 8]),
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
        ("3_標準ロジック.md", "all_but_last"),
        ("6_会計の状態機械.md", "all_but_last"),
    ],
    "19_会計状態をまるごと保存する": [
        ("2_型定義.md", [0, 1]),
        ("3_標準ロジック.md", [0, 2]),          # §1 合計 と §3 在庫検証
        ("6_会計の状態機械.md", "all_but_last"),
    ],
    "24_IDを採番する": [
        ("2_型定義.md", [0, 1]),
        # base/3 §1 合計 / §2 販売記録（採番）／§3 在庫検証・減算 / §4 確定
        #        （§5 以降は使わないので飛ばす）
        ("3_標準ロジック.md", [0, 1, 2, 3]),
    ],
    "25_オプショナルを「―（現金）」にする": [
        ("2_型定義.md", [0, 1]),
        # base/3 §1 合計の表示2行（totalLines）/ §2 販売記録（resolveMethod・paidIn）
        ("3_標準ロジック.md", [0, 1]),
    ],
}


def prelude_src(lesson_stem: str) -> str:
    """レッスンの土台になる base のコードを連結して返す"""
    spec = PRELUDE.get(lesson_stem)
    if not spec:
        return ""
    parts = []
    for name, which in spec:
        blocks = swift_blocks(BASE / name)
        use = blocks[:-1] if which == "all_but_last" else [blocks[i] for i in which]
        parts.append("\n\n".join(use))
    return "\n\n".join(parts) + "\n\n"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
OFF = "\033[0m"


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


def check(label: str, src: str, want: Optional[str]):
    got = typecheck_run(src, label)
    if got is None:
        return 1
    if want is None:
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


def main() -> int:
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    fail = 0

    t_md = BASE / "2_型定義.md"
    t_blocks = swift_blocks(t_md)
    # 2_型定義.md の swift ブロック = [型, JSON方針, 動作確認]
    if what in ("all", "types", "logic"):
        if what != "logic":
            fail += check("Types.swift", "\n".join(t_blocks[:3]),
                          expected_after(t_md, "動作確認"))

    if what in ("all", "logic"):
        l_md = BASE / "3_標準ロジック.md"
        l_blocks = swift_blocks(l_md)
        src = t_blocks[0] + "\n" + t_blocks[1] + "\n\n" + "\n\n".join(l_blocks)
        fail += check("3_標準ロジック.md（通し）", src,
                      expected_after(l_md, "通しの確認"))

    if what in ("all", "flow"):
        f_md = BASE / "6_会計の状態機械.md"
        f_blocks = swift_blocks(f_md)
        l_blocks = swift_blocks(BASE / "3_標準ロジック.md")
        src = t_blocks[0] + "\n" + t_blocks[1] + "\n\n" + "\n\n".join(l_blocks[:-1]) \
              + "\n\n" + "\n\n".join(f_blocks)
        fail += check("6_会計の状態機械.md（通し）", src,
                      expected_after(f_md, "通しの確認"))

    if what in ("all", "save"):
        sv_md = BASE.parent / "19_会計状態をまるごと保存する.md"
        src = prelude_src(sv_md.stem) + "\n".join(swift_blocks(sv_md))
        fail += check(sv_md.name, src, expected_after(sv_md, "通しの確認"))

    if what in ("all", "cart"):
        c_md = BASE / "5_カート編集.md"
        c_blocks = swift_blocks(c_md)
        src = t_blocks[0] + "\n" + t_blocks[1] + "\n\n" + "\n\n".join(c_blocks)
        fail += check("5_カート編集.md（通し）", src,
                      expected_after(c_md, "通しの確認"))

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