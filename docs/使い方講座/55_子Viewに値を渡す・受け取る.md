# 子Viewに値を渡す・受け取る

元: `../siyou.md` A-3

画面を小さな部品（**子View**）に分けると、見通しがよくなります。そのときに必要になるのが**値の受け渡し**です。題材は「カートの行（`CartRow`）」と「数量ステッパー（－／＋）」です（A-3）。

覚えるのは4つ:

- **親→子**: 子Viewのプロパティ（`let`）で値を渡す。読み取り専用。
- **子→親**: `@Binding` で渡すと、子の書き換えが**親に戻る**。
- **クロージャのコールバック**: 「押された」だけを親へ知らせ、処理は親に任せる。
- **`@ViewBuilder`**: 子Viewに**表示を差し込む**（Svelteの `<slot/>` 相当）。

> **Svelteとの対比**: 親→子のプロパティ ≒ `let { prop } = $props()`。`@Binding` ≒ `bind:value`（双方向）。クロージャ ≒ `onclick={fn}` のようなコールバック。`@ViewBuilder` ≒ `<slot/>`。

画面（UI）を出すので、**アプリ（App）**として新しく作ります。

---

## 前提データ

```swift
import SwiftUI

// ── 在庫の扱い（種類ごと）──
enum StockMode: String { case counted, unique, none }

// ── 商品（products 相当）──
struct Product: Identifiable {
    let id: String
    let typeId: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?      // nil なら sats単価なし
    var stock: Int?
    let stockMode: StockMode
}

// ── カートの1行（登録商品と野良を同じ形で持つ）──
struct CartLine: Identifiable {
    let id: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?
    var qty: Int
    let isAdhoc: Bool        // 野良かどうか
}

// ── 商品のサンプル（../開発/6_データベース.md）──
let products: [Product] = [
    Product(id: "ST-001", typeId: "sticker",   name: "ステッカー まる",     priceJpy: 300, priceSats: 500,  stock: 10, stockMode: .counted),
    Product(id: "ST-003", typeId: "sticker",   name: "ステッカー しかく",   priceJpy: 300, priceSats: nil,  stock: 10, stockMode: .counted),
    Product(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-008", typeId: "keyholder", name: "キーホルダー 08", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
]

// ── カートの初期値（親が持つ状態）──
let initialCart: [CartLine] = [
    CartLine(id: "KH-001", name: "キーホルダー 01", priceJpy: 800, priceSats: 1200, qty: 1, isAdhoc: false),
    CartLine(id: "ST-001", name: "ステッカー まる",  priceJpy: 300, priceSats: 500,  qty: 2, isAdhoc: false),
    CartLine(id: "ST-003", name: "ステッカー しかく", priceJpy: 300, priceSats: nil, qty: 1, isAdhoc: false),
    CartLine(id: "ADHOC-1", name: "委託品A", priceJpy: 1200, priceSats: nil, qty: 1, isAdhoc: true),   // 野良
]
```

---

## 1. 親→子（プロパティで値を渡す）

子Viewは「渡された値を表示するだけ」にします。プロパティは `let` なので読み取り専用です。

```swift
struct CartSummary: View {
    let totalJpy: Int                 // 親から渡される値
    let count: Int

    var body: some View {
        HStack {
            Text("\(count)点")
            Spacer()
            Text("現金　¥\(totalJpy)").bold()
        }
    }
}
```

親は `CartSummary(totalJpy: total, count: cart.count)` のように渡すだけです。

## 2. 子→親（`@Binding` で書き換えを戻す）

数量の「－／＋」は、子の部品にします。子が `@Binding var qty` を持ち、親から `$` 付きで渡すと、**子の書き換えが親の状態に戻ります**。

```swift
struct QuantityStepper: View {
    @Binding var qty: Int             // 子→親（書き換えは親に戻る）

    var body: some View {
        HStack(spacing: 8) {
            Button("－") { if qty > 1 { qty -= 1 } }   // 1未満にはしない
            Text("\(qty)").frame(minWidth: 24)
            Button("＋") { qty += 1 }
        }
    }
}
```

- `@Binding` … 「**親が持っている値**を、ここから書き換えてよい」という印。
- 親は `QuantityStepper(qty: $line.qty)` のように、`$` を付けて渡す。
- 0にしたい場合は、下の「削除」ボタンのように**行の削除**として扱う（A-3）。

## 3. クロージャのコールバック（処理は親に任せる）

「削除ボタンが押された」ことだけを親に知らせ、実際の削除は親が行います。子は**どう消すかを知らなくてよい**のが利点です。

```swift
struct CartRow: View {
    @Binding var line: CartLine        // 子→親（数量の書き換え用）
    let onDelete: () -> Void           // クロージャのコールバック

    var body: some View {
        HStack(spacing: 10) {
            if line.isAdhoc {
                Text("野良").font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.25)).cornerRadius(4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)                              // 親から渡された値
                Text("¥\(line.priceJpy) ・ \(satsText)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            QuantityStepper(qty: $line.qty)                  // $ で Binding を渡す
            Text("¥\(line.priceJpy * line.qty)").frame(width: 80, alignment: .trailing)
            Button("削除", action: onDelete)                 // 押されたら親の処理を呼ぶ
        }
        .padding(.vertical, 6)
    }

    // sats単価が空（nil）なら「―（現金）」
    private var satsText: String { line.priceSats.map { "\($0) sats" } ?? "―（現金）" }
}
```

## 4. `@ViewBuilder`（表示を差し込む）

子Viewの**箱**だけ用意して、中身は親が渡す形です。Svelteの `<slot/>` に近い役割です。

```swift
struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content    // 差し込まれる表示

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content                          // ← 親が渡した中身が出る
        }
        .padding()
        .background(Color.gray.opacity(0.08)).cornerRadius(10)
    }
}
```

親は `Panel(title: "カート") { ... }` と**波カッコ**で中身を渡します。

---

## 5. 組み立てる（親）

親は状態（`@State` のカート）を持ち、子へ `$` で渡します。

```swift
struct CartView: View {
    @State private var cart: [CartLine] = initialCart

    var body: some View {
        Panel(title: "カート") {
            VStack(spacing: 0) {
                // $cart で各要素の Binding を作り、$line で受ける
                ForEach($cart) { $line in
                    CartRow(line: $line, onDelete: { delete(line.id) })   // 値は line、Binding は $line
                    Divider()
                }
                CartSummary(totalJpy: totalJpy, count: cart.count)         // 親→子（読み取り専用）
            }
        }
        .frame(width: 580, height: 440)
    }

    private var totalJpy: Int { cart.reduce(0) { $0 + $1.priceJpy * $1.qty } }

    private func delete(_ id: String) {
        cart.removeAll { $0.id == id }
    }
}
```

- `ForEach($cart) { $line in ... }` … 各要素の**Binding**を受け取る書き方。中では `line` が値、`$line` が Binding。
- `CartRow(line: $line, ...)` … Binding を渡す（子→親）。
- `CartSummary(totalJpy: totalJpy, ...)` … ただの値を渡す（親→子）。

## `@main` の入口

```swift
@main
struct RowApp: App {
    var body: some Scene {
        WindowGroup {
            CartView()   // ← 起動時にこれが自動で出る
        }
    }
}
```

---

## できた合図

- 4行（KH-001×1／ST-001×2／ST-003×1／野良 委託品A×1）が表示される
- `ST-003` と野良の行の sats単価が **―（現金）** になっている
- 野良の行に **野良** のラベルが付いている
- **＋／－**を押すと、その行の数量と小計、合計が変わる（子の操作が親に戻っている）
- **削除**を押すとその行が消える（クロージャのコールバックで親が削除している）

---

## ポイント

- 親→子は**プロパティ**（`let`）。子は表示するだけ。
- 子→親は **`@Binding`**。親は `$` を付けて渡す。子の書き換えが親に戻る。
- 「押されたことだけ伝える」場合は**クロージャのコールバック**（`let onDelete: () -> Void`）。処理は親に任せる。
- 中身を差し込む箱は **`@ViewBuilder`**。`<slot/>` のように親が中身を渡す。
- `ForEach($cart) { $line in ... }` で、配列の各要素を Binding として取り出せる。
- 数量0にする操作は**行の削除**として扱う（A-3）。子は1未満にしない。
