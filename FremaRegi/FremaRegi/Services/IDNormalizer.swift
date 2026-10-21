import Foundation

// ════════════════════════════════════════════════════════════
// 手動入力の正規化（A-2）
// 全角→半角、小文字→大文字、空白除去。
// 接頭辞は種類定義と照合し、番号は種類の桁数でゼロ埋めする（例: mk8 → MK-008）。
// ════════════════════════════════════════════════════════════

enum IDNormalizer {

    /// 全角英数字・全角記号を半角に、小文字を大文字に変換し、空白を除く。
    static func normalize(_ raw: String) -> String {
        var out = ""
        for c in raw.precomposedStringWithCompatibilityMapping {   // NFKC: 全角→半角
            if c.isWhitespace { continue }
            out.append(Character(String(c).uppercased()))
        }
        return out
    }

    /// 正規化したID文字列を、種類定義（接頭辞・桁数）に従って商品IDにする。
    /// - 入力例: `MK-008` / `MK008` / `mk8` / `ＭＫ−８` → `MK-008`
    /// - 接頭辞がどの種類とも一致しなければ nil（存在しないID → 画面でエラー表示・A-2）
    static func resolveProductID(_ raw: String, types: [ProductType]) -> String? {
        let s = normalize(raw)
        guard !s.isEmpty else { return nil }
        // 長い接頭辞から照合する（例: MKX と MK の両方がある場合、MKX-008 は MK に先奪されない・A-2）
        let sorted = types.sorted { $0.idPrefix.count > $1.idPrefix.count }
        for t in sorted {
            let head = t.idPrefix + "-"
            let body: String
            if s.hasPrefix(head) {
                body = String(s.dropFirst(head.count))
            } else if s.hasPrefix(t.idPrefix) {
                body = String(s.dropFirst(t.idPrefix.count)).trimmingCharacters(in: ["-"])
            } else {
                continue
            }
            // この接頭辞で検証に失敗しても他種類の可能性があるので次へ進む（部分一致誤拒否の防止）
            guard isAsciiDigits(body), !body.isEmpty else { continue }
            let n = Int(body) ?? 0
            guard n >= 1 else { continue }
            let digits = String(n)
            guard digits.count <= t.idDigits else { continue }   // 桁数超過はこの種類では成立しない
            return head + String(repeating: "0", count: t.idDigits - digits.count) + digits
        }
        return nil
    }

    /// QR読み取りの内容から商品IDを取り出す（QR内容は商品ID文字列のみ・A-2）。
    /// 前後の空白・改行を除き、正規形のまま返す。補正はしない（スキャナー由来は正規形のはず）。
    static func fromQR(_ payload: String) -> String {
        normalize(payload)
    }

    /// 入力中に在庫ありの候補をサジェスト（A-2）。前方一致、公開・在庫ありのみ。
    static func suggestions(_ raw: String, inventory: [Product], types: [ProductType]) -> [Product] {
        let q = normalize(raw)
        guard !q.isEmpty else { return [] }
        return inventory.filter { p in
            p.isPublic && !isSoldOut(p, in: inventory, types: types) && p.id.hasPrefix(q)
        }.prefix(8).map { $0 }
    }
}
