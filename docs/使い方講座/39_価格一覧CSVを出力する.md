# 39. 価格一覧CSVを出力する

元: `../siyou.md` A-1

価格一覧をCSVで出力する。おしながき（値札）との照合に使う。
列は `product_id, type_id, name, price_jpy, price_sats`。`price_sats` は空欄にできる（ST-003 のようにsats価格がない商品）。
**野良商品は含めない**（登録商品だけ）。
CSVのエスケープ（値にカンマや `"` があるときは `"` で囲む）も扱う。**純ロジックなので「ブック（Book）」**で試す。

---

## 前提データ
```swift
import Foundation

struct Product {
    let id: String        // product_id
    let typeId: String    // type_id（例 "sticker" / "keyholder"）
    let name: String
    let priceJpy: Int
    let priceSats: Int?   // nil は空欄にする
    var stock: Int?
}

// 6_データベース.md のサンプル（一部抜粋。KH-003〜KH-020 も同様）
let products: [Product] = [
    Product(id: "ST-001", typeId: "sticker",   name: "ステッカー まる",   priceJpy: 300, priceSats: 500,  stock: 10),
    Product(id: "ST-002", typeId: "sticker",   name: "ステッカー さんかく", priceJpy: 300, priceSats: 500,  stock: 10),
    Product(id: "ST-003", typeId: "sticker",   name: "ステッカー しかく",  priceJpy: 300, priceSats: nil,  stock: 10),
    Product(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01",   priceJpy: 800, priceSats: 1200, stock: 1),
    Product(id: "KH-002", typeId: "keyholder", name: "キーホルダー 02",   priceJpy: 800, priceSats: 1200, stock: 1),
    Product(id: "KH-008", typeId: "keyholder", name: "キーホルダー 08",   priceJpy: 800, priceSats: 1200, stock: 1),
]
```

---

## 1. CSVのエスケープ
```swift
/// CSVの1つの値を安全な形にする。
/// 値に「,」「"」「改行」があれば "..." で囲み、中の " は "" にする。
func csvField(_ value: String) -> String {
    let needsQuote = value.contains(",") || value.contains("\"") || value.contains("\n")
    if !needsQuote { return value }
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
}

print(csvField("ステッカー まる"))   // ステッカー まる（そのまま）
print(csvField("赤, 青"))            // "赤, 青"（カンマがあるので囲む）
print(csvField("5\"の商品"))         // "5""の商品"（" を "" にする）
```
- `siyou.md` のとおり **RFC 4180 準拠**の基本ルール
- 「囲むかどうか」と「中の `"` を `""` にする」の2点だけ

**できた合図**: 2行目は `"赤, 青"`、3行目は `"5""の商品"` のように出る。

---

## 2. 価格一覧CSVを作る
```swift
/// 登録商品の価格一覧をCSV文字列にする。
/// 引数が登録商品だけなので、野良商品は渡さなければ入らない。
func priceListCSV(_ products: [Product]) -> String {
    // ヘッダ行
    var lines = ["product_id,type_id,name,price_jpy,price_sats"]

    for p in products {
        let sats = p.priceSats.map { String($0) } ?? ""   // nil は空欄
        let row: [String] = [
            csvField(p.id),
            csvField(p.typeId),
            csvField(p.name),
            String(p.priceJpy),
            sats,
        ]
        lines.append(row.joined(separator: ","))
    }
    return lines.joined(separator: "\n")
}

print(priceListCSV([products[0], products[2], products[3]]))
```
出力:
```
product_id,type_id,name,price_jpy,price_sats
ST-001,sticker,ステッカー まる,300,500
ST-003,sticker,ステッカー しかく,300,
KH-001,keyholder,キーホルダー 01,800,1200
```
- `p.priceSats.map { String($0) } ?? ""` … 値があれば数字、nilなら空文字
- `joined(separator: ",")` で1行に、`joined(separator: "\n")` で全体をつなぐ

**できた合図**: 上の4行が出る。ST-003 の `price_sats` が空になっている。

---

## 3. ファイルに書き出す（アプリ）
ファイル保存は**「アプリ（App）」**の役目。保存・共有のUIはMacとiPadで違う（A-8）が、CSV文字列を作るところまでは共通。

```swift
import Foundation

/// CSV文字列をUTF-8のテキストとして書き出す。
func writeCSV(_ csv: String, to url: URL) throws {
    try csv.write(to: url, atomically: true, encoding: .utf8)
}

// 使い方の例（url の作り方はOSで違う）
#if os(macOS)
// Mac: 保存ダイアログ（NSSavePanel）で url を得る
#else
// iPad: ファイルアプリ／共有シートで url を得る
#endif
```
- 書き出し先のURLを用意して渡す。文字コードは **UTF-8**
- 保存・共有のUI（保存ダイアログ／共有シート）はここでは割愛
- 文字化けする場合、Excel向けにBOMを付ける方法もある。まずはUTF-8で確認する

---

## ポイント
- `price_sats` が **nil の商品は空欄**（ST-003）。`0` と混同しない（0は価格として不正）
- **野良商品は含めない**。`priceListCSV` に登録商品だけを渡せばよい
- 商品名にカンマや `"` が入っていてもエスケープで壊れない
- 出力はおしながきとの目視照合に使う（A-1）

**できた合図**: 価格一覧のCSVが出て、`price_sats` が無い商品は空欄になる。
