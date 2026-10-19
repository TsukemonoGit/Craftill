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
    # Swift のキーワード・標準型（本文で `...` を付けずに書くことがある）
    "nil", "Optional", "enum", "struct", "class", "protocol", "extension",
    "func", "var", "let", "case", "switch", "guard", "if", "else", "return",
    "throws", "throw", "try", "async", "await", "import", "init", "self", "Self",
    "static", "mutating", "inout", "where", "in", "for", "while", "defer",
    "typealias", "public", "private", "internal", "fileprivate", "open",
    "true", "false", "some", "any", "lazy", "weak", "unowned",
    "Int", "Double", "String", "Bool", "Array", "Dictionary", "Set", "Data",
    "Date", "Error", "Result", "Codable", "Identifiable", "Equatable", "Hashable",
    "Binding", "MainActor", "Sendable", "URL",
    # Swift の練習レッスンに出る用語・API 名
    "Book", "Books", "Playgrounds", "Playground", "EXIF", "JS", "TS", "React",
    "Svelte", "Testing", "XCTest", "SHA", "FK", "Unix", "Sandbox", "entitlement",
    "encoder", "decoder", "getter", "setter", "init", "Console", "lldb", "Info",
    "Invoice", "CoreImage", "Web", "VS", "Variables", "Clean", "RawValue",
    "Priced", "Product", "ProductType", "Type", "Types", "offset", "push",
    "sheet", "early", "return", "main", "index", "id", "cart", "product",
    "OK", "NG", "VS Code", "MacBook", "UIKit", "Network", "ImageIO", "CryptoKit",
    "NWPathMonitor", "Observable", "StateObject", "Environment", "Scene",
    "WindowGroup", "NavigationLink", "NavigationSplitView", "sheet", "alert",
    "confirmationDialog", "Form", "List", "VStack", "HStack", "ZStack", "Text",
    "Button", "Image", "Label", "Toggle", "Picker", "TextField", "Spacer",
    "Personal", "Team", "Wi", "view", "TEXT", "INTEGER", "completedAt", "PK",
    "Worker", "Workers", "HEIC", "Photos", "Photo", "Build", "Folder", "Navigator",
    "File", "Inspector", "Bundle", "Target", "Scheme", "Signing", "Capability",
    "Environment", "Preview", "Canvas", "Inspector", "Debug", "Release",
    "OS", "Test", "print", "ON", "OFF", "Fi", "Wi", "po", "Team",
    "rejected", "Unit", "object", "priced", "rejected", "allowed", "needsConfirm",
    "needsPIN", "ok", "ng", "sale", "void", "adjust", "initial", "cash", "lightning",
    "mixed", "jpy", "registered", "adhoc", "counted", "unique", "none", "success",
    "failed", "completed", "suspended", "voided", "idle", "satsWaiting",
    "needsMethod", "needsCash", "done", "ProductPanel", "RegisterCore", "RegisterView",
    "Task", "Adhoc", "conform", "Assumptions", "Blank", "Organization", "Interface",
    "Associated", "Windows", "DOM", "Design", "Quick", "Wallet", "Vision", "Union",
    "Key", "Path", "LF", "Code", "Base", "Name", "New", "Id", "My", "Sign",
    "Capabilities", "Supported", "Destinations", "TARGETS", "Multiplatform", "Linux",
    "AVFoundation", "AppKit", "JSDoc", "QRView", "Warning", "BUG", "COUNT",
    "qty", "default", "destination", "decode", "field", "identifier", "identity",
    "line", "mac", "method", "name", "null", "or", "paid", "plist", "prefix",
    "reason", "snake", "type", "types", "body", "cashForSats", "sqlite", "svelte",
    "truthy", "tvOS", "free", "Collection", "Encoders", "Expressions", "Language",
    "Lesson", "Playground", "Blank", "Top", "Level", "allowed",
    "Guidelines", "SUM", "implementation", "SQLite", "INTEGER", "TEXT",
    "GitHub", "Git", "Commit", "Branch", "Merge", "Rebase", "Stash", "Remote",
    "Push", "Pull", "Fork", "Clone", "Issue", "PullRequest", "Markdown",
    "README", "LICENSE", "Package", "SwiftPM", "Dependency", "Binary",
    "entity", "do", "catch", "try", "Result", "throws", "Optional", "UIKit",
    "CoreImage", "CoreFoundation", "Foundation", "NSHomeDirectory", "plist",
    "SQLITE", "TRANSIENT", "ROLLBACK", "SUM", "COUNT", "bind",
    "Apple", "Camera", "Sandbox", "Signing", "General", "Simulator", "Xcode",
    "Help", "digits", "of", "Satoshi", "Wallet", "Docker", "Container", "Linux",
    "Homebrew", "Terminal", "Shell", "Bash", "Zsh", "Script", "Command",
    "watchOS", "visionOS", "Project", "Identifier", "Developer", "Program",
    "to", "Run", "Locally", "stock", "mode", "type_id", "id_prefix", "id_digits",
    "price_jpy", "price_sats", "stock_mode", "paid_in", "sale_id", "item_id",
    "product_id", "sale_items", "stock_movements", "sync_log", "product_types",
    "NULL", "OR", "AND", "falsy", "Values", "NOT",
    "NaN", "are", "Infinity", "exactly", "not", "at", "top", "level",
    # 列名（snake_case）と、その構成語
    "unit", "total", "price", "item", "items", "attr", "sync", "status",
    "snapshot", "sales", "result", "refunded", "received", "products",
    "movements", "image", "detail", "delta", "confirmed", "is", "public",
    "unit_price_jpy", "unit_price_sats", "total_jpy", "total_sats",
    "has_image", "image_ref", "updated_at", "confirmed_at", "completed_at",
    "received_jpy", "change_jpy", "name_snapshot", "item_type", "is_public",
    # 外部サービス・製品名
    "GB", "MiB", "CPU", "JPEG", "USB", "FAQ", "REST", "Pro", "LND", "NWC",
    "TestFlight", "AirDrop", "Flutter", "Catalyst", "Designed", "silicon",
    "Receive", "Point", "Sale", "Business", "Storage", "Edit", "Workers",
    "https", "xxx", "Amount", "Note", "Touch", "Native", "WebP", "ms", "Class",
    "FaceTime", "support", "forums", "portal", "developers", "smithery", "HD",
    "MacBook", "Neo", "A18", "iPad", "iPhone", "Wi", "Cellular", "Pro", "Max",
    "Cloudflare", "KV", "R2", "Workers", "Storage", "Edit", "API", "Token",
    "change", "log", "SD", "Safari", "Chrome", "Edge", "Firefox", "Browser",
    "label", "ref", "updated", "attr_label_1", "attr_label_2", "attr_label_3",
    "Nostr", "NIP", "Relay", "WebSocket", "JSON-RPC", "RPC", "Connect",
}

# ---- 日本語に無い簡体字を含む語 ------------------------------------------
#   ※ 同じ漢字でも「確認」（日本）と「确认」（中国）は別物。
#     「確・設・発・終」などは日本字。こちらには**中国だけの字**を入れる。
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

        # 「…」で囲まれた**引用**は、外部（Xcode・OS）のメッセージそのもの。
        # 翻訳できないので、中身は検査しない。
        plain = re.sub(r"「[^」]*」", "", plain)

        # URL は外部のもの。ドメイン名を英単語として数えない。
        plain = re.sub(r"https?://\S+", "", plain)
        plain = re.sub(r"\[[^\]]*\]\([^)]*\)", "", plain)   # Markdown リンク

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
