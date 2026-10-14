# 追加レッスン: 商品マスタCSVを取り込む【大問・小問】

元: `../siyou.md` A-1

商品マスタCSVは、商品（`products`）をまとめて登録するための表です。店頭で使う前に、このCSVをアプリへ取り込みます。

CSVの共通ルール（A-1）:

- RFC 4180 の**簡易版**。区切りはカンマ。値はダブルクォート `"` で囲める。
- 改行は **CRLF / LF** のどちらもよい。
- **1行目はヘッダ行**。列は**見出し名**で識別し、**列の順序は問わない**。
- 必須列が欠けていたらエラー。
- 値の**前後の空白は取り除く**。**空行は無視**する。
- **1行でもエラーがあれば、全体を取り込まない**。エラーは「行番号・列名・理由」で一覧にする。

対象の列:

| 列 | 必須 | 値・規則 |
| --- | --- | --- |
| `product_id` | 必須 | `<接頭辞>-<番号>`。番号は種類の桁数（例 `KH-008`） |
| `type_id` | 必須 | 種類定義に存在すること |
| `name` | 必須 | 商品名。空は不可 |
| `price_jpy` | 必須 | 1以上の整数 |
| `price_sats` | 任意 | 1以上の整数。空なら sats払いでも現金で受け取る |
| `stock` | 種類による | `counted` は0以上、`unique` は0/1、`none` は空 |
| `attr_1`〜`attr_3` | 任意 | 属性の値 |
| `is_public` | 必須 | `1`（公開）／`0`（非公開） |

> ここは**純ロジック**なので **ブック（Book）** で書ける。画面（SwiftUI）は別の回で扱う。
> このファイルだけで完結します。冒頭のコードをそのままPlaygroundsに貼り、その下に続けて書けば動きます。

---

## 前提データ

```swift
import Foundation   // trimmingCharacters に必要

// ── 在庫の扱い（種類ごと）────────────────
enum StockMode: String {
    case counted   // 数量管理型（ステッカー）
    case unique    // 一点物型（キーホルダー）
    case none      // 在庫管理なし型（今回は商品なし）
}

// ── 種類の定義（product_types 相当）──────
struct ProductType {
    let typeId: String       // 例: "sticker"
    let idPrefix: String     // 例: "ST"
    let idDigits: Int        // 例: 3
    let stockMode: StockMode
}

// ── 商品（products 相当）────────────────
struct Product {
    let id: String
    let typeId: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?      // nil なら sats単価なし
    var stock: Int?          // none は nil
    let attr1: String?
    let attr2: String?
    let attr3: String?
    let isPublic: Bool
}

// ── 種類定義（../開発/6_データベース.md より）
let productTypes: [ProductType] = [
    ProductType(typeId: "sticker",   idPrefix: "ST", idDigits: 3, stockMode: .counted),
    ProductType(typeId: "keyholder", idPrefix: "KH", idDigits: 3, stockMode: .unique),
]

// ── 取り込みエラー1件分 ──────────────────
struct CSVError {
    let line: Int       // 行番号（1始まり。1行目はヘッダ）
    let column: String  // 列名
    let reason: String  // 理由
}

// ── 取り込み結果 ────────────────────────
enum ImportResult {
    case success([Product])   // 全部よければ商品の配列
    case failure([CSVError])  // 1行でもエラーなら理由の一覧
}
```

---

## 小問1: CSVを行とセルに分ける（パース）

文字を1つずつ見て、`"` の中のカンマや改行は**区切りにしない**ようにします。

```swift
/// CSV文字列を行×セルに分ける（RFC 4180 の簡易版）。
func parseCSV(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    let chars = Array(text)
    var i = 0

    while i < chars.count {
        let c = chars[i]
        if inQuotes {
            if c == "\"" {
                // 次の文字も " なら、エスケープされた1つの "（"" → "）
                if i + 1 < chars.count && chars[i + 1] == "\"" {
                    field.append("\"")
                    i += 1
                } else {
                    inQuotes = false   // ここで囲みが閉じる
                }
            } else {
                field.append(c)        // 囲みの中はそのまま
            }
        } else {
            if c == "\"" {
                inQuotes = true        // 囲みが始まる
            } else if c == "," {
                row.append(field)
                field = ""
            } else if c == "\r" || c == "\n" {
                // 改行（CRLF / LF / CR すべて同じ扱い）
                row.append(field)
                field = ""
                rows.append(row)
                row = []
                // CRLF のときは \n を飛ばす
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" {
                    i += 1
                }
            } else {
                field.append(c)
            }
        }
        i += 1
    }
    // 最後の行（改行で終わっていない場合）
    if !field.isEmpty || !row.isEmpty {
        row.append(field)
        rows.append(row)
    }
    return rows
}
```

- `inQuotes` が「いまダブルクォートの中にいるか」を持つフラグ
- 囲みの中では `,` と改行を**そのまま**セルに足す

---

## 小問2: 見出し名から列番号を調べる

列の**順序は問わない**ので、ヘッダから「何番目か」を引きます。

```swift
/// ヘッダから列名の位置を返す（無ければ nil）。
func columnIndex(_ header: [String], _ name: String) -> Int? {
    header.firstIndex { $0.trimmingCharacters(in: .whitespaces) == name }
}

/// 小さな補助: 文字列を整数に（空や数字以外は nil）。
func intValue(_ s: String?) -> Int? {
    guard let s = s, !s.isEmpty else { return nil }
    return Int(s)
}

/// 小さな補助: 空文字は nil にする。
func emptyToNil(_ s: String?) -> String? {
    guard let s = s, !s.isEmpty else { return nil }
    return s
}

/// product_id が種類の接頭辞・桁数に合うか（例: ST-001）。
func matchesID(_ id: String, type: ProductType) -> Bool {
    let parts = id.split(separator: "-")
    guard parts.count == 2 else { return false }
    let prefix = String(parts[0])
    let number = String(parts[1])
    return prefix == type.idPrefix
        && number.count == type.idDigits
        && Int(number) != nil
}
```

---

## 小問3: 1行を商品に変換する（検証つき）

```swift
/// 1行を Product に変換する。エラーがあれば理由を返し、商品は作らない。
func parseRow(_ row: [String], header: [String], line: Int,
              types: [ProductType]) -> (Product?, [CSVError]) {
    var errors: [CSVError] = []

    // セルを取り出す（前後の空白を取り除く。足りないセルは空扱い）
    func value(_ name: String) -> String {
        guard let idx = columnIndex(header, name), idx < row.count else { return "" }
        return row[idx].trimmingCharacters(in: .whitespaces)
    }

    // product_id
    let id = value("product_id")
    if id.isEmpty { errors.append(CSVError(line: line, column: "product_id", reason: "空です")) }

    // type_id（種類定義に存在すること）
    let typeId = value("type_id")
    let type = types.first { $0.typeId == typeId }
    if typeId.isEmpty {
        errors.append(CSVError(line: line, column: "type_id", reason: "空です"))
    } else if type == nil {
        errors.append(CSVError(line: line, column: "type_id", reason: "存在しない種類IDです"))
    }

    // product_id の形式（接頭辞・桁数）
    if let t = type, !id.isEmpty, !matchesID(id, type: t) {
        errors.append(CSVError(line: line, column: "product_id",
                               reason: "種類 \(t.typeId) の形式ではありません"))
    }

    // name
    let name = value("name")
    if name.isEmpty { errors.append(CSVError(line: line, column: "name", reason: "空です")) }

    // price_jpy（1以上の整数）
    let priceJpy = intValue(value("price_jpy"))
    if priceJpy == nil || priceJpy! < 1 {
        errors.append(CSVError(line: line, column: "price_jpy",
                               reason: "1以上の整数ではありません"))
    }

    // price_sats（任意。入っていれば1以上の整数）
    var priceSats: Int? = nil
    let rawSats = value("price_sats")
    if !rawSats.isEmpty {
        if let s = Int(rawSats), s >= 1 { priceSats = s }
        else { errors.append(CSVError(line: line, column: "price_sats",
                                      reason: "1以上の整数ではありません")) }
    }

    // stock（種類による: counted 0以上 / unique 0・1 / none 空）
    var stock: Int? = nil
    if let t = type {
        let raw = value("stock")
        switch t.stockMode {
        case .none:
            break
        case .counted:
            if let s = Int(raw), s >= 0 { stock = s }
            else { errors.append(CSVError(line: line, column: "stock", reason: "0以上の整数ではありません")) }
        case .unique:
            if let s = Int(raw), s == 0 || s == 1 { stock = s }
            else { errors.append(CSVError(line: line, column: "stock", reason: "0か1ではありません")) }
        }
    }

    // is_public（1 or 0）
    let pub = value("is_public")
    if pub != "0" && pub != "1" {
        errors.append(CSVError(line: line, column: "is_public", reason: "1か0ではありません"))
    }

    guard errors.isEmpty else { return (nil, errors) }

    let product = Product(id: id, typeId: typeId, name: name,
                          priceJpy: priceJpy!, priceSats: priceSats, stock: stock,
                          attr1: emptyToNil(value("attr_1")),
                          attr2: emptyToNil(value("attr_2")),
                          attr3: emptyToNil(value("attr_3")),
                          isPublic: pub == "1")
    return (product, [])
}
```

---

## 小問4: 全体を取り込む（1行でもエラーなら全体を止める）

```swift
/// 商品マスタCSVを取り込む。1行でもエラーがあれば全体を取り込まない。
func importProducts(csv: String, types: [ProductType]) -> ImportResult {
    let rows = parseCSV(csv)
    guard let header = rows.first else {
        return .failure([CSVError(line: 1, column: "-", reason: "ヘッダ行がありません")])
    }
    let headerTrimmed = header.map { $0.trimmingCharacters(in: .whitespaces) }
    var errors: [CSVError] = []

    // 必須列のチェック
    for col in ["product_id", "type_id", "name", "price_jpy", "is_public"] {
        if columnIndex(headerTrimmed, col) == nil {
            errors.append(CSVError(line: 1, column: col, reason: "必須列がありません"))
        }
    }
    // stock 列は、在庫管理ありの種類があれば必須
    let needsStock = types.contains { $0.stockMode != .none }
    if needsStock && columnIndex(headerTrimmed, "stock") == nil {
        errors.append(CSVError(line: 1, column: "stock", reason: "必須列がありません"))
    }
    guard errors.isEmpty else { return .failure(errors) }

    // 各行を処理（1行目はヘッダなので飛ばす）
    var products: [Product] = []
    for (i, row) in rows.enumerated() where i > 0 {
        // 空行は無視
        if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
        let (product, rowErrors) = parseRow(row, header: headerTrimmed, line: i + 1, types: types)
        errors.append(contentsOf: rowErrors)
        if let p = product { products.append(p) }
    }

    // 1件でもエラーがあれば全体を取り込まない
    if !errors.isEmpty { return .failure(errors) }
    return .success(products)
}
```

---

## 試す

列の順序をわざと入れ替えたCSVでも、見出し名で識別できることを確かめます。

```swift
let csv = """
is_public,product_id,type_id,name,stock,price_jpy,price_sats,attr_1,attr_2,attr_3
1,ST-001,sticker,ステッカー まる,10,300,500,黄,まる,
1,ST-002,sticker,ステッカー さんかく,10,300,500,赤,さんかく,
1,ST-003,sticker,ステッカー しかく,10,300,,青,しかく,
1,KH-001,keyholder,キーホルダー 01,1,800,1200,赤,○,
"""

switch importProducts(csv: csv, types: productTypes) {
case .success(let ps):
    print("取り込み成功: \(ps.count)件")
    for p in ps {
        print(p.id, p.name, p.priceJpy, p.priceSats ?? 0, p.stock ?? 0)
    }
case .failure(let errs):
    for e in errs { print("\(e.line)行目 \(e.column): \(e.reason)") }
}
```

**できた合図**:
```
取り込み成功: 4件
ST-001 ステッカー まる 300 500 10
ST-002 ステッカー さんかく 300 500 10
ST-003 ステッカー しかく 300 0 10
KH-001 キーホルダー 01 800 1200 1
```

次に、エラーのあるCSVを試します。価格が数字でない行と、`is_public` が `2` の行を混ぜます。

```swift
let badCSV = """
product_id,type_id,name,price_jpy,price_sats,stock,attr_1,attr_2,attr_3,is_public
ST-001,sticker,ステッカー まる,300,500,10,黄,まる,,1
KH-021,keyholder,キーホルダー 21,abc,1200,1,赤,○,,1
ST-002,sticker,ステッカー さんかく,300,500,10,赤,さんかく,,2
"""

switch importProducts(csv: badCSV, types: productTypes) {
case .success(let ps):
    print("取り込み成功: \(ps.count)件")
case .failure(let errs):
    print("取り込み失敗（全体を取り込まない）")
    for e in errs { print("\(e.line)行目 \(e.column): \(e.reason)") }
}
```

**できた合図**:
```
取り込み失敗（全体を取り込まない）
3行目 price_jpy: 1以上の整数ではありません
4行目 is_public: 1か0ではありません
```

---

## ポイント

- CSVはまず**素の表**（行×セル）にしてから、ヘッダで列名を引く。だから**列順不同**でよい
- 空行は捨て、値は**前後の空白を除去**する
- 検証は「必須列の有無」→「行ごとの値」の順。エラーは**行番号・列名・理由**で持つ
- **1行でもエラーがあれば `success` を返さない**。中途半端に一部だけ登録しないための方針
- `struct CSVError` を用意しておくと、画面側でそのまま一覧表示できる
