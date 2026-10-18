# 36. sats額をコピーする

元: `../siyou.md` A-6-4

sats待ち画面で使う「sats額をコピー」。**請求sats額**（現金分を含まない。A-6-1）をOS標準のクリップボードへ入れ、WoSの入力欄へ貼り付けられるようにする。

- 金額の計算は**純ロジックなので「ブック（Book）」**で試す。
- クリップボードは**「アプリ（App）」**で行う。APIがOSで違うので `#if os(macOS)` で分岐する（`06_QRを試す.md` の `typealias` と同じ考え方）。

---

## 前提データ
```swift
struct Product {
    let id: String
    let typeId: String       // 種類ID（"sticker" など）
    let name: String
    let priceJpy: Int
    let priceSats: Int?
    var stock: Int?
}

struct CartLine {
    let id: String          // 登録商品は商品ID、野良は "ADHOC-1" など
    let typeId: String?     // 登録商品は種類ID、野良は nil
    let name: String        // カートに入れた時点の商品名
    let unitPriceJpy: Int   // カートに入れた時点の円単価
    let unitPriceSats: Int? // カートに入れた時点のsats単価
    var qty: Int
    let isAdhoc: Bool       // 野良かどうか
}

struct Cart {
    var lines: [CartLine]
}

// 6_データベース.md のサンプル（一部抜粋）
let products: [Product] = [
    Product(id: "ST-001", typeId: "sticker", name: "ステッカー まる",   priceJpy: 300, priceSats: 500,  stock: 10),
    Product(id: "ST-003", typeId: "sticker", name: "ステッカー しかく",  priceJpy: 300, priceSats: nil,  stock: 10),
    Product(id: "KH-002", typeId: "keyholder", name: "キーホルダー 02",   priceJpy: 800, priceSats: 1200, stock: 1),
    Product(id: "KH-008", typeId: "keyholder", name: "キーホルダー 08",   priceJpy: 800, priceSats: 1200, stock: 1),
]

func addLine(_ product: Product, to cart: inout Cart) {
    let line = CartLine(id: product.id, typeId: product.typeId, name: product.name,
                        unitPriceJpy: product.priceJpy,
                        unitPriceSats: product.priceSats, qty: 1, isAdhoc: false)
    cart.lines.append(line)
}
```

---

## 1. 請求sats額を計算する（ブック）
```swift
/// 請求sats額 = Σ（sats単価 × 数量）。sats単価のある行だけ。現金分は含まない。
func requestSats(_ cart: Cart) -> Int {
    var total = 0
    for line in cart.lines {
        if let sats = line.unitPriceSats {
            total += sats * line.qty
        }
    }
    return total
}

/// 現金分 = Σ（円単価 × 数量）。sats単価のない行だけ。
func cashPortion(_ cart: Cart) -> Int {
    var total = 0
    for line in cart.lines {
        if line.unitPriceSats == nil {
            total += line.unitPriceJpy * line.qty
        }
    }
    return total
}

// ── 試す（会計の例2。6_データベース.md）──
var cart = Cart(lines: [])
addLine(products[2], to: &cart)   // KH-002（sats 1200）
addLine(products[1], to: &cart)   // ST-003（satsなし ¥300）

print(requestSats(cart))    // 1200  ← コピーする値
print(cashPortion(cart))    // 300   ← コピーには含まれない
```
- `if let sats = line.unitPriceSats` で sats単価のある行だけ足す
- 現金分は別の関数に分ける（コピーに混ざらないようにする）

**できた合図**: `1200` と `300` が出る。現金分（300）はコピーに含まれない。

---

## 2. クリップボードへコピーする（アプリ）
`06_QRを試す.md` と同じで、OSで違う部分は `#if` で分け、型は `typealias` で名前をそろえる。

```swift
#if os(macOS)
import AppKit
typealias Pasteboard = NSPasteboard    // Mac のクリップボード
#else
import UIKit
typealias Pasteboard = UIPasteboard    // iPad/iOS のクリップボード
#endif

/// 文字列をOS標準のクリップボードへコピーする。
func copyToClipboard(_ text: String) {
    #if os(macOS)
    Pasteboard.general.clearContents()                    // 前の中身を消す
    Pasteboard.general.setString(text, forType: .string)  // 文字を入れる
    #else
    Pasteboard.general.string = text                      // 代入するだけ
    #endif
}

/// 請求sats額だけを「数字だけ」の文字列にしてコピーする。
func copySats(_ cart: Cart) {
    let sats = requestSats(cart)
    copyToClipboard("\(sats)")   // 余計な記号は入れない（貼り付け先で使う）
}
```
- `typealias` で `Pasteboard` という同じ名前になるが、**使い方が違う**ので中の `#if` は残す
- `NSPasteboard.general` は「消してから入れる」、`UIPasteboard.general` は `.string` に代入するだけ
- コピーするのは**数字だけ**。「1200 sats」のように単位まで入れると、貼り付け先で使えないことがある

---

## 3. sats待ち画面に置く（アプリ / SwiftUI）
```swift
import SwiftUI

struct SatsWaitingView: View {
    let cart: Cart
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            Text("請求 \(requestSats(cart)) sats")
                .font(.largeTitle).bold()

            if cashPortion(cart) > 0 {
                Text("現金分 ¥\(cashPortion(cart)) は sats確認後に受け取り")
                    .foregroundStyle(.secondary)
            }

            Button(copied ? "コピーしました" : "sats額をコピー") {
                copySats(cart)
                copied = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
```
- 請求sats額を大きく出しておく（貼り付けに失敗しても目視入力できる）
- 現金分があるときは「sats確認後に受け取る」を併記する（A-6-1）

---

## ポイント
- コピーするのは**請求sats額だけ**。現金分はWoSへ入力しない（A-6-1）
- WoSをiPhoneに置く場合、NeoとiPhoneでクリップボードが共有されるかは未確認。共有されない場合は目視で入力する
- クリップボードのAPIは `#if` で分岐する（Mac＝`NSPasteboard`、iPad＝`UIPasteboard`）

**できた合図**: 「sats額をコピー」を押して、メモ帳やWoSの入力欄に `1200` が貼り付けられる。
