import Foundation

// ════════════════════════════════════════════════════════════
// CSV 字句解析（RFC 4180）と書き出し（A-1）
// 「3_標準ロジック.md」に含めなかった部分（§6-2 の注記：
// 「CSV の字句解析（RFC 4180・BOM・改行）は含まない」）をここで実装する。
// 解析結果は `CSVTable`（ヘッダ＋行）になり、標準ロジックの `parse*CSV` に渡す。
// ════════════════════════════════════════════════════════════

/// RFC 4180 準拠のパーサ。UTF-8（BOM 有無不问）、改行は CRLF／LF どちらも可。
/// 値の前後の空白は**標準ロジック側**（`cell`）で取り除くので、ここでは保持する。
enum CSVParser {
    /// テキスト全体 → セルの二次元配列（空行は無視しない。行の判定は呼び出し側）
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex

        // BOM を外す
        if text.hasPrefix("\u{FEFF}") { i = text.index(after: i) }

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            // 完全な空行（1セルが空文字のみ）は無視（A-1）
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {   // "" → "
                        field.append("\"")
                        i = text.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",":  endField()
                case "\r":
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\n" { i = next }
                    endRow()
                case "\n": endRow()
                default:   field.append(c)
                }
            }
            i = text.index(after: i)
        }
        // 末尾改行なしの最終行
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    /// テキスト → CSVTable（1行目＝ヘッダ、以降＝データ）。
    /// 列名 → 値 の辞書にする。行内の余剰・不足セルはそのままでは扱えないため、
    /// 不足は空文字で埋め、余剰は捨てる（値の検証は `parse*CSV` が行う）。
    static func table(from text: String) -> CSVTable? {
        let rows = parse(text)
        guard let header = rows.first else { return nil }
        let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let data = rows.dropFirst().map { r -> [String: String] in
            var d: [String: String] = [:]
            for (k, name) in names.enumerated() {
                d[name] = k < r.count ? r[k] : ""
            }
            return d
        }
        return CSVTable(headers: names, rows: Array(data))
    }
}

/// CSV の1フィールドを書き出す（カンマ・引用符・改行を含むならダブルクォートで囲む）
func csvEscape(_ s: String) -> String {
    guard s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") else { return s }
    return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

/// セルのリスト → CSV の1行
func csvLine(_ cells: [String]) -> String {
    cells.map(csvEscape).joined(separator: ",")
}

// ════════════════════════════════════════════════════════════
// 定義・記録の CSV 書き出し（バックアップ・復元用・A-1、A-8、A-13）
// 列構成は A-1 の取り込みCSVと同一（往復できること。C-6 #75）
// ════════════════════════════════════════════════════════════

enum CSVExport {

    /// グループ定義CSV（group_id,label）
    static func groups(_ groups: [ProductGroup]) -> String {
        ([csvLine(["group_id", "label"])] + groups.map { csvLine([$0.groupId, $0.label]) })
            .joined(separator: "\n")
    }

    /// 種類定義CSV（next_no は現在値。復元時に高水位を引き継ぐ・A-1）
    static func types(_ types: [ProductType]) -> String {
        let head = csvLine(["type_id", "name", "id_prefix", "id_digits", "stock_mode",
                            "attr_label_1", "attr_label_2", "attr_label_3", "group_id", "next_no"])
        let rows = types.map { t in
            csvLine([t.typeId, t.name, t.idPrefix, String(t.idDigits), t.stockMode.rawValue,
                     t.attrLabel1 ?? "", t.attrLabel2 ?? "", t.attrLabel3 ?? "",
                     t.groupId ?? "", String(t.nextNo)])
        }
        return ([head] + rows).joined(separator: "\n")
    }

    /// 商品マスタCSV（stock は現在庫・A-1）
    static func products(_ inventory: [Product]) -> String {
        let head = csvLine(["product_id", "type_id", "name", "price_jpy", "price_sats",
                            "stock", "attr_1", "attr_2", "attr_3", "is_public"])
        let rows = inventory.map { p in
            csvLine([p.id, p.typeId, p.name, String(p.priceJpy), p.priceSats.map(String.init) ?? "",
                     p.stock.map(String.init) ?? "",
                     p.attr1 ?? "", p.attr2 ?? "", p.attr3 ?? "", p.isPublic ? "1" : "0"])
        }
        return ([head] + rows).joined(separator: "\n")
    }

    /// 価格一覧CSV（野良商品は含めない・A-1。列：product_id,type_id,name,price_jpy,price_sats）
    static func priceList(_ inventory: [Product]) -> String {
        let head = csvLine(["product_id", "type_id", "name", "price_jpy", "price_sats"])
        let rows = inventory.map { p in
            csvLine([p.id, p.typeId, p.name, String(p.priceJpy), p.priceSats.map(String.init) ?? ""])
        }
        return ([head] + rows).joined(separator: "\n")
    }

    /// 在庫一覧CSV（在庫管理なし型は含まない・C-6 #73）
    static func stockList(_ inventory: [Product], types: [ProductType]) -> String {
        let head = csvLine(["product_id", "type_id", "name", "stock"])
        let rows = inventory.filter { $0.managesStock(in: types) }.map { p in
            csvLine([p.id, p.typeId, p.name, p.stock.map(String.init) ?? ""])
        }
        return ([head] + rows).joined(separator: "\n")
    }

    // ── 販売記録（A-13 の項目名＝列名。C-6 #75）──

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ d: Date?) -> String { d.map { iso8601.string(from: $0) } ?? "" }

    /// sales のエクスポート（sale_id,status,method,...）
    static func sales(_ sales: [Sale]) -> String {
        let head = csvLine(["sale_id", "status", "method", "total_jpy", "total_sats",
                            "received_jpy", "change_jpy", "confirmed_at", "refunded", "completed_at"])
        let rows = sales.map { s in
            csvLine([s.id, s.status.rawValue, s.method.rawValue,
                     s.totalJpy.map(String.init) ?? "", s.totalSats.map(String.init) ?? "",
                     s.receivedJpy.map(String.init) ?? "", s.changeJpy.map(String.init) ?? "",
                     date(s.confirmedAt), s.refunded ? "1" : "0", date(s.completedAt)])
        }
        return ([head] + rows).joined(separator: "\n")
    }

    /// sale_items のエクスポート
    static func saleItems(_ items: [SaleItem]) -> String {
        let head = csvLine(["item_id", "sale_id", "item_type", "type_id", "group_id", "product_id",
                            "qty", "unit_price_jpy", "unit_price_sats", "paid_in", "name_snapshot"])
        let rows = items.map { it in
            csvLine([it.id, it.saleId, it.itemType.rawValue, it.typeId ?? "", it.groupId ?? "",
                     it.productId ?? "", String(it.qty), String(it.unitPriceJpy),
                     it.unitPriceSats.map(String.init) ?? "", it.paidIn.rawValue, it.nameSnapshot])
        }
        return ([head] + rows).joined(separator: "\n")
    }

    /// stock_movements のエクスポート
    static func movements(_ movements: [StockMovement]) -> String {
        let head = csvLine(["id", "product_id", "delta", "reason", "sale_id", "at"])
        let rows = movements.map { m in
            csvLine([m.id, m.productId, String(m.delta), m.reason.rawValue,
                     m.saleId ?? "", date(m.at)])
        }
        return ([head] + rows).joined(separator: "\n")
    }

    /// sats照合CSV（A-8。列：sale_id,status,completed_at,confirmed_at,total_sats,total_jpy,refunded）
    static func satsReconciliationCSV(_ sales: [Sale]) -> String {
        let head = csvLine(["sale_id", "status", "completed_at", "confirmed_at",
                            "total_sats", "total_jpy", "refunded"])
        let rows = satsReconciliation(sales).map { s in
            csvLine([s.id, s.status.rawValue, date(s.completedAt), date(s.confirmedAt),
                     s.totalSats.map(String.init) ?? "", s.totalJpy.map(String.init) ?? "",
                     s.refunded ? "1" : "0"])
        }
        return ([head] + rows).joined(separator: "\n")
    }
}
