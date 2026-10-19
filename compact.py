#!/usr/bin/env python3

#ーーーーーーーーーーー
# 制約:
#--extra に指定しない固有名（ユーザー名 mono 単体など）は、パス形式（/Users/mono）でなければ残る。--extra mono=USER を追加すると、mono を含む他の単語（例: monorepo）も置換される。
#IPアドレス規則は、バージョン番号（1.2.3.4 形式）も置換する。誤検出の可能性がある。
#[IP] 等の置換は元に戻せない。元の output.json は別途保管すること。
#日本語の氏名・住所・電話番号は検出しない。必要なら --extra で指定する。
#仕様内容（決済・在庫設計）自体はマスクされない。
#ーーーーーーーーーーー

import argparse
import json
import re
import sys
from collections import Counter

SKIP_TYPES = {"model-switched"}

# (種別, パターン, 置換後)。上から順に適用する。
MASK_RULES = [
    ("秘密鍵", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.S), "[PRIVATE_KEY]"),
    ("APIキー", re.compile(r"\b(?:sk-[A-Za-z0-9_-]{10,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,})\b"), "[API_KEY]"),
    ("Bearer", re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{16,}"), "Bearer [TOKEN]"),
    ("代入シークレット", re.compile(r"(?i)\b(api[_-]?key|secret|token|passwd|password)\b(\s*[:=]\s*)(['\"]?)[^\s'\"]{6,}\3"), r"\1\2[REDACTED]"),
    ("メール", re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"), "[EMAIL]"),
    ("URL内認証", re.compile(r"(https?://)[^/\s:@]+:[^/\s@]+@"), r"\1[CREDENTIALS]@"),
    ("IPアドレス", re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), "[IP]"),
    ("ホームパス(mac)", re.compile(r"/Users/[^/\s\"'`]+"), "/Users/USER"),
    ("ホームパス(linux)", re.compile(r"/home/[^/\s\"'`]+"), "/home/USER"),
    ("ホームパス(win)", re.compile(r"[A-Za-z]:\\Users\\[^\\\s\"'`]+"), r"C:\\Users\\USER"),
    ("プロンプト", re.compile(r"\b[\w.-]+@[\w.-]*(?:MacBook|iMac|Mac-mini|Mac-Studio|Mac|PC|Desktop|Laptop)[\w.-]*"), "USER@HOST"),
    ("セッションID", re.compile(r"\b(?:ses|msg|prt|prj)_[A-Za-z0-9]{10,}\b"), "[ID]"),
    ("長いhex", re.compile(r"\b[0-9a-f]{32,}\b"), "[HEX]"),
]


def find_messages(data):
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for key in ("messages", "items"):
            if isinstance(data.get(key), list):
                return data[key]
    return []


def get_role(msg):
    info = msg.get("info") if isinstance(msg.get("info"), dict) else {}
    for src in (msg, info):
        for key in ("role", "author", "sender", "from"):
            v = src.get(key)
            if isinstance(v, str) and v:
                return v
    t = msg.get("type")
    if t in ("user", "assistant", "agent", "ai"):
        return t
    return "unknown"


def get_text(msg):
    texts = []
    parts = msg.get("parts")
    if isinstance(parts, list):
        for p in parts:
            if not isinstance(p, dict) or p.get("type") != "text":
                continue
            if p.get("synthetic") or p.get("ignored"):
                continue
            if isinstance(p.get("text"), str):
                texts.append(p["text"])
    t = msg.get("text")
    if isinstance(t, str):
        texts.append(t)
    c = msg.get("content")
    if isinstance(c, str):
        texts.append(c)
    elif isinstance(c, list):
        for p in c:
            if isinstance(p, dict) and p.get("type") == "text" and isinstance(p.get("text"), str):
                texts.append(p["text"])
    return "\n".join(texts)


def normalize(s):
    s = s.replace("\r\n", "\n")
    s = re.sub(r"[ \t]+\n", "\n", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    return s.strip()


def build_literal_rules(data, extras):
    """JSONの info から固有文字列を拾い、リテラル置換ルールにする。"""
    rules = []
    info = data.get("info") if isinstance(data, dict) and isinstance(data.get("info"), dict) else {}
    loc = info.get("location") if isinstance(info.get("location"), dict) else {}
    directory = loc.get("directory")
    if isinstance(directory, str) and len(directory) > 3:
        rules.append(("info.directory", directory, "[PROJECT_DIR]"))
    for key in ("id", "projectID"):
        v = info.get(key)
        if isinstance(v, str) and len(v) >= 8:
            rules.append((f"info.{key}", v, "[ID]"))
    for item in extras:
        if "=" not in item:
            sys.exit(f"--extra は '元=置換後' 形式で指定すること: {item}")
        src, dst = item.split("=", 1)
        if not src:
            sys.exit(f"--extra の元文字列が空: {item}")
        rules.append(("extra", src, dst))
    # 長い文字列を先に置換（部分一致による取りこぼしを防ぐ）
    rules.sort(key=lambda r: -len(r[1]))
    return rules


def mask(text, literal_rules, counter):
    for name, src, dst in literal_rules:
        n = text.count(src)
        if n:
            counter[name] += n
            text = text.replace(src, dst)
    for name, pat, dst in MASK_RULES:
        text, n = pat.subn(dst, text)
        if n:
            counter[name] += n
    return text


def inspect(messages):
    print(f"メッセージ数: {len(messages)}")
    keys = Counter()
    types = Counter()
    for m in messages:
        if isinstance(m, dict):
            keys.update(m.keys())
            types[str(m.get("type"))] += 1
    print("トップレベルキー:", dict(keys))
    print("type の値:", dict(types))
    for i, m in enumerate(messages[:3]):
        if isinstance(m, dict):
            print(f"--- [{i}] キー: {list(m.keys())}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output", nargs="?")
    ap.add_argument("--max-chars", type=int, default=0,
                    help="1メッセージあたりの最大文字数。0で無制限（デフォルト）")
    ap.add_argument("--inspect", action="store_true", help="構造を表示して終了")
    ap.add_argument("--no-mask", action="store_true", help="個人情報のマスクを無効化")
    ap.add_argument("--extra", action="append", default=[], metavar="元=置換後",
                    help="追加の固定文字列置換。複数指定可（例: --extra Craftill=PROJECT）")
    args = ap.parse_args()

    with open(args.input, encoding="utf-8") as f:
        data = json.load(f)

    messages = find_messages(data)
    if not messages:
        sys.exit("messages が見つからない。JSON構造を確認すること。")

    if args.inspect:
        inspect(messages)
        return
    if not args.output:
        sys.exit("出力ファイルを指定すること。")

    literal_rules = [] if args.no_mask else build_literal_rules(data, args.extra)
    counter = Counter()

    blocks = []
    prev = None
    for m in messages:
        if not isinstance(m, dict) or m.get("type") in SKIP_TYPES:
            continue
        text = normalize(get_text(m))
        if not text:
            continue
        if not args.no_mask:
            text = mask(text, literal_rules, counter)
        if text == prev:
            continue
        prev = text
        if args.max_chars and len(text) > args.max_chars:
            omitted = len(text) - args.max_chars
            text = text[: args.max_chars] + f"\n[...{omitted}文字省略]"
        blocks.append(f"[{get_role(m)}]\n{text}")

    out = "\n\n".join(blocks) + "\n"
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(out)

    print(f"メッセージ数: {len(blocks)} / 文字数: {len(out)}", file=sys.stderr)
    if args.no_mask:
        print("マスク: 無効", file=sys.stderr)
    elif counter:
        print("マスク件数:", file=sys.stderr)
        for k, v in counter.most_common():
            print(f"  {k}: {v}", file=sys.stderr)
    else:
        print("マスク対象: なし", file=sys.stderr)


if __name__ == "__main__":
    main()