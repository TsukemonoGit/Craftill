# SQLiteで在庫を保存する

元: `../siyou.md` A-13, A-16

端末内の **SQLite** に商品と在庫を保存する練習。現在庫は **ここが唯一の正**。
会計の完了は、**1つのトランザクション**で「在庫検証 → 在庫減算 → 販売確定 → 在庫変動ログ」をまとめて行う。

> **SQLite3（OS/DB依存）を使うので、iPadのブックでは動きません。**
> **アプリ**（Mac/iPad）または **Macのコマンドラインツール**で実行します。
> 表の定義とサンプルは `../開発/6_データベース.md` と同じ。

**構成**: 【小問1】テーブルを作って在庫を読み書き → 【小問2】会計完了をトランザクションで行う。

---

## 前提データ

```swift
import Foundation
import SQLite3

struct Product {
    let id: String
    let typeId: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?
    var stock: Int?
    let imageRef: String?
    let isPublic: Bool
}
```

### テーブル定義とサンプル（`../開発/6_データベース.md` のまま。Swift文字列で持つ）

```swift
let schemaSQL = """
CREATE TABLE IF NOT EXISTS product_types (
  type_id TEXT PRIMARY KEY, name TEXT NOT NULL, id_prefix TEXT NOT NULL UNIQUE,
  id_digits INTEGER NOT NULL, stock_mode TEXT NOT NULL,
  attr_label_1 TEXT, attr_label_2 TEXT, attr_label_3 TEXT, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS products (
  product_id TEXT PRIMARY KEY, type_id TEXT NOT NULL, name TEXT NOT NULL,
  price_jpy INTEGER NOT NULL, price_sats INTEGER, stock INTEGER,
  attr_1 TEXT, attr_2 TEXT, attr_3 TEXT, image_ref TEXT,
  is_public INTEGER NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sales (
  sale_id TEXT PRIMARY KEY, status TEXT NOT NULL, method TEXT NOT NULL,
  total_jpy INTEGER, total_sats INTEGER, received_jpy INTEGER, change_jpy INTEGER,
  confirmed_at TEXT, refunded INTEGER NOT NULL DEFAULT 0, completed_at TEXT);
CREATE TABLE IF NOT EXISTS sale_items (
  item_id TEXT PRIMARY KEY, sale_id TEXT NOT NULL, item_type TEXT NOT NULL,
  type_id TEXT, product_id TEXT, qty INTEGER NOT NULL, unit_price_jpy INTEGER NOT NULL,
  unit_price_sats INTEGER, paid_in TEXT NOT NULL, name_snapshot TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS stock_movements (
  id TEXT PRIMARY KEY, product_id TEXT NOT NULL, delta INTEGER NOT NULL,
  reason TEXT NOT NULL, sale_id TEXT, at TEXT NOT NULL);
"""

let sampleSQL = """
INSERT INTO product_types
(type_id, name, id_prefix, id_digits, stock_mode, attr_label_1, attr_label_2, attr_label_3, updated_at) VALUES
('sticker',   'ステッカー',   'ST', 3, 'counted', '色', '模様', NULL, '2026-10-13T10:00:00+09:00'),
('keyholder', 'キーホルダー', 'KH', 3, 'unique',  '色', '模様', NULL, '2026-10-13T10:00:00+09:00');
INSERT INTO products
(product_id, type_id, name, price_jpy, price_sats, stock, attr_1, attr_2, attr_3, image_ref, is_public, updated_at) VALUES
('ST-001','sticker',   'ステッカー まる', 300, 500,  10, '黄','まる',NULL, 'ST-001.jpg', 1, '2026-10-13T10:00:00+09:00'),
('KH-005','keyholder', 'キーホルダー 05', 800, 1200, 1,  '紫','○',  NULL, 'KH-005.jpg', 1, '2026-10-13T10:00:00+09:00');
"""
```

---

## 薄いラッパー（SQLite3のC APIを使いやすくする）

```swift
// SQLiteのC APIに、文字列の寿命を伝えるおまじない
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DBError: Error {
    case open(String)
    case sql(String)
    case stockShortage(productID: String, current: Int, requested: Int)
}

/// SQLite3 の薄いラッパー（練習用の最小限）
final class Database {
    private var handle: OpaquePointer?

    init(path: String) throws {
        if sqlite3_open(path, &handle) != SQLITE_OK {
            throw DBError.open(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown")
        }
    }
    deinit { if let h = handle { sqlite3_close(h) } }

    /// CREATE TABLE など、まとめた文を実行する
    func exec(_ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &errmsg) != SQLITE_OK {
            let message = errmsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errmsg)
            throw DBError.sql(message)
        }
    }

    /// 1つの整数を返す（在庫の読み出しなど）。行が無い / NULL なら nil
    func scalarInt(_ sql: String, _ bind: String) throws -> Int? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.sql(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, bind, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_ROW {
            if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return nil
    }
}
```

- `sqlite3_open` / `sqlite3_exec` / `sqlite3_prepare_v2` はCの関数。`import SQLite3` で使える。
- 実運用ではSQLに文字列を貼らず、プレースホルダ（`?`）と `bind` を使う（ここは練習）。

---

## 小問1: テーブルを作って、在庫を読み書きする

```swift
func setupSample(_ db: Database) throws {
    try db.exec(schemaSQL)   // テーブル作成（存在すれば何もしない）
    try db.exec(sampleSQL)   // サンプル投入
}

func printStock(_ db: Database, _ productID: String) throws {
    let stock = try db.scalarInt("SELECT stock FROM products WHERE product_id = ?;", productID)
    print("\(productID) 在庫: \(stock.map { String($0) } ?? "—")")
}

#if os(macOS)
let dbPath = "rezi.sqlite"   // Macのコマンドラインツール：カレントにファイルを作る
#else
let dbPath = FileManager.default   // iOS/iPad：自分の書類フォルダの中だけ
    .urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("rezi.sqlite").path
#endif

let db = try Database(path: dbPath)
try setupSample(db)
try printStock(db, "ST-001")   // ST-001 在庫: 10
try printStock(db, "KH-005")   // KH-005 在庫: 1
```

**できた合図**: `ST-001 在庫: 10` と `KH-005 在庫: 1` が出る。

---

## 小問2: 会計完了をトランザクションで行う

「在庫検証 → 在庫減算 → 販売確定 → 在庫変動ログ」を **1つ**にまとめる。
途中で失敗したら `ROLLBACK` して、**全部なかったこと**にする（`BEGIN` 〜 `COMMIT`）。

```swift
struct SaleLine {
    let productID: String
    let qty: Int
    let unitPriceJpy: Int
    let unitPriceSats: Int?
    let paidIn: String       // "jpy" / "sats"
    let nameSnapshot: String
}

func completeCashSale(_ db: Database, saleID: String, receivedJpy: Int,
                      lines: [SaleLine], at: String) throws {
    try db.exec("BEGIN;")
    do {
        // 1. 在庫検証（足りなければ例外 → ROLLBACK）
        for line in lines {
            let current = try db.scalarInt(
                "SELECT stock FROM products WHERE product_id = ?;", line.productID)
            guard let stock = current else {
                throw DBError.sql("在庫管理外、または商品がありません: \(line.productID)")
            }
            guard stock >= line.qty else {
                throw DBError.stockShortage(productID: line.productID,
                                            current: stock, requested: line.qty)
            }
        }
        // 2. 在庫減算
        for line in lines {
            try db.exec("UPDATE products SET stock = stock - \(line.qty) WHERE product_id = '\(line.productID)';")
        }
        // 3. 販売確定（現金会計なので total_jpy = 全行の円合計）
        let totalJpy = lines.reduce(0) { $0 + $1.unitPriceJpy * $1.qty }
        try db.exec("""
        INSERT INTO sales
        (sale_id,status,method,total_jpy,total_sats,received_jpy,change_jpy,confirmed_at,refunded,completed_at)
        VALUES ('\(saleID)','completed','cash',\(totalJpy),NULL,\(receivedJpy),\(receivedJpy - totalJpy),NULL,0,'\(at)');
        """)
        // 4. 明細と在庫変動ログ
        for (index, line) in lines.enumerated() {
            let sats = line.unitPriceSats.map { String($0) } ?? "NULL"
            try db.exec("""
            INSERT INTO sale_items
            (item_id,sale_id,item_type,type_id,product_id,qty,unit_price_jpy,unit_price_sats,paid_in,name_snapshot)
            VALUES ('I-\(saleID)-\(index)','\(saleID)','registered',
                    (SELECT type_id FROM products WHERE product_id='\(line.productID)'),
                    '\(line.productID)',\(line.qty),\(line.unitPriceJpy),\(sats),'\(line.paidIn)','\(line.nameSnapshot)');
            """)
            try db.exec("""
            INSERT INTO stock_movements (id,product_id,delta,reason,sale_id,at)
            VALUES ('M-\(saleID)-\(index)','\(line.productID)',\(-line.qty),'sale','\(saleID)','\(at)');
            """)
        }
        try db.exec("COMMIT;")
    } catch {
        try? db.exec("ROLLBACK;")   // どれかで失敗したら、全部なかったことにする
        throw error
    }
}
```

```swift
// ST-001 を2枚（¥300）、KH-005 を1個（¥800）→ 合計 ¥1400。受取 ¥2000。
let lines = [
    SaleLine(productID: "ST-001", qty: 2, unitPriceJpy: 300, unitPriceSats: 500,
             paidIn: "jpy", nameSnapshot: "ステッカー まる"),
    SaleLine(productID: "KH-005", qty: 1, unitPriceJpy: 800, unitPriceSats: 1200,
             paidIn: "jpy", nameSnapshot: "キーホルダー 05"),
]
try completeCashSale(db, saleID: "S-20261013-001", receivedJpy: 2000,
                     lines: lines, at: "2026-10-13T11:00:00+09:00")

try printStock(db, "ST-001")   // 10 → 8
try printStock(db, "KH-005")   // 1 → 0（SOLD OUT）
```

**できた合図**: `ST-001 在庫: 8` と `KH-005 在庫: 0`。
在庫が足りないとき（例: 在庫1の KH-002 を2個）は `stockShortage` が投げられ、`ROLLBACK` されて在庫は元のまま。

---

## 覚えておくこと

- 現在庫は**端末内DBが唯一の正**（`../siyou.md` A-7）。会計で減らすのは「完了」のときだけ。
- 「検証 → 減算 → 販売確定 → 変動ログ」は**1トランザクション**。途中失敗は `ROLLBACK`（`../siyou.md` A-4）。
- 併用会計（`mixed`）は、`sales.total_sats` にsats額を足し、行ごとの `paid_in` を `sats` にするだけ。
- DBの置き場所はOSで違う（Mac：任意の場所、iPad：書類フォルダ）。`#if os` で分ける。
