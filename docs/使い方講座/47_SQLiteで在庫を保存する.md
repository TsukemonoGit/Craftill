# SQLiteで在庫を保存する

元: `../siyou.md` A-4（トランザクション）、A-7、A-13（表定義）、A-16
`../siyou.md` A-19-1（現在庫の正）、A-19-4（採番規則）、A-19-5（日時）
受け入れテスト C-6 #4・#77

端末内の **SQLite** に商品と在庫を保存します。現在庫は **ここが唯一の正**（A-19-1）。
会計の完了は **1つのトランザクション** で「在庫検証 → 在庫減算 → 販売確定 → 在庫変動ログ」
（A-4 の4手順）をまとめて行います。

> **SQLite3（OS/DB 依存）を使うので、ブックでは動きません。**
> **アプリ**（Mac / iPad）または **Mac のコマンドラインツール**で実行します。
> 表の定義は `../開発/6_データベース.md` と一致させます。

**このレッスンは「配列で計算した正を、SQL にどう書くか」です。**
計算・採番・判定はすべて `base/` にあります。

| 担当 | 正 |
| --- | --- |
| `Product` / `Sale` / `SaleItem` / `StockMovement` / `IdSequencer` | `base/2_型定義.md` |
| 在庫検証・減算・採番（A-4 の4手順） | `base/3_標準ロジック.md` §2・§3・§4 |
| `paid_in` / `item_type` / `reason` の値域 | `base/2` の enum（A-13、P6） |
| 日時の `TEXT` 化 | `jsonEncoder`（A-19-5） |

---

## まず土台をペーストする

1. `base/Types.swift` の**型だけ**
2. `base/3_標準ロジック.md` の **§2・§3・§4**

> **`SaleLine` を作りません。** `SaleItem` がその役目です。
> **採番は `IdSequencer`** に任せます（A-19-4）。

---

## わざと間違う①: SQL で ID を自分で振りなおす

```swift NG
// わざと間違う版①：明細ID・変動IDを SQL に書きながら採番する
for (index, line) in lines.enumerated() {
    try db.exec("""
    INSERT INTO sale_items (...) VALUES ('I-\(saleID)-\(index)', ...);
    """)
    try db.exec("""
    INSERT INTO stock_movements (id,product_id,delta,reason,sale_id,at)
    VALUES ('M-\(saleID)-\(index)','\(line.productID)',\(-line.qty),'sale','\(saleID)','\(at)');
    """)
}
```

**SQL は通ります。でも A-19-4 に2つ違反**しています。

| 出力 | この版 | A-19-4 の正 |
| --- | --- | --- |
| 明細ID | `I-S-20261013-001-0` | **`S-20261013-001-01`**（`{sale_id}-{n:02}`） |
| 変動ID | `M-S-20261013-001-0` | **`M-000001`**（`M-{連番:06}`） |

**なぜこれが駄目か**

1. **`M-…` の数列が販売ごとに振り直される**。全販売のログを並べると
   `M-S-…-001-0`, `M-S-…-001-1`, `M-S-…-002-0`, … となり、**時刻順にならない**。
   **`M-000001`…`M-000004` なら時系列に並ぶ**（`40_販売記録を書き出す.md` のエクスポートが機能する）
2. **明細IDが `0` 始まり**。A-13 の `{sale_id}-{n:02}` は **`01` 始まり**
3. **欠番・重複の検出ができない**。`PRIMARY KEY` が守っても
   「3行目のIDが `…-01` に戻ってる」ような**並びの破綻**は検出できない

**正**: `commitSale` が **`IdSequencer` で採番済みの `Sale` / `SaleItem` / `StockMovement` を返す**。
SQL はその値を**書き込むだけ**。

```swift 断片
// base/3 §4：採番はここ。SQL ではない
let built = buildSale(cart: cart, ids: &ids, chooseSats: chooseSats,
                      receivedJpy: receivedJpy, confirmedAt: confirmedAt, now: now)
// built.sale.id   = "S-20231115-001"
// built.items[0].id = "S-20231115-001-01"
```

> **「採番は販売確定時」**（A-19-4）。`ROLLBACK` しても番号は**戻りません**。
> 欠番は正常です。**再利用しません**。

---

## わざと間違う②: SQL 文字列に値を埋め込む

```swift NG
// わざと間違う版②：値を文字列連結する
try db.exec("UPDATE products SET stock = stock - \(line.qty) WHERE product_id = '\(line.productID)';")
```

**商品名に `'`（シングルクォート）が入ったら壊れます。** `O'Brien` → 文法エラー。

**それ以上に**、値がそのまま SQL の一部になるので、**SQL インジェクション**が起きます。

```swift NG
// 商品名にこれが入ってたら
let evil = "x'; DROP TABLE products; --"
// 組み立てるとこうなる
try db.exec("UPDATE products SET stock = stock - 1 WHERE product_id = 'x'; DROP TABLE products; --';")
```

**正**: **プレースホルダ（`?`）** と `sqlite3_bind_*`。
**SQL 文の文字列には値を一切混ぜません。**

```swift 断片
// 正：文と値を分ける
func run(_ sql: String, _ binds: [(Int32, String)]) throws {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK else { throw … }
    defer { sqlite3_finalize(stmt) }
    for (i, text) in binds { sqlite3_bind_text(stmt, i, text, -1, SQLITE_TRANSIENT) }
    guard sqlite3_step(stmt) == SQLITE_DONE else { throw … }
}

try db.run("UPDATE products SET stock = ? WHERE product_id = ?;",
           [(1, newStockText), (2, productId)])
```

| | 連結 | プレースホルダ |
| --- | --- | --- |
| `'` を含む値 | **壊れる** | そのまま入る |
| SQL インジェクション | **起きうる** | 起きない |
| 実行計画のキャッシュ | 値ごとに別 | **文が同じなら再利用される** |

> **`SQLITE_TRANSIENT`** は「SQLite が文字列をコピーしてから free する」という意味の
> おまじないです。`nil` を渡すと**バッファが先に解放されて**壊れます。

---

## わざと間違う③: `total_jpy` を SQL の中で足す

```swift NG
// わざと間違う版③：合計を SQL の式で出す
try db.exec("""
INSERT INTO sales (...) VALUES ('\(saleID)','completed','cash',
  (SELECT SUM(unit_price_jpy * qty) FROM sale_items WHERE sale_id = '\(saleID)'), ...);
""")
```

**足し算は正しい**です。**設計が間違っています。**

1. **`sales` を書く時点では `sale_items` がまだ入っていない**。
   下のコードの順序では `sales` → `sale_items` なので、**結果は 0** になります
2. **「円合計」と「現金分」は別**（A-6-1）。sats払いの併用では
   `cashForSats`（sats単価の無い行だけ）が必要です。**SQL では出し分けられない**
3. **A-13 の `sales.total_jpy` は `sales` の値**。明細から逆算する設計にすると
   `sale_items` が壊れた時に**合計も壊れる**（原因が追えない）

**正**: `cart.totals()`（`base/2`）で計算した値を**そのまま書く**。

```swift 断片
// base/2
extension Array where Element == CartLine {
    func totals() -> Totals { … }   // sats / cashForSats / cash の3つ
}
```

> **`Totals` の3つを区別して持つ**のはこのためです（A-6-1）。
> SQL に COUNT/SUM を寄せると、`cashForSats` を出す式が必要になります。

---

## 1. トランザクションの，是在 `base/3` にある

**配列側で A-4 の4手順を済ませ、その結果を SQL に書きます。**

| # | 配列側（`base/3`） | SQL 側（このレッスン） |
| --- | --- | --- |
| ① 在庫検証 | `checkStock` / `completeSale` 冒頭 | **何もしない**（書けないなら書かない） |
| ② 販売記録・採番 | `buildSale`（**検証後に採番**・A-19-4） | `INSERT INTO sales` / `sale_items` |
| ③ 在庫減算 | `inventory[i].stock = after` | `UPDATE products SET stock = ?` |
| ④ 在庫変動ログ | `movements.append(...)` | `INSERT INTO stock_movements` |

**②③④ を `BEGIN` 〜 `COMMIT` で包みます。**

```swift 断片
/// `commitSale` の結果を **1トランザクション** で書き込む（A-4）
func persist(_ r: CommitResult, db: Db, now: Date) throws {
    guard case .success(let sale, let its, _) = r else { throw DBError.sql("commit が失敗") }
    try db.exec("BEGIN;")
    do {
        try db.run("INSERT INTO sales (…) VALUES (?,?,?,…);", [ … ])
        for it in its {
            try db.run("INSERT INTO sale_items (…) VALUES (?,?,?,…);", [ … ])
        }
        for m in movements { try db.run("INSERT INTO stock_movements (…) VALUES (?,?,…);", [ … ]) }
        for p in inventory { try db.run("UPDATE products SET stock = ? WHERE product_id = ?;", [ … ]) }
        try db.exec("COMMIT;")
    } catch {
        try? db.exec("ROLLBACK;")   // どれかで失敗したら、全部なかったことにする
        throw error
    }
}
```

> **`guard` で `.failure` を弾くのが第1の防御**です。
> `commitSale` が失敗したなら **SQL に1行も書きません**。
> で、`ROLLBACK` は **それ以外の失敗**（SQL エラー等）の保険です。

---

## 2. 通しの確認

下のコードを、**土台（`base/Types.swift` の型 ＋ `base/3` の §2・§3・§4）に続けて**、
**コマンドラインで**動かします（`import SQLite3` が必要なので）。

```swift
// ════════ 通しの確認（SQLite 保存・A-4 / A-13 / A-19-4）════════
// 実行: swift DB.swift   （SQLite3 を使うので Xcode ではなくコマンドライン）

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DBError: Error {
    case open(String)
    case sql(String)
    case shortage(productId: String, current: Int, requested: Int)
}

final class Db {
    private var h: OpaquePointer?
    init(path: String) throws {
        if sqlite3_open(path, &h) != SQLITE_OK {
            throw DBError.open(h.map { String(cString: sqlite3_errmsg($0)) } ?? "?")
        }
    }
    deinit { if let h = h { sqlite3_close(h) } }

    /// 複数の文実行（スキーマ作成用）
    func exec(_ sql: String) throws {
        var msg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(h, sql, nil, nil, &msg) != SQLITE_OK {
            let m = msg.map { String(cString: $0) } ?? "?"
            sqlite3_free(msg)
            throw DBError.sql(m)
        }
    }

    /// **プレースホルダ（`?`）で値を渡す**。SQL 文字列に値を埋め込まない
    func run(_ sql: String, _ binds: [(Int32, String)]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.sql(String(cString: sqlite3_errmsg(h)))
        }
        defer { sqlite3_finalize(stmt) }
        for (i, text) in binds {
            sqlite3_bind_text(stmt, i, text, -1, SQLITE_TRANSIENT)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DBError.sql(String(cString: sqlite3_errmsg(h)))
        }
    }

    private func prep(_ sql: String, _ binds: [(Int32, String)]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(h, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DBError.sql(String(cString: sqlite3_errmsg(h)))
        }
        for (i, text) in binds {
            sqlite3_bind_text(stmt, i, text, -1, SQLITE_TRANSIENT)
        }
        return stmt
    }

    /// 1つの整数を返す。行が無い / NULL なら nil
    func scalarInt(_ sql: String, _ bind: String) throws -> Int? {
        guard let stmt = try prep(sql, [(1, bind)]) else { return nil }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return nil
    }

    /// 1列の文字列を全件取り出す
    func columnTexts(_ sql: String) throws -> [String] {
        guard let stmt = try prep(sql, []) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return out
    }
}

let schemaSQL = """
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

// ── 型の正（base/2）・ロジックの正（base/3）──
let types47: [ProductType] = [
    ProductType(typeId: "sticker", name: "ステッカー", idPrefix: "ST", idDigits: 3,
                stockMode: .counted, attrLabel1: "色", attrLabel2: nil, attrLabel3: nil),
    ProductType(typeId: "keyholder", name: "キーホルダー", idPrefix: "KH", idDigits: 3,
                stockMode: .unique, attrLabel1: "色", attrLabel2: nil, attrLabel3: nil),
]
var inventory47: [Product] = []
var movements47: [StockMovement] = []
var sales47: [Sale] = []
var items47: [SaleItem] = []
var ids47 = IdSequencer()
let t47 = Date(timeIntervalSince1970: 1_700_000_000)

func p47(_ s: String) { print("  " + s) }
func iso47(_ d: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: d)
}

// ── 配列側の正（A-4 の4手順）。SQL にはこの結果を書くだけ ──
let productMaster47: [Product] = [
    Product(id: "ST-001", typeId: "sticker", name: "ステッカー まる", priceJpy: 300, priceSats: 500, stock: 10),
    Product(id: "KH-005", typeId: "keyholder", name: "キーホルダー 05", priceJpy: 800, priceSats: 1200, stock: 1),
]

/// `commitSale` の結果を **1トランザクション** で書き込む（`base/3` §4）
func persist(_ r: CommitResult, db: Db, now: Date) throws {
    guard case .success(let sale, let its, _) = r else { throw DBError.sql("commit が失敗") }
    try db.exec("BEGIN;")
    do {
        try db.run("INSERT INTO sales (sale_id,status,method,total_jpy,total_sats,received_jpy,change_jpy,confirmed_at,refunded,completed_at) VALUES (?,?,?,?,?,?,?,?,?,?);",
                   [(1, sale.id), (2, sale.status.rawValue), (3, sale.method.rawValue),
                    (4, sale.totalJpy.map(String.init) ?? ""), (5, sale.totalSats.map(String.init) ?? ""),
                    (6, sale.receivedJpy.map(String.init) ?? ""), (7, sale.changeJpy.map(String.init) ?? ""),
                    (8, sale.confirmedAt.map(iso47) ?? ""), (9, sale.refunded ? "1" : "0"),
                    (10, sale.completedAt.map(iso47) ?? "")])
        for it in its {
            try db.run("INSERT INTO sale_items (item_id,sale_id,item_type,type_id,product_id,qty,unit_price_jpy,unit_price_sats,paid_in,name_snapshot) VALUES (?,?,?,?,?,?,?,?,?,?);",
                       [(1, it.id), (2, it.saleId), (3, it.itemType.rawValue), (4, it.typeId ?? ""),
                        (5, it.productId ?? ""), (6, String(it.qty)), (7, String(it.unitPriceJpy)),
                        (8, it.unitPriceSats.map(String.init) ?? ""), (9, it.paidIn.rawValue),
                        (10, it.nameSnapshot)])
        }
        for m in movements47 {
            try db.run("INSERT INTO stock_movements (id,product_id,delta,reason,sale_id,at) VALUES (?,?,?,?,?,?);",
                       [(1, m.id), (2, m.productId), (3, String(m.delta)),
                        (4, m.reason.rawValue), (5, m.saleId ?? ""), (6, iso47(m.at))])
        }
        for p in inventory47 {
            try db.run("UPDATE products SET stock = ? WHERE product_id = ?;",
                       [(1, p.stock.map(String.init) ?? ""), (2, p.id)])
        }
        try db.exec("COMMIT;")
    } catch {
        try? db.exec("ROLLBACK;")
        throw error
    }
}

// ── 実行 ──
let path47 = NSTemporaryDirectory() + "rezi47-\(UUID().uuidString).sqlite"
let db = try Db(path: path47)
try db.exec(schemaSQL)

for p in productMaster47 {
    try db.run("INSERT INTO products (product_id,type_id,name,price_jpy,price_sats,stock,attr_1,attr_2,attr_3,image_ref,is_public,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?);",
               [(1, p.id), (2, p.typeId), (3, p.name), (4, String(p.priceJpy)),
                (5, p.priceSats.map(String.init) ?? ""), (6, p.stock.map(String.init) ?? ""),
                (7, ""), (8, ""), (9, ""), (10, p.imageRef ?? ""), (11, p.isPublic ? "1" : "0"),
                (12, iso47(t47))])
}
// 初期登録は配列側で（A-7）。DB には在庫の正だけを入れる
registerInitialStock(productMaster47, inventory: &inventory47, movements: &movements47,
                     ids: &ids47, types: types47, at: t47)

print("【1】初期状態を書き込む")
for p in productMaster47 {
    try db.run("UPDATE products SET stock = ? WHERE product_id = ?;",
               [(1, p.stock.map(String.init) ?? ""), (2, p.id)])
}
p47("ST-001 在庫: " + String(try db.scalarInt("SELECT stock FROM products WHERE product_id = ?;", "ST-001") ?? -1))
p47("KH-005 在庫: " + String(try db.scalarInt("SELECT stock FROM products WHERE product_id = ?;", "KH-005") ?? -1))

print("【2】会計完了：A-4 の4手順を1トランザクションで書く（A-19-4 の採番）")
var cart47 = [CartLine(product: inventory47[0], qty: 2), CartLine(product: inventory47[1], qty: 1)]
let r47 = commitSale(cart: cart47, inventory: &inventory47, movements: &movements47,
                     sales: &sales47, items: &items47, ids: &ids47, types: types47,
                     chooseSats: false, receivedJpy: 2000, confirmedAt: nil, now: t47)
try persist(r47, db: db, now: t47)
p47("sales: " + (try db.columnTexts("SELECT sale_id FROM sales;")).joined(separator: " "))
p47("sale_items: " + (try db.columnTexts("SELECT item_id FROM sale_items;")).joined(separator: " "))
p47("stock_movements: " + (try db.columnTexts("SELECT id FROM stock_movements;")).joined(separator: " "))
p47("ST-001 在庫: " + String(try db.scalarInt("SELECT stock FROM products WHERE product_id = ?;", "ST-001") ?? -1))
p47("KH-005 在庫: " + String(try db.scalarInt("SELECT stock FROM products WHERE product_id = ?;", "KH-005") ?? -1))

print("【3】在庫不足なら ROLLBACK（何も残らない）")
let beforeSales = try db.columnTexts("SELECT sale_id FROM sales;")
let beforeMv = try db.columnTexts("SELECT id FROM stock_movements;")
let stBefore = try db.scalarInt("SELECT stock FROM products WHERE product_id = ?;", "KH-005")
var badCart = [CartLine(product: inventory47[1], qty: 5)]        // 在庫 0 に対して 5 個
let rBad = commitSale(cart: badCart, inventory: &inventory47, movements: &movements47,
                      sales: &sales47, items: &items47, ids: &ids47, types: types47,
                      chooseSats: false, receivedJpy: 4000, confirmedAt: nil, now: t47)
switch rBad {
case .success: p47("★ 成功してしまった（まずい）")
case .failure(let why):
    p47("commit が失敗: " + why.joined(separator: " / "))
    p47("→ 配列側も何も変わっていない: ST-001=" + String(inventory47[0].stock ?? -1) + " KH-005=" + String(inventory47[1].stock ?? -1))
}
p47("DB の sales が増えない: " + String(beforeSales == (try db.columnTexts("SELECT sale_id FROM sales;"))))
p47("DB の stock_movements が増えない: " + String(beforeMv == (try db.columnTexts("SELECT id FROM stock_movements;"))))
p47("DB の KH-005 が変わらない: " + String(stBefore == (try db.scalarInt("SELECT stock FROM products WHERE product_id = ?;", "KH-005"))))

print("【4】不変条件 I1：products.stock == Σ stock_movements.delta（A-19-1）")
var allMatch47 = true
for p in productMaster47 {
    let d = try db.scalarInt("SELECT SUM(delta) FROM stock_movements WHERE product_id = ?;", p.id) ?? 0
    let s = try db.scalarInt("SELECT stock FROM products WHERE product_id = ?;", p.id) ?? 0
    if s != d { allMatch47 = false }
    p47("\(p.id)  在庫 \(s)  ログ合計 \(d)  " + (s == d ? "OK" : "不一致"))
}
p47("全部一致: " + String(allMatch47))

try? FileManager.default.removeItem(atPath: path47)
```

**期待される出力**:
```
【1】初期状態を書き込む
  ST-001 在庫: 10
  KH-005 在庫: 1
【2】会計完了：A-4 の4手順を1トランザクションで書く（A-19-4 の採番）
  sales: S-20231115-001
  sale_items: S-20231115-001-01 S-20231115-001-02
  stock_movements: M-000001 M-000002 M-000003 M-000004
  ST-001 在庫: 8
  KH-005 在庫: 0
【3】在庫不足なら ROLLBACK（何も残らない）
  commit が失敗: 在庫不足: キーホルダー 05（在庫 0、必要 5）
  → 配列側も何も変わっていない: ST-001=8 KH-005=0
  DB の sales が増えない: true
  DB の stock_movements が増えない: true
  DB の KH-005 が変わらない: true
【4】不変条件 I1：products.stock == Σ stock_movements.delta（A-19-1）
  ST-001  在庫 8  ログ合計 8  OK
  KH-005  在庫 0  ログ合計 0  OK
  全部一致: true
```

---

## 動かし方とできた合図

```
swift DB.swift
```

| # | 期待 |
| --- | --- |
| 1 | `ST-001 在庫: 10` / `KH-005 在庫: 1` |
| 2 | `sales` に `S-20231115-001` が **1件**、`sale_items` に `…-01` `…-02` が **2件**、`stock_movements` に **`M-000001`…`M-000004`** が4件 |
| 3 | `ST-001 在庫: 8` / `KH-005 在庫: 0` |
| 4 | 在庫不足の会計は **`commit` が失敗**して、DB に**何も増えない** |
| 5 | `products.stock == Σ stock_movements.delta` が**全商品で一致** |

> **`swift DB.swift` で実行します**（`swiftc` ではなく）。
> 一時ファイルは実行の最後に削除します。

---

## 考えてみる（答えはない）

1. 配列側で `commitSale` を**先に**呼び、SQL は**あとから**書く設計にしました。
   SQL の `UPDATE` が**途中で失敗**したら、**配列側だけ減算されたまま**になります。
   これは「両方の正がずれる」ことです。
   **`BEGIN` を先に開始してから配列側で計算し、`COMMIT` を最後に出す**という順序にしたら、何が壊れますか。
   それとも、この設計の**利点**は何ですか。
2. `PRIMARY KEY` に `sale_id` / `item_id` / `id` を指定しています。
   `commitSale` を**2回**呼んで**同じ `sale_id`** で書いたら、`UNIQUE` 制約で失敗します。
   `ids.nextSaleID(at:)` は日付ごとに `001` に戻るので、
   **日付をまたいだ採番に衝突の危険**がありますか。あれば、`CHECK` 制約か `ON CONFLICT` で防げますか。
3. A-16 は「端末内DB が唯一の正」と書いています。配列側の `inventory` は
   **DB から読んだキャッシュ**にすぎません。
   `DayKey` の**ローカル日付**で日付が変わったとき、**販売IDと明細IDは衝突しますか**。
   するとして、どう防ぎますか。

---

## ポイント

- **採番は `IdSequencer`**（A-19-4）。`M-{連番:06}`・明細は `{sale_id}-{n:02}`・`01` 始まり
- **`ROLLBACK` しても番号は戻らない**。欠番は**正常**
- **SQL に値を埋め込まない**。プレースホルダ + `sqlite3_bind_*`
- **`SQLITE_TRANSIENT`** を渡す（バッファの寿命を sqlite に**任せる**）
- **合計は `cart.totals()`**。SQL の `SUM` にしない（A-6-1、`cashForSats` が要る）
- **`sales` を先に書く**。明細から逆算すると壊れたときに原因が追えない
- **検証は `base/3`**。SQL で検証しない（1件でも不足なら**1行も書かない**）
- **①②③④ を1トランザクション**。`BEGIN` 〜 `COMMIT`、失敗は `ROLLBACK`（A-4）
- **`is_public` は `INTEGER` 0/1**、`stock` は `NULL` で在庫管理なし型（A-13）
- **日時は `TEXT`（ISO 8601）**。Swift 側では `Date`（A-19-5）

---

## 関連

- `08_在庫を減らす.md` … 配列版の減算（ここで SQL 版に変換する）
- `41_在庫変動ログを記録する.md` … `stock_movements` の採番と値域（A-19-4）
- `12_会計を完了させる.md` … A-4 の4手順そのもの
- `38_日時をISO8601にする.md` … `TEXT` に入れる日時形式（A-19-5）
- `40_販売記録を書き出す.md` … `M-{連番:06}` だから `sale_items` の並びが壊れない理由
- `13_商品マスタCSVを取り込む.md` · `23_種類定義CSVを読み込む.md` … 同じラッパーを使う
- `base/3_標準ロジック.md` §4 · `base/2_型定義.md` … このレッスンの土台