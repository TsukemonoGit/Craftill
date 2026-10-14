# 52. extensionで型を広げる（既存の型にメソッド・計算プロパティを足す）

元: `../siyou.md` A-3（カート表示）、A-6-1（請求sats額・現金分）

**ゴール**: `extension` で、**すでにある型を書き換えずに**機能を足す。
`Int` に `formattedYen`（`¥1,200`）、`String` に `isNumberOnly`、
`Product` に `satsLabel`（`1200 sats` / `―（現金）`）を足す。
さらに `extension Product: Priced {}` のように、**プロトコル準拠を後付け**する。

> 画面は出さず、`print` で結果を見る**純ロジック**の練習。**ブック（Book）**で作る。
> **レッスン同士は独立**。このファイルだけで完結する。

---

## 前提データ（このまま貼れば動く）

```swift
import Foundation

// ── 在庫の扱い（種類ごと）──────────────
enum StockMode: String {
    case counted = "counted"   // 数量管理型
    case unique  = "unique"    // 一点物型
    case none    = "none"      // 在庫管理なし型
}

// ── 種類の定義（product_types 相当）────
struct ProductType {
    let typeId: String        // 例: "sticker"
    let name: String          // 例: "ステッカー"
    let idPrefix: String      // 例: "ST"
    let idDigits: Int         // 例: 3
    let stockMode: StockMode
}

// ── 商品（products 相当）──────────────
struct Product {
    let id: String
    let typeId: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?   // nil なら sats単価なし（sats払いでも現金で受け取る）
    var stock: Int?       // none は nil
}

let productTypes: [ProductType] = [
    ProductType(typeId: "sticker",   name: "ステッカー",   idPrefix: "ST", idDigits: 3, stockMode: .counted),
    ProductType(typeId: "keyholder", name: "キーホルダー", idPrefix: "KH", idDigits: 3, stockMode: .unique),
]

// 商品（../開発/6_データベース.md のサンプルより。KH は抜粋）
let products: [Product] = [
    Product(id: "ST-001", typeId: "sticker",   name: "ステッカー まる",     priceJpy: 300, priceSats: 500,  stock: 10),
    Product(id: "ST-002", typeId: "sticker",   name: "ステッカー さんかく", priceJpy: 300, priceSats: 500,  stock: 10),
    Product(id: "ST-003", typeId: "sticker",   name: "ステッカー しかく",   priceJpy: 300, priceSats: nil,  stock: 10),
    Product(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01",     priceJpy: 800, priceSats: 1200, stock: 1),
    Product(id: "KH-005", typeId: "keyholder", name: "キーホルダー 05",     priceJpy: 800, priceSats: 1200, stock: 1),
    Product(id: "KH-008", typeId: "keyholder", name: "キーホルダー 08",     priceJpy: 800, priceSats: 1200, stock: 1),
]

// ── 「価格を持つもの」という約束（後付け準拠で使う）──
protocol Priced {
    var priceJpy: Int { get }
    var priceSats: Int? { get }
    var name: String { get }
}
```

---

## 1. extension とは（型を広げる）

`extension 型名 { ... }` で、**その型の定義を書き換えずに**メソッドや計算プロパティを足せる。

- 既存の型（`Int` や `String`、自分で作った `Product`）に後から足せる
- 元のコードは1行も変えない → 既存の動きを壊さない
- 追加できるのは**メソッド**と**計算プロパティ**（`var` で `{ }` を返すもの）。**保存プロパティは足せない**

```swift
extension Product {
    /// 円価格を「¥300」の形で返す
    var priceYenLabel: String { "¥\(priceJpy)" }
}

print(products[0].priceYenLabel)   // ¥300
```

---

## 2. 既存の型に足す：`Int.formattedYen`（`¥1,200`）

`Int` は標準の型。そこに3桁区切りの表示を足す。**商品の円価格**の表示に使う（A-3、A-8）。

```swift
extension Int {
    /// 3桁区切りの円表記（1200 → "¥1,200"）
    var formattedYen: String {
        let negative = self < 0
        let digits = String(abs(self))
        var grouped = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(",") }
            grouped.append(ch)
        }
        return (negative ? "-¥" : "¥") + String(grouped.reversed())
    }
}

print(300.formattedYen)      // ¥300
print(1200.formattedYen)     // ¥1,200
print(1234567.formattedYen)  // ¥1,234,567
```

- `Int` の既存コードは無変更。**足しただけ**
- `300.formattedYen` のように、ふつうの `Int` と同じ書き方で呼べる
- 商品の一覧表示に使う:

```swift
for p in products {
    print(p.id, p.name, p.priceJpy.formattedYen)
}
```

**できた合図**:
```
ST-001 ステッカー まる ¥300
ST-002 ステッカー さんかく ¥300
ST-003 ステッカー しかく ¥300
KH-001 キーホルダー 01 ¥800
KH-005 キーホルダー 05 ¥800
KH-008 キーホルダー 08 ¥800
```

---

## 3. 既存の型に足す：`String.isNumberOnly`

CSVの数値は**半角数字のみ**（A-1）。全角や記号が混じっていないかを調べる。

```swift
extension String {
    /// 半角数字だけでできているか（空文字は false）
    var isNumberOnly: Bool {
        !isEmpty && allSatisfy { $0.isASCII && $0.isNumber }
    }
}

print("1200".isNumberOnly)   // true
print("12a0".isNumberOnly)   // false
print("".isNumberOnly)       // false
print("１２".isNumberOnly)   // false（全角は isASCII が false）
```

- `allSatisfy { ... }` … 全部の文字が条件を満たすか
- `$0.isASCII` … 半角かどうか（全角数字を弾く）
- `!isEmpty` … 空文字を「数字だけ」と誤判定しないため

---

## 4. `Product.satsLabel`（`1200 sats` / `―（現金）`）

sats単価があるか無いかで表示を分ける（A-3）。`nil` は「sats払いでも現金で受け取る」印。

```swift
extension Product {
    /// sats単価の表示。無ければ「―（現金）」
    var satsLabel: String {
        if let s = priceSats { return "\(s) sats" }
        else { return "―（現金）" }
    }
}

for p in products {
    print(p.name, p.priceJpy.formattedYen, p.satsLabel)
}
```

**できた合図**:
```
ステッカー まる ¥300 500 sats
ステッカー さんかく ¥300 500 sats
ステッカー しかく ¥300 ―（現金）
キーホルダー 01 ¥800 1200 sats
キーホルダー 05 ¥800 1200 sats
キーホルダー 08 ¥800 1200 sats
```

- `formattedYen` と `satsLabel` を**並べて**使える。どちらも `extension` で足したもの

---

## 5. プロトコル準拠を後付けする（`extension Product: Priced {}`）

`extension` は**プロトコルへの準拠**も後から付けられる。
`Product` は既に `priceJpy` / `priceSats` / `name` を持っているので、中身を書かなくても準拠できる。

```swift
extension Product: Priced {}   // 必要な項目はすでに揃っている
```

これで `Product` は「**Priced である**」と見なせる。約束だけを受け取る関数に渡せる。

```swift
/// Priced なら何でも合計できる（型を1つに固定しない）
func totalJpy(_ items: [any Priced]) -> Int {
    items.reduce(0) { $0 + $1.priceJpy }
}

print(totalJpy(products))   // 3300
```

**できた合図**:
```
3300
```

- `[any Priced]` … 「Priced に準拠した何か」の配列。`Product` 以外の型も、準拠させれば入れられる
- **元の `Product` の定義を変えずに**、共通の約束を持たせられた

---

## 6. `Codable` / `Identifiable` 準拠を後付けする

同じ要領で、標準プロトコルも後付けできる。

```swift
extension Product: Identifiable {}   // id: String があるのでそのまま準拠できる
extension Product: Codable {}        // String / Int / Int? だけでできているので自動で変換できる

if let data = try? JSONEncoder().encode(products) {
    print("JSONエンコード成功: \(data.count > 0)")
}
```

- `Identifiable` … `id` を持っていれば準拠できる。SwiftUI の `ForEach` で並べやすくなる
- `Codable` … 保存プロパティがすべて変換可能なら、中身を書かずに JSON にできる
- どちらも **`extension` の1行だけ**。`Product` 本体は無変更

**できた合図**:
```
JSONエンコード成功: true
```

---

## Svelte/JSでいうと

JSでも `String.prototype.foo = ...` のように既存の型を広げられる（プロトタイプ拡張）。
ただしこれは**全コードに効いてしまう**（グローバル汚染）。名前が衝突すると別の場所が壊れる。
Swiftの `extension` は**型安全・スコープ付き**で、足せるのはメソッドと計算プロパティだけ。
保存プロパティは足せず、既存の動きを上書きもしない。
プロトコルの後付け準拠は、TSの**インターフェースのマージ**に近いが、コンパイル時に検査される。

---

## まとめ

- `extension 型名 { ... }` で、**既存の型を書き換えずに**メソッド・計算プロパティを足せる
- `Int.formattedYen`（`¥1,200`）／`String.isNumberOnly`／`Product.satsLabel` を足した
- `extension Product: Priced {}` で**プロトコル準拠を後付け**できる。`[any Priced]` で共通に扱える
- `Codable` / `Identifiable` 準拠も `extension` 1行で後付けできる
- JSのプロトタイプ拡張と違い、Swiftは**型安全・スコープ付き**で既存を壊しにくい
