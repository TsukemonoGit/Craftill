import Foundation
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// ════════════════════════════════════════════════════════════
// CSV エクスポート（P1-12 / siyou2 A-8・A-13）
// 列名はDBの項目名に合わせる。円とsatsは別の列。
// ════════════════════════════════════════════════════════════

enum CSVExport {
    nonisolated static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    nonisolated static func table(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    private static func date(_ d: Date?) -> String {
        d.map { iso.string(from: $0) } ?? ""
    }

    private static func int(_ n: Int?) -> String {
        n.map(String.init) ?? ""
    }

    static func groupsCSV(_ groups: [ProductGroup]) -> String {
        table([["group_id", "label"]] + groups.map { [$0.groupId, $0.label] })
    }

    static func typesCSV(_ types: [ProductType]) -> String {
        table([[
            "type_id", "name", "id_prefix", "id_digits", "stock_mode",
            "attr_label_1", "attr_label_2", "attr_label_3",
            "group_id", "next_no", "updated_at"
        ]] + types.map {
            [$0.typeId, $0.name, $0.idPrefix, String($0.idDigits), $0.stockMode.rawValue,
             $0.attrLabel1 ?? "", $0.attrLabel2 ?? "", $0.attrLabel3 ?? "",
             $0.groupId ?? "", String($0.nextNo), date($0.updatedAt)]
        })
    }

    static func productsCSV(_ products: [Product]) -> String {
        table([[
            "product_id", "type_id", "name", "price_jpy", "price_sats", "stock",
            "attr_1", "attr_2", "attr_3", "image_ref", "is_public", "updated_at"
        ]] + products.map {
            [$0.id, $0.typeId, $0.name, String($0.priceJpy), int($0.priceSats), int($0.stock),
             $0.attr1 ?? "", $0.attr2 ?? "", $0.attr3 ?? "", $0.imageRef ?? "",
             $0.isPublic ? "1" : "0", date($0.updatedAt)]
        })
    }

    static func salesCSV(_ sales: [Sale]) -> String {
        table([[
            "sale_id", "status", "method", "total_jpy", "total_sats",
            "received_jpy", "change_jpy", "confirmed_at", "refunded", "completed_at"
        ]] + sales.map {
            [$0.id, $0.status.rawValue, $0.method.rawValue, int($0.totalJpy), int($0.totalSats),
             int($0.receivedJpy), int($0.changeJpy), date($0.confirmedAt),
             $0.refunded ? "1" : "0", date($0.completedAt)]
        })
    }

    static func saleItemsCSV(_ items: [SaleItem]) -> String {
        table([[
            "item_id", "sale_id", "item_type", "type_id", "group_id", "product_id",
            "qty", "unit_price_jpy", "unit_price_sats", "paid_in", "name_snapshot"
        ]] + items.map {
            [$0.id, $0.saleId, $0.itemType.rawValue, $0.typeId ?? "", $0.groupId ?? "",
             $0.productId ?? "", String($0.qty), String($0.unitPriceJpy), int($0.unitPriceSats),
             $0.paidIn.rawValue, $0.nameSnapshot]
        })
    }

    static func movementsCSV(_ movements: [StockMovement]) -> String {
        table([["id", "product_id", "delta", "reason", "sale_id", "at"]] + movements.map {
            [$0.id, $0.productId, String($0.delta), $0.reason.rawValue, $0.saleId ?? "", date($0.at)]
        })
    }

    static func syncLogCSV(_ log: [SyncLogEntry]) -> String {
        table([["id", "at", "result", "detail"]] + log.map {
            [$0.id, date($0.at), $0.result.rawValue, $0.detail]
        })
    }

    static func settlementCSV(_ rows: [ReportRow]) -> String {
        table([[
            "group_id", "group_label", "item_type", "type_id", "paid_in",
            "lines", "qty", "amount"
        ]] + rows.map {
            // ReportRow.id は「group|区分|種類|paid_in」で作っている
            let parts = $0.id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let groupId = parts.indices.contains(0) ? parts[0] : ""
            let itemType = parts.indices.contains(1) ? parts[1] : ""
            let typeId = parts.indices.contains(2) ? parts[2] : ""
            return [groupId, $0.groupLabel, itemType, typeId, $0.paidIn.rawValue,
                    String($0.lines), String($0.qty), String($0.amount)]
        })
    }

    static func priceListCSV(_ products: [Product]) -> String {
        table([["product_id", "type_id", "name", "price_jpy", "price_sats"]] + products.map {
            [$0.id, $0.typeId, $0.name, String($0.priceJpy), int($0.priceSats)]
        })
    }
}

#if canImport(AppKit)
enum CSVExportPanel {
    nonisolated static var usesShareSheet: Bool { false }

    @MainActor
    static func save(_ csv: String, suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    @MainActor
    static func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "このフォルダへ書き出す"
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func finish(folder: URL) {}
}
#elseif canImport(UIKit)
enum CSVExportPanel {
    nonisolated static var usesShareSheet: Bool { true }

    /// iPad / iPhone: 一時ファイルに書いて共有シートを開く（ファイルアプリへ保存可能）。
    @MainActor
    static func save(_ csv: String, suggestedName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
        do {
            try Data(csv.utf8).write(to: url, options: .atomic)
            share([url])
            return url
        } catch {
            return nil
        }
    }

    /// 一括出力用の一時フォルダを返す。書き出し後に finish(folder:) を呼ぶ。
    @MainActor
    static func chooseDirectory() -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("craftill-export-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }

    @MainActor
    static func finish(folder: URL) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                 includingPropertiesForKeys: nil)) ?? [folder]
        share(urls)
    }

    @MainActor
    private static func share(_ urls: [URL]) {
        guard let root = topViewController() else { return }
        let av = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let pop = av.popoverPresentationController {
            pop.sourceView = root.view
            pop.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY,
                                    width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        root.present(av, animated: true)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
#endif
