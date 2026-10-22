import Foundation

// ════════════════════════════════════════════════════════════
// CSV取り込み（A-1 / P4）
// - RFC 4180 の簡易版（カンマ区切り、ダブルクォート、CRLF/LF、BOM可）
// - 検証は basic.swift の parseGroupCSV / parseTypeCSV / parseProductCSV を使う
// - 1件でもエラーがあれば、DB・メモリを一切変更しない
// ════════════════════════════════════════════════════════════

/// 画面に出す取り込みエラー。`row == 0` はファイル全体・DBのエラー。
struct CSVError: Identifiable {
    let id = UUID()
    let row: Int
    let column: String
    let reason: String
}

struct CSVParseError: LocalizedError {
    let row: Int
    let reason: String

    var errorDescription: String? { reason }
    var csvError: CSVError { CSVError(row: row, column: "", reason: reason) }
}

enum CSVImportParser {
    static func parse(_ data: Data) throws -> CSVTable {
        guard var text = String(data: data, encoding: .utf8) else {
            throw CSVParseError(row: 1, reason: "UTF-8のCSVとして読み取れません")
        }
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return try parse(text: text)
    }

    static func parse(text rawText: String) throws -> CSVTable {
        var rawText = rawText
        if rawText.hasPrefix("\u{FEFF}") {
            rawText.removeFirst()
        }
        // Swift の Character では CRLF が1文字として扱われるため、
        // "\r" / "\n" に加えて "\r\n" も改行として判定する。
        let chars = Array(rawText)
        var i = 0
        var physicalLine = 1
        var recordStartLine = 1
        var field = ""
        var fields: [String] = []
        var inQuotes = false
        var fieldStarted = false
        var records: [(line: Int, fields: [String])] = []

        func trim(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func finishField() {
            fields.append(trim(field))
            field = ""
            fieldStarted = false
        }

        func finishRecord() {
            finishField()
            if !fields.allSatisfy({ $0.isEmpty }) {
                records.append((recordStartLine, fields))
            }
            fields = []
        }

        while i < chars.count {
            let c = chars[i]

            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                    } else {
                        inQuotes = false
                        i += 1
                    }
                } else if c == "\r\n" || c == "\r" || c == "\n" {
                    field.append("\n")
                    physicalLine += 1
                    i += 1
                } else {
                    field.append(c)
                    i += 1
                }
                continue
            }

            if c == "\"" {
                if !fieldStarted {
                    inQuotes = true
                    fieldStarted = true
                    i += 1
                } else {
                    throw CSVParseError(row: recordStartLine,
                                        reason: "引用符（\"）の位置が不正です")
                }
            } else if c == "," {
                finishField()
                i += 1
            } else if c == "\r\n" || c == "\r" || c == "\n" {
                finishRecord()
                i += 1
                physicalLine += 1
                recordStartLine = physicalLine
            } else {
                field.append(c)
                fieldStarted = true
                i += 1
            }
        }

        if inQuotes {
            throw CSVParseError(row: recordStartLine, reason: "引用符（\"）が閉じられていません")
        }
        if fieldStarted || !field.isEmpty || !fields.isEmpty {
            finishRecord()
        }

        guard let headerRecord = records.first else {
            throw CSVParseError(row: 1, reason: "ヘッダ行がありません")
        }
        let headers = headerRecord.fields
        if headers.contains(where: { $0.isEmpty }) {
            throw CSVParseError(row: headerRecord.line, reason: "列名が空です")
        }
        var seen = Set<String>()
        for h in headers where !seen.insert(h).inserted {
            throw CSVParseError(row: headerRecord.line, reason: "列名が重複しています: \(h)")
        }

        var rows: [[String: String]] = []
        var lines: [Int] = []
        for record in records.dropFirst() {
            guard record.fields.count == headers.count else {
                throw CSVParseError(
                    row: record.line,
                    reason: "列数がヘッダ（\(headers.count)列）と一致しません（\(record.fields.count)列）")
            }
            var row: [String: String] = [:]
            for (n, h) in headers.enumerated() {
                row[h] = record.fields[n]
            }
            rows.append(row)
            lines.append(record.line)
        }

        return CSVTable(headers: headers, rows: rows, lines: lines)
    }
}

// MARK: - 取り込み計画

struct CSVStockDiff: Identifiable {
    var id: String { productId }
    let productId: String
    let current: Int
    let csv: Int
    var delta: Int { csv - current }
}

struct CSVMovementSpec {
    let productId: String
    let delta: Int
    let reason: MovementReason
}

struct CSVImportPlan {
    let groups: [ProductGroup]
    let types: [ProductType]
    let products: [Product]

    let changedGroups: [ProductGroup]
    let changedTypes: [ProductType]
    let changedProducts: [Product]

    let movements: [CSVMovementSpec]
    let stockDiffs: [CSVStockDiff]

    let newGroupCount: Int
    let updatedGroupCount: Int
    let newTypeCount: Int
    let updatedTypeCount: Int
    let newProductCount: Int
    let updatedProductCount: Int

    let at: Date

    var hasChanges: Bool {
        !changedGroups.isEmpty || !changedTypes.isEmpty || !changedProducts.isEmpty
            || !movements.isEmpty
    }
}

struct CSVImportOutcome {
    let plan: CSVImportPlan?
    let errors: [CSVError]
}

enum CSVImportPlanner {
    static func plan(groupCSV: CSVTable?,
                     typeCSV: CSVTable?,
                     productCSV: CSVTable?,
                     existingGroups: [ProductGroup],
                     existingTypes: [ProductType],
                     existingProducts: [Product],
                     existingItems: [SaleItem],
                     overwriteStock: Bool,
                     at: Date = Date()) -> CSVImportOutcome {

        guard groupCSV != nil || typeCSV != nil || productCSV != nil else {
            return CSVImportOutcome(
                plan: nil,
                errors: [CSVError(row: 0, column: "CSV", reason: "取り込むCSVを選択してください")])
        }

        var workingGroups = existingGroups
        var workingTypes = existingTypes
        var workingInventory = existingProducts
        var issues: [ValidationIssue] = []

        if let groupCSV {
            let parsed = parseGroupCSV(groupCSV)
            issues.append(contentsOf: parsed.issues)
            if parsed.issues.isEmpty {
                applyGroups(parsed.groups, groups: &workingGroups)
            }
        }

        if let typeCSV {
            let parsed = parseTypeCSV(typeCSV,
                                      groups: workingGroups,
                                      existing: workingTypes,
                                      inventory: workingInventory,
                                      items: existingItems)
            issues.append(contentsOf: parsed.issues)
            if parsed.issues.isEmpty {
                applyTypes(parsed.types, types: &workingTypes,
                           inventory: workingInventory, at: at)
            }
        }

        if let productCSV {
            let parsed = parseProductCSV(productCSV,
                                         types: workingTypes,
                                         inventory: workingInventory)
            issues.append(contentsOf: parsed.issues)
            if parsed.issues.isEmpty {
                // 在庫・nextNo の更新だけを計画に反映する。IDは本適用時に採番する。
                var dummyIDs = IdSequencer()
                var dummyMovements: [StockMovement] = []
                applyProductMaster(parsed.products,
                                   inventory: &workingInventory,
                                   movements: &dummyMovements,
                                   ids: &dummyIDs,
                                   types: &workingTypes,
                                   overwriteStock: overwriteStock,
                                   at: at)
            }
        }

        guard issues.isEmpty else {
            return CSVImportOutcome(
                plan: nil,
                errors: issues.map {
                    CSVError(row: $0.row, column: $0.column, reason: $0.reason)
                })
        }

        workingGroups.sort { $0.groupId < $1.groupId }
        workingTypes.sort { $0.typeId < $1.typeId }
        workingInventory.sort { $0.id < $1.id }

        let oldGroups = Dictionary(uniqueKeysWithValues: existingGroups.map { ($0.groupId, $0) })
        let oldTypes = Dictionary(uniqueKeysWithValues: existingTypes.map { ($0.typeId, $0) })
        let oldProducts = Dictionary(uniqueKeysWithValues: existingProducts.map { ($0.id, $0) })

        let changedGroups = workingGroups.filter { g in
            guard let old = oldGroups[g.groupId] else { return true }
            return old != g
        }
        let changedTypes = workingTypes.filter { t in
            guard let old = oldTypes[t.typeId] else { return true }
            return old != t
        }
        let changedProducts = workingInventory.filter { p in
            guard let old = oldProducts[p.id] else { return true }
            return old != p
        }

        var diffs: [CSVStockDiff] = []
        var movementSpecs: [CSVMovementSpec] = []
        for product in workingInventory {
            let managesStock = product.managesStock(in: workingTypes)
            if let old = oldProducts[product.id] {
                guard overwriteStock, managesStock,
                      let current = old.stock, let incoming = product.stock,
                      current != incoming else { continue }
                diffs.append(CSVStockDiff(productId: product.id,
                                          current: current,
                                          csv: incoming))
                movementSpecs.append(CSVMovementSpec(productId: product.id,
                                                     delta: incoming - current,
                                                     reason: .adjust))
            } else {
                guard managesStock, let stock = product.stock, stock > 0 else { continue }
                movementSpecs.append(CSVMovementSpec(productId: product.id,
                                                     delta: stock,
                                                     reason: .initial))
            }
        }

        let newGroupCount = workingGroups.filter { oldGroups[$0.groupId] == nil }.count
        let updatedGroupCount = changedGroups.count - newGroupCount
        let newTypeCount = workingTypes.filter { oldTypes[$0.typeId] == nil }.count
        let updatedTypeCount = changedTypes.count - newTypeCount
        let newProductCount = workingInventory.filter { oldProducts[$0.id] == nil }.count
        let updatedProductCount = changedProducts.count - newProductCount

        let plan = CSVImportPlan(
            groups: workingGroups,
            types: workingTypes,
            products: workingInventory,
            changedGroups: changedGroups,
            changedTypes: changedTypes,
            changedProducts: changedProducts,
            movements: movementSpecs,
            stockDiffs: diffs,
            newGroupCount: newGroupCount,
            updatedGroupCount: updatedGroupCount,
            newTypeCount: newTypeCount,
            updatedTypeCount: updatedTypeCount,
            newProductCount: newProductCount,
            updatedProductCount: updatedProductCount,
            at: at)

        return CSVImportOutcome(plan: plan, errors: [])
    }
}
