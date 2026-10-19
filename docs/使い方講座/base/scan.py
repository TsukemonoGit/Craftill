#!/usr/bin/env python3
"""日本語の教材に混ざった「文字化け・無関係な英単語・簡体字」を検出する。

    python3 scan.py             # レッスン群を全部
    python3 scan.py 24          # ファイル名の一部を指定
    python3 scan.py --strict 24 # 許容語も一覧に出す

検出するのは 3 つ:
  1. **U+FFFD**（�）… 文字化け・入力途中の欠損
  2. **許容語以外の英単語** … 日本語の文中に英単語がそのまま入っている
  3. **簡体字** … 日本語の教材に混ざった中国語

コードフェンス（``` … ```）の中身は対象外。Swift のキーワードは在里面が正常だから。
"""
import re
import sys
from pathlib import Path

BASE = Path(__file__).resolve().parent
LESSONS = BASE.parent

# ---- 教材がそのまま使う英字（略語・製品名・列名など）----------------------
ALLOWED = {
    # 略語・技術用語
    "ID", "IDs", "QR", "CSV", "JSON", "PIN", "DB", "SQL", "SQLite", "HTTP", "HTTPS",
    "API", "URL", "UTF", "BOM", "CRLF", "RFC", "NFC", "LNURL", "KV", "POS", "MAC",
    "UTC", "JST", "sats", "sat", "BTC", "WoS", "ISO", "UI", "UX", "SOLD", "OUT",
    # 商品ID の接頭辞（例として文中に出る）
    "ST", "KH", "TB",
    # 製品名・フレームワーク名
    "Swift", "swift", "swiftc", "typecheck", "Mac", "iPad", "iPhone", "PhotoKit",
    "Cloudflare", "WoS", "Neo", "Bolt", "Lightning", "Address", "POS", "Card",
    "App", "Store", "Watch", "Excel", "Xcode", "JavaScript", "TypeScript", "Python",
    "Svelte", "git", "Foundation", "SwiftUI", "Keychain", "Combine", "Observable",
    "NumberFormatter", "DateFormatter", "JSONEncoder", "JSONDecoder", "UserDefaults",
    "FileManager", "NotificationCenter", "URLSession", "NavigationStack",
    "View", "store", "State", "Run", "Xcode", "macOS", "iOS", "iPadOS", "app",
    # ファイル名の一部
    "md", "csv", "json", "png", "jpg", "jpeg", "txt", "tsx", "ts", "js", "py",
    "verify", "scan", "base", "lesson", "siyou", "Types", "Main", "BOM",
}

# ---- 日本語に無い簡体字を含む語 ------------------------------------------
#   ※ 同じ漢字でも「確認」（日本）と「确认」（中国）は別物。
#     「確/設/発/終…」のwey分别是日本字。こちらだけ簡体。
SIMPLIFIED = [
    "规范", "时间", "日期", "数据", "状态", "销售", "确认", "记录", "编号", "种类",
    "目录", "文件夹", "设置", "网络", "离线", "传输", "发送", "请求", "响应",
    "错误", "异常", "日志", "台帐", "字段", "时区", "终端", "库存", "金额",
    "规则", "单价", "总计", "校验", "缺货", "入库", "出库", "单据", "结账",
    "验证", "验收", "测试用例", "实现", "开发", "部署", "读取", "写入",
    "删除", "修改", "新增", "查询", "列表", "详情", "页面", "按钮", "输入框",
    "关闭", "打开", "启动",
]
# ※「保存」「运行」「接口」は日本語にもあるので **入れない**。
#   同じ漢字でも「確認」（日本）と「确认」（中国）は別物、という区別を基本にする。


def strip_code_fences(text: str) -> list[tuple[int, str]]:
    """コードフェンスの外だけを通しで返す。[(行番号, 行)]"""
    out: list[tuple[int, str]] = []
    inside = False
    for n, line in enumerate(text.split("\n"), 1):
        if line.lstrip().startswith("```"):
            inside = not inside
            continue
        if not inside:
            out.append((n, line))
    return out


def scan(path: Path, strict: bool) -> list[str]:
    hits: list[str] = []
    for n, line in strip_code_fences(path.read_text(encoding="utf-8")):

        if "�" in line:
            hits.append(f"{path.name}:{n}: 文字化け(FFFD)   {line.strip()[:90]}")

        # インラインコード（`foo`）を除いた行だけを見る
        plain = re.sub(r"`[^`]*`", "", line)

        for m in re.finditer(r"[A-Za-z][A-Za-z']+", plain):
            w = m.group(0)
            if strict or w not in ALLOWED:
                hits.append(f"{path.name}:{n}: 英単語「{w}」  {line.strip()[:90]}")
                break

        for w in SIMPLIFIED:
            if w in plain:
                hits.append(f"{path.name}:{n}: 簡体字「{w}」  {line.strip()[:90]}")
                break

    return hits


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    strict = "--strict" in sys.argv
    with_spec = "--spec" in sys.argv
    only = args[0] if args else ""

    # 既定はレッスン群だけ。siyou.md（仕様書）は URL や製品名が大量に並ぶので
    # `--spec` を付けたときだけ見る。
    targets = sorted(LESSONS.rglob("*.md"))
    if with_spec:
        targets.append(LESSONS.parent / "siyou.md")
    if only:
        targets = [p for p in targets if only in p.name]
    targets = [p for p in targets if p.exists()]

    all_hits: list[str] = []
    for p in targets:
        all_hits += scan(p, strict)

    for h in all_hits:
        print(h)
    print(f"\n--- {len(targets)} ファイル / {len(all_hits)} 件"
          f"{'（--strict）' if strict else ''}")
    return 1 if all_hits else 0


if __name__ == "__main__":
    sys.exit(main())
