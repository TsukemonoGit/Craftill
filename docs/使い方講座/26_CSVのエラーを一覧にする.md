# 26. CSVのエラーを一覧にする

元: `../siyou.md` A-1（取り込み時の検証）

**ゴール**: 商品マスタCSVの取り込みで、エラーを1件ずつではなく**一覧**で出す。
エラーは「**行番号・列名・理由**」の構造体 `CSVError` で持つ。
**1行でもエラーがあれば全体を取り込まない**、という方針を実装する。

> 画面は出さず、`print` で結果を見る**純ロジック**の練習。**ブック（Book）**で作る。
> **レッスン同士は独立**。このファイルだけで完結する。

---

## 前提データ（このまま貼れば動く）

```swift
import Foundation

// ── 在庫の扱い（種類ごと）──────────────
enum StockMode: String {
    case counted = "counted"
    case unique  = "unique"
    case none    = "none"
}

// ── 種類の定義（product_types 相当）────
struct ProductType {
    let typeId: String     // 例: "sticker"
    let idPrefix: String   // 例: "ST"
    let idDigits: Int      // 例: 3
    let stockMode: StockMode
}

// 今回の種類（../開発/6_データベース.md より）
let productTypes: [ProductType] = [
    ProductType(typeId: "sticker",   idPrefix: "ST", idDigits: 3, stockMode: .counted),
    ProductType(typeId: "keyholder", idPrefix: "KH", idDigits: 3, stockMode: .unique),
]

// すでに端末内DBにある商品ID（重複チェック用）
let existingIDs: Set<String> = ["ST-001", "ST-002", "ST-003", "KH-001", "KH-008"]

// ── 商品マスタCSVの1行（値はすべて文字列のまま）──
struct ProductRow {
    let row: Int          // 行番号（ヘッダを1行目として数える）
    let productId: String // product_id
    let typeId: String    // type_id
    let name: String      // name
    let priceJpy: String  // price_jpy
    let priceSats: String // price_sats（空可）
    let stock: String     // stock（空可）
    let isPublic: String  // is_public
}
```

---

## 1. エラーを表す構造体

```swift
/// 取り込みエラー1件。行番号・列名・理由を持つ
struct CSVError {
    let row: Int
    let column: String
    let reason: String
}

/// エラー一覧を1行ずつ出す
func showErrors(_ errors: [CSVError]) {
    for e in errors {
        print("\(e.row)行目 \(e.column): \(e.reason)")
    }
}
```

---

## 2. 1行を検証する

1行を調べて、見つかったエラーを**まとめて配列で返す**。
`seenIDs` は「このCSV内で既に出た product_id」を覚えておくためのもの（`inout` で受け取る）。

```swift
/// 1行を検証して、エラーの配列を返す（エラーが無ければ空）
func validate(_ row: ProductRow,
              existingIDs: Set<String>,
              seenIDs: inout Set<String>) -> [CSVError] {
    var errors: [CSVError] = []
    let type = productTypes.first { $0.typeId == row.typeId }

    // type_id が種類定義にあるか
    if type == nil {
        errors.append(CSVError(row: row.row, column: "type_id",
                               reason: "種類定義に存在しない（\(row.typeId)）"))
    }

    // product_id の形式が type_id の種類と一致するか
    if let t = type {
        let prefix = t.idPrefix + "-"
        if !row.productId.hasPrefix(prefix) {
            errors.append(CSVError(row: row.row, column: "product_id",
                                   reason: "接頭辞が種類 \(row.typeId) と一致しない"))
        } else {
            let number = row.productId.dropFirst(prefix.count)
            if number.count != t.idDigits || Int(number) == nil {
                errors.append(CSVError(row: row.row, column: "product_id",
                                       reason: "番号が \(t.idDigits) 桁の数字でない"))
            }
        }
    }

    // product_id の重複（既存DB・同じCSV内の両方）
    if existingIDs.contains(row.productId) {
        errors.append(CSVError(row: row.row, column: "product_id", reason: "すでに登録済み"))
    }
    if seenIDs.contains(row.productId) {
        errors.append(CSVError(row: row.row, column: "product_id", reason: "CSV内で重複"))
    }
    seenIDs.insert(row.productId)

    // name が空でないか
    if row.name.trimmingCharacters(in: .whitespaces).isEmpty {
        errors.append(CSVError(row: row.row, column: "name", reason: "空は不可"))
    }

    // price_jpy が1以上の整数か
    if !(Int(row.priceJpy).map { $0 >= 1 } ?? false) {
        errors.append(CSVError(row: row.row, column: "price_jpy", reason: "1以上の整数でない"))
    }

    // price_sats（空は可。値があるなら1以上の整数）
    let sats = row.priceSats.trimmingCharacters(in: .whitespaces)
    if !sats.isEmpty, !(Int(sats).map { $0 >= 1 } ?? false) {
        errors.append(CSVError(row: row.row, column: "price_sats", reason: "1以上の整数でない"))
    }

    // stock が種類の範囲か
    let stock = row.stock.trimmingCharacters(in: .whitespaces)
    if let t = type {
        switch t.stockMode {
        case .counted:
            if !(Int(stock).map { $0 >= 0 } ?? false) {
                errors.append(CSVError(row: row.row, column: "stock", reason: "0以上の整数でない"))
            }
        case .unique:
            if !(Int(stock).map { $0 == 0 || $0 == 1 } ?? false) {
                errors.append(CSVError(row: row.row, column: "stock", reason: "0または1でない"))
            }
        case .none:
            if !stock.isEmpty {
                errors.append(CSVError(row: row.row, column: "stock", reason: "在庫管理なし型は空にする"))
            }
        }
    }

    // is_public が 1 / 0 か
    if row.isPublic != "1" && row.isPublic != "0" {
        errors.append(CSVError(row: row.row, column: "is_public", reason: "1または0でない"))
    }

    return errors
}
```

- `Int("300円")` は `nil` になる。`.map { $0 >= 1 }` で「Intにできたときだけ条件判定」できる
- `seenIDs.insert(...)` は `Set` への追加。返り値は使わなくてよい

---

## 3. 全体を取り込むか決める

```swift
/// 全行を検証し、1行でもエラーがあれば取り込まない
func importProducts(_ rows: [ProductRow],
                    existingIDs: Set<String>) -> (imported: Bool, errors: [CSVError]) {
    var allErrors: [CSVError] = []
    var seenIDs = Set<String>()
    for row in rows {
        allErrors.append(contentsOf: validate(row, existingIDs: existingIDs, seenIDs: &seenIDs))
    }
    if allErrors.isEmpty {
        return (true, [])          // 1件もエラーなし → 取り込む
    } else {
        return (false, allErrors)  // 1行でもエラー → 全体を取り込まない
    }
}
```

- `append(contentsOf:)` … 配列に配列をまとめて足す
- エラーが残ったまま `imported: false` を返すので、**部分取り込み**は起きない

---

## 4. わざとエラーを作って一覧を出す

代表的な違反を**1行ずつ**入れてみる。

```swift
let rows: [ProductRow] = [
    // 2行目: product_id が種類と不一致（KH のはずが ST）
    ProductRow(row: 2, productId: "ST-010", typeId: "keyholder", name: "キーホルダー 21",
               priceJpy: "800", priceSats: "1200", stock: "1", isPublic: "1"),
    // 3行目: 既存の KH-001 と重複
    ProductRow(row: 3, productId: "KH-001", typeId: "keyholder", name: "キーホルダー 01",
               priceJpy: "800", priceSats: "1200", stock: "1", isPublic: "1"),
    // 4行目: price_jpy が整数でない
    ProductRow(row: 4, productId: "ST-020", typeId: "sticker", name: "ステッカー",
               priceJpy: "300円", priceSats: "", stock: "5", isPublic: "1"),
    // 5行目: unique なのに stock が範囲外
    ProductRow(row: 5, productId: "KH-021", typeId: "keyholder", name: "キーホルダー 21",
               priceJpy: "800", priceSats: "1200", stock: "5", isPublic: "1"),
    // 6行目: is_public が 1/0 以外
    ProductRow(row: 6, productId: "ST-021", typeId: "sticker", name: "ステッカー",
               priceJpy: "300", priceSats: "", stock: "5", isPublic: "true"),
]

let result = importProducts(rows, existingIDs: existingIDs)
if result.imported {
    print("取り込み完了")
} else {
    print("取り込み中止: \(result.errors.count)件のエラー")
    showErrors(result.errors)
}
```

**できた合図**:
```
取り込み中止: 5件のエラー
2行目 product_id: 接頭辞が種類 keyholder と一致しない
3行目 product_id: すでに登録済み
4行目 price_jpy: 1以上の整数でない
5行目 stock: 0または1でない
6行目 is_public: 1または0でない
```

---

## 5. 正しいCSVなら取り込める

```swift
let goodRows: [ProductRow] = [
    ProductRow(row: 2, productId: "ST-004", typeId: "sticker", name: "ステッカー ほし",
               priceJpy: "300", priceSats: "500", stock: "10", isPublic: "1"),
    ProductRow(row: 3, productId: "KH-021", typeId: "keyholder", name: "キーホルダー 21",
               priceJpy: "800", priceSats: "1200", stock: "1", isPublic: "1"),
]

let ok = importProducts(goodRows, existingIDs: existingIDs)
print(ok.imported ? "取り込み完了" : "取り込み中止")   // 取り込み完了
```

**できた合図**: `取り込み完了` と出る。

---

## まとめ

- エラーは「**行番号・列名・理由**」の `CSVError` で持つ
- 1行を検証して**複数エラー**を返せる。全行分を**まとめて一覧**にする
- **1行でもエラーがあれば全体を取り込まない**（`imported: false`）
- 代表的な違反: `product_id` の不一致・重複、価格が1以上の整数でない、`stock` が範囲外、`is_public` が 1/0 以外
