import Foundation
import SQLite3
import Security

// ════════════════════════════════════════════════════════════
// 端末内 SQLite（docs/開発/6_データベース.md / siyou2 A-13）
// 現在庫・販売・在庫変動の唯一の正。
// ════════════════════════════════════════════════════════════

enum DatabaseError: LocalizedError {
    case open(String)
    case sql(String)

    var errorDescription: String? {
        switch self {
        case .open(let m): return "データベースを開けません: \(m)"
        case .sql(let m):  return "データベース操作に失敗しました: \(m)"
        }
    }
}

private let dbTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class Database {
    static let shared: Database? = try? Database()

    private var db: OpaquePointer?
    let url: URL

    private let isoOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    private let isoIn: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func defaultURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("Craftill", isDirectory: true)
                   .appendingPathComponent("craftill.sqlite")
    }

    init(url: URL? = nil) throws {
        self.url = url ?? Database.defaultURL()
        let folder = self.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(self.url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let m = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw DatabaseError.open(m)
        }
        db = handle
        try exec("PRAGMA foreign_keys = ON;")
        try migrate()
        try seedIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - 基本

    private func errorMessage() -> String {
        guard let db else { return "unknown" }
        return String(cString: sqlite3_errmsg(db))
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &err)
        defer { sqlite3_free(err) }
        guard rc == SQLITE_OK else {
            throw DatabaseError.sql(err.map { String(cString: $0) } ?? errorMessage())
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DatabaseError.sql(errorMessage())
        }
        return stmt
    }

    private func run(_ sql: String, _ binds: (OpaquePointer) throws -> Void = { _ in }) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try binds(stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.sql(errorMessage())
        }
    }

    private func query<T>(_ sql: String, _ row: (OpaquePointer) -> T) throws -> [T] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: out.append(row(stmt))
            case SQLITE_DONE: return out
            default: throw DatabaseError.sql(errorMessage())
            }
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        try query(sql) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try exec("COMMIT;")
            return result
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    // MARK: - 束縛・取り出し

    private func bind(_ s: OpaquePointer, _ i: Int32, _ v: String?) {
        if let v { sqlite3_bind_text(s, i, v, -1, dbTransient) }
        else { sqlite3_bind_null(s, i) }
    }

    private func bind(_ s: OpaquePointer, _ i: Int32, _ v: Int?) {
        if let v { sqlite3_bind_int64(s, i, sqlite3_int64(v)) }
        else { sqlite3_bind_null(s, i) }
    }

    private func text(_ s: OpaquePointer, _ i: Int32) -> String? {
        guard sqlite3_column_type(s, i) != SQLITE_NULL else { return nil }
        return String(cString: sqlite3_column_text(s, i))
    }

    private func int(_ s: OpaquePointer, _ i: Int32) -> Int? {
        guard sqlite3_column_type(s, i) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(s, i))
    }

    private func date(_ s: OpaquePointer, _ i: Int32) -> Date? {
        text(s, i).flatMap { isoIn.date(from: $0) }
    }

    private func dateText(_ d: Date?) -> String? {
        d.map { isoOut.string(from: $0) }
    }

    // MARK: - スキーマ

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS product_groups (
            group_id  TEXT PRIMARY KEY,
            label     TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS product_types (
            type_id      TEXT PRIMARY KEY,
            name         TEXT NOT NULL,
            id_prefix    TEXT NOT NULL UNIQUE,
            id_digits    INTEGER NOT NULL,
            stock_mode   TEXT NOT NULL,
            attr_label_1 TEXT,
            attr_label_2 TEXT,
            attr_label_3 TEXT,
            group_id     TEXT REFERENCES product_groups(group_id),
            next_no      INTEGER NOT NULL DEFAULT 1,
            updated_at   TEXT
        );

        CREATE TABLE IF NOT EXISTS products (
            product_id  TEXT PRIMARY KEY,
            type_id     TEXT NOT NULL REFERENCES product_types(type_id),
            name        TEXT NOT NULL,
            price_jpy   INTEGER NOT NULL,
            price_sats  INTEGER,
            stock       INTEGER,
            attr_1      TEXT,
            attr_2      TEXT,
            attr_3      TEXT,
            image_ref   TEXT,
            is_public   INTEGER NOT NULL DEFAULT 0,
            updated_at  TEXT
        );

        CREATE TABLE IF NOT EXISTS sales (
            sale_id      TEXT PRIMARY KEY,
            status       TEXT NOT NULL,
            method       TEXT NOT NULL,
            total_jpy    INTEGER,
            total_sats   INTEGER,
            received_jpy INTEGER,
            change_jpy   INTEGER,
            confirmed_at TEXT,
            refunded     INTEGER NOT NULL DEFAULT 0,
            completed_at TEXT
        );

        CREATE TABLE IF NOT EXISTS sale_items (
            item_id         TEXT PRIMARY KEY,
            sale_id         TEXT NOT NULL REFERENCES sales(sale_id),
            item_type       TEXT NOT NULL,
            type_id         TEXT,
            group_id        TEXT,
            product_id      TEXT,
            qty             INTEGER NOT NULL,
            unit_price_jpy  INTEGER NOT NULL,
            unit_price_sats INTEGER,
            paid_in         TEXT NOT NULL,
            name_snapshot   TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS stock_movements (
            id         TEXT PRIMARY KEY,
            product_id TEXT NOT NULL,
            delta      INTEGER NOT NULL,
            reason     TEXT NOT NULL,
            sale_id    TEXT,
            at         TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sync_log (
            id     TEXT PRIMARY KEY,
            at     TEXT NOT NULL,
            result TEXT NOT NULL,
            detail TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_products_type ON products(type_id);
        CREATE INDEX IF NOT EXISTS idx_items_sale ON sale_items(sale_id);
        CREATE INDEX IF NOT EXISTS idx_movements_product ON stock_movements(product_id);
        """)
    }

    // MARK: - 初期データ（テスト商品）

    private func seedIfNeeded() throws {
        let typeCount = try scalarInt("SELECT COUNT(*) FROM product_types;")
        let productCount = try scalarInt("SELECT COUNT(*) FROM products;")
        guard typeCount == 0 && productCount == 0 else { return }

        let seededAt = isoIn.date(from: "2026-10-13T10:00:00+09:00") ?? Date()

        let sticker = ProductType(typeId: "sticker", name: "ステッカー", idPrefix: "ST",
                                  idDigits: 3, stockMode: .counted,
                                  attrLabel1: "色", attrLabel2: "模様", groupId: nil,
                                  nextNo: 4, updatedAt: seededAt)
        let keyholder = ProductType(typeId: "keyholder", name: "キーホルダー", idPrefix: "KH",
                                    idDigits: 3, stockMode: .unique,
                                    attrLabel1: "色", attrLabel2: "模様", groupId: nil,
                                    nextNo: 21, updatedAt: seededAt)
        let service = ProductType(typeId: "service", name: "サービス", idPrefix: "SV",
                                  idDigits: 2, stockMode: .none,
                                  groupId: nil, nextNo: 1, updatedAt: seededAt)

        var products: [Product] = []
        let stickerSeed: [(String, String, String, Int, Int?)] = [
            ("ST-001", "ステッカー まる", "黄", 300, 500),
            ("ST-002", "ステッカー さんかく", "赤", 300, 500),
            ("ST-003", "ステッカー しかく", "青", 300, nil)
        ]
        let stickerPatterns = ["まる", "さんかく", "しかく"]
        for (i, row) in stickerSeed.enumerated() {
            products.append(Product(id: row.0, typeId: "sticker", name: row.1,
                                    priceJpy: row.3, priceSats: row.4, stock: 10,
                                    attr1: row.2, attr2: stickerPatterns[i],
                                    imageRef: "\(row.0).jpg", isPublic: true,
                                    updatedAt: seededAt))
        }

        let colors = ["赤", "青", "緑", "黄", "紫"]
        let patterns = ["○", "△", "□", "☆"]
        for n in 1...20 {
            let id = "KH-" + String(format: "%03d", n)
            products.append(Product(id: id, typeId: "keyholder", name: "キーホルダー " + String(format: "%02d", n),
                                    priceJpy: 800, priceSats: 1200, stock: 1,
                                    attr1: colors[(n - 1) % colors.count],
                                    attr2: patterns[(n - 1) % patterns.count],
                                    imageRef: "\(id).jpg", isPublic: true,
                                    updatedAt: seededAt))
        }

        try transaction {
            try save(group: ProductGroup(groupId: "mono", label: "もの製品"))
            try save(type: sticker)
            try save(type: keyholder)
            try save(type: service)
            for p in products { try save(product: p) }

            var seq = 1
            for p in products {
                guard p.managesStock(in: [sticker, keyholder, service]),
                      let stock = p.stock, stock > 0 else { continue }
                let movement = StockMovement(id: String(format: "M-%06d", seq),
                                             productId: p.id, delta: stock,
                                             reason: .initial, saleId: nil, at: seededAt)
                try save(movement: movement)
                seq += 1
            }
        }
    }

    // MARK: - 読み込み

    func loadGroups() throws -> [ProductGroup] {
        try query("SELECT group_id, label FROM product_groups ORDER BY group_id;") { s in
            ProductGroup(groupId: text(s, 0) ?? "", label: text(s, 1) ?? "")
        }
    }

    func loadTypes() throws -> [ProductType] {
        try query("""
        SELECT type_id, name, id_prefix, id_digits, stock_mode,
               attr_label_1, attr_label_2, attr_label_3,
               group_id, next_no, updated_at
        FROM product_types ORDER BY type_id;
        """) { s in
            ProductType(typeId: text(s, 0) ?? "",
                        name: text(s, 1) ?? "",
                        idPrefix: text(s, 2) ?? "",
                        idDigits: int(s, 3) ?? 1,
                        stockMode: StockMode(rawValue: text(s, 4) ?? "") ?? .counted,
                        attrLabel1: text(s, 5),
                        attrLabel2: text(s, 6),
                        attrLabel3: text(s, 7),
                        groupId: text(s, 8),
                        nextNo: int(s, 9) ?? 1,
                        updatedAt: date(s, 10))
        }
    }

    func loadProducts() throws -> [Product] {
        try query("""
        SELECT product_id, type_id, name, price_jpy, price_sats, stock,
               attr_1, attr_2, attr_3, image_ref, is_public, updated_at
        FROM products ORDER BY product_id;
        """) { s in
            Product(id: text(s, 0) ?? "",
                    typeId: text(s, 1) ?? "",
                    name: text(s, 2) ?? "",
                    priceJpy: int(s, 3) ?? 0,
                    priceSats: int(s, 4),
                    stock: int(s, 5),
                    attr1: text(s, 6),
                    attr2: text(s, 7),
                    attr3: text(s, 8),
                    imageRef: text(s, 9),
                    isPublic: (int(s, 10) ?? 0) != 0,
                    updatedAt: date(s, 11))
        }
    }

    func loadSales() throws -> [Sale] {
        try query("""
        SELECT sale_id, status, method, total_jpy, total_sats,
               received_jpy, change_jpy, confirmed_at, refunded, completed_at
        FROM sales ORDER BY sale_id;
        """) { s in
            Sale(id: text(s, 0) ?? "",
                 status: SaleStatus(rawValue: text(s, 1) ?? "") ?? .completed,
                 method: PaymentMethod(rawValue: text(s, 2) ?? "") ?? .cash,
                 totalJpy: int(s, 3),
                 totalSats: int(s, 4),
                 receivedJpy: int(s, 5),
                 changeJpy: int(s, 6),
                 confirmedAt: date(s, 7),
                 refunded: (int(s, 8) ?? 0) != 0,
                 completedAt: date(s, 9))
        }
    }

    func loadSaleItems() throws -> [SaleItem] {
        try query("""
        SELECT item_id, sale_id, item_type, type_id, group_id, product_id,
               qty, unit_price_jpy, unit_price_sats, paid_in, name_snapshot
        FROM sale_items ORDER BY item_id;
        """) { s in
            SaleItem(id: text(s, 0) ?? "",
                     saleId: text(s, 1) ?? "",
                     itemType: ItemType(rawValue: text(s, 2) ?? "") ?? .registered,
                     typeId: text(s, 3),
                     groupId: text(s, 4),
                     productId: text(s, 5),
                     qty: int(s, 6) ?? 0,
                     unitPriceJpy: int(s, 7) ?? 0,
                     unitPriceSats: int(s, 8),
                     paidIn: PaidIn(rawValue: text(s, 9) ?? "") ?? .jpy,
                     nameSnapshot: text(s, 10) ?? "")
        }
    }

    func loadMovements() throws -> [StockMovement] {
        try query("""
        SELECT id, product_id, delta, reason, sale_id, at
        FROM stock_movements ORDER BY at, id;
        """) { s in
            StockMovement(id: text(s, 0) ?? "",
                          productId: text(s, 1) ?? "",
                          delta: int(s, 2) ?? 0,
                          reason: MovementReason(rawValue: text(s, 3) ?? "") ?? .adjust,
                          saleId: text(s, 4),
                          at: date(s, 5) ?? Date())
        }
    }

    func loadSyncLog() throws -> [SyncLogEntry] {
        try query("SELECT id, at, result, detail FROM sync_log ORDER BY at, id;") { s in
            SyncLogEntry(id: text(s, 0) ?? "",
                         at: date(s, 1) ?? Date(),
                         result: SyncResult(rawValue: text(s, 2) ?? "") ?? .failed,
                         detail: text(s, 3) ?? "")
        }
    }

    // MARK: - 書き込み（マスタ）

    func save(group: ProductGroup) throws {
        try run("""
        INSERT INTO product_groups (group_id, label) VALUES (?, ?)
        ON CONFLICT(group_id) DO UPDATE SET label = excluded.label;
        """) { s in
            bind(s, 1, group.groupId)
            bind(s, 2, group.label)
        }
    }

    func deleteGroup(id: String) throws {
        try run("DELETE FROM product_groups WHERE group_id = ?;") { s in
            bind(s, 1, id)
        }
    }

    func save(type t: ProductType) throws {
        try run("""
        INSERT INTO product_types
        (type_id, name, id_prefix, id_digits, stock_mode,
         attr_label_1, attr_label_2, attr_label_3, group_id, next_no, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(type_id) DO UPDATE SET
            name = excluded.name,
            id_prefix = excluded.id_prefix,
            id_digits = excluded.id_digits,
            stock_mode = excluded.stock_mode,
            attr_label_1 = excluded.attr_label_1,
            attr_label_2 = excluded.attr_label_2,
            attr_label_3 = excluded.attr_label_3,
            group_id = excluded.group_id,
            next_no = excluded.next_no,
            updated_at = excluded.updated_at;
        """) { s in
            bind(s, 1, t.typeId)
            bind(s, 2, t.name)
            bind(s, 3, t.idPrefix)
            bind(s, 4, t.idDigits)
            bind(s, 5, t.stockMode.rawValue)
            bind(s, 6, t.attrLabel1)
            bind(s, 7, t.attrLabel2)
            bind(s, 8, t.attrLabel3)
            bind(s, 9, t.groupId)
            bind(s, 10, t.nextNo)
            bind(s, 11, dateText(t.updatedAt))
        }
    }

    func save(product p: Product) throws {
        try run("""
        INSERT INTO products
        (product_id, type_id, name, price_jpy, price_sats, stock,
         attr_1, attr_2, attr_3, image_ref, is_public, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(product_id) DO UPDATE SET
            type_id = excluded.type_id,
            name = excluded.name,
            price_jpy = excluded.price_jpy,
            price_sats = excluded.price_sats,
            stock = excluded.stock,
            attr_1 = excluded.attr_1,
            attr_2 = excluded.attr_2,
            attr_3 = excluded.attr_3,
            image_ref = excluded.image_ref,
            is_public = excluded.is_public,
            updated_at = excluded.updated_at;
        """) { s in
            bind(s, 1, p.id)
            bind(s, 2, p.typeId)
            bind(s, 3, p.name)
            bind(s, 4, p.priceJpy)
            bind(s, 5, p.priceSats)
            bind(s, 6, p.stock)
            bind(s, 7, p.attr1)
            bind(s, 8, p.attr2)
            bind(s, 9, p.attr3)
            bind(s, 10, p.imageRef)
            bind(s, 11, p.isPublic ? 1 : 0)
            bind(s, 12, dateText(p.updatedAt))
        }
    }

    // MARK: - 書き込み（会計・在庫）

    private func insert(sale: Sale) throws {
        try run("""
        INSERT OR REPLACE INTO sales
        (sale_id, status, method, total_jpy, total_sats,
         received_jpy, change_jpy, confirmed_at, refunded, completed_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """) { s in
            bind(s, 1, sale.id)
            bind(s, 2, sale.status.rawValue)
            bind(s, 3, sale.method.rawValue)
            bind(s, 4, sale.totalJpy)
            bind(s, 5, sale.totalSats)
            bind(s, 6, sale.receivedJpy)
            bind(s, 7, sale.changeJpy)
            bind(s, 8, dateText(sale.confirmedAt))
            bind(s, 9, sale.refunded ? 1 : 0)
            bind(s, 10, dateText(sale.completedAt))
        }
    }

    private func insert(item: SaleItem) throws {
        try run("""
        INSERT OR REPLACE INTO sale_items
        (item_id, sale_id, item_type, type_id, group_id, product_id,
         qty, unit_price_jpy, unit_price_sats, paid_in, name_snapshot)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """) { s in
            bind(s, 1, item.id)
            bind(s, 2, item.saleId)
            bind(s, 3, item.itemType.rawValue)
            bind(s, 4, item.typeId)
            bind(s, 5, item.groupId)
            bind(s, 6, item.productId)
            bind(s, 7, item.qty)
            bind(s, 8, item.unitPriceJpy)
            bind(s, 9, item.unitPriceSats)
            bind(s, 10, item.paidIn.rawValue)
            bind(s, 11, item.nameSnapshot)
        }
    }

    func save(movement: StockMovement) throws {
        try run("""
        INSERT OR REPLACE INTO stock_movements
        (id, product_id, delta, reason, sale_id, at)
        VALUES (?, ?, ?, ?, ?, ?);
        """) { s in
            bind(s, 1, movement.id)
            bind(s, 2, movement.productId)
            bind(s, 3, movement.delta)
            bind(s, 4, movement.reason.rawValue)
            bind(s, 5, movement.saleId)
            bind(s, 6, dateText(movement.at))
        }
    }

    private func updateStocks(_ inventory: [Product]) throws {
        for p in inventory {
            try run("UPDATE products SET stock = ? WHERE product_id = ?;") { s in
                bind(s, 1, p.stock)
                bind(s, 2, p.id)
            }
        }
    }

    /// 会計確定（sales + sale_items + 在庫 + 在庫変動）を1トランザクションで保存する
    func persistCommit(sale: Sale, items: [SaleItem],
                       inventory: [Product], movements: [StockMovement]) throws {
        try transaction {
            try insert(sale: sale)
            for i in items { try insert(item: i) }
            try updateStocks(inventory)
            for m in movements { try save(movement: m) }
        }
    }

    /// 販売取消（sales 更新 + 在庫 + 在庫変動）
    func persistVoid(sale: Sale, inventory: [Product], movements: [StockMovement]) throws {
        try transaction {
            try insert(sale: sale)
            try updateStocks(inventory)
            for m in movements { try save(movement: m) }
        }
    }

    func persistSale(_ sale: Sale) throws {
        try insert(sale: sale)
    }

    /// 在庫調整（products.stock + stock_movements）
    func persistAdjust(inventory: [Product], movements: [StockMovement]) throws {
        try transaction {
            try updateStocks(inventory)
            for m in movements { try save(movement: m) }
        }
    }

    func save(sync: SyncLogEntry) throws {
        try run("""
        INSERT OR REPLACE INTO sync_log (id, at, result, detail)
        VALUES (?, ?, ?, ?);
        """) { s in
            bind(s, 1, sync.id)
            bind(s, 2, dateText(sync.at))
            bind(s, 3, sync.result.rawValue)
            bind(s, 4, sync.detail)
        }
    }
}

// ════════════════════════════════════════════════════════════
// PIN（Keychain / A-19-6）
// ════════════════════════════════════════════════════════════

enum PinStore {
    private static let service = "dev.craftill.pin"
    private static let account = "craftill"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load() -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let pin = String(data: data, encoding: .utf8),
              !pin.isEmpty else { return nil }
        return pin
    }

    @discardableResult
    static func save(_ pin: String) -> Bool {
        clear()
        var q = baseQuery
        q[kSecValueData as String] = Data(pin.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
