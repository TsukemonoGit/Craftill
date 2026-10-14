# 追加レッスン: 商品パネルをSwiftUIで作る

元: `../siyou.md` A-2

**商品パネル**は、登録商品をタイル状に並べ、タップでカートに追加する画面です（A-2）。ここは初めてで画面（UI）を出すので、**アプリ（App）**として新しく作ります。

商品パネルで満たすこと:

- 全登録商品を一覧表示する（**商品画像・商品ID・商品名**）。
- **種類ごとのタブ**で切り替える（ステッカー／キーホルダー）。
- **在庫0**の商品（在庫管理ありの種類）は **SOLD OUT** 表示にし、タップしても追加しない。
- **一点物型**でカートに入っている商品は「**追加済み**」表示にし、タップしたらエラーを表示する。
- **画像がない商品**は、商品ID・商品名・属性の**文字表示**で代替する。

> このファイルだけで完結します。アプリを新規作成し、そのまま貼れば動きます。

---

## 前提データ

```swift
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// ── 在庫の扱い（種類ごと）────────────────
enum StockMode: String {
    case counted   // 数量管理型（ステッカー）
    case unique    // 一点物型（キーホルダー）
    case none      // 在庫管理なし型（今回は商品なし）
}

// ── 種類の定義（product_types 相当）──────
struct ProductType: Identifiable {
    let typeId: String
    let name: String
    let stockMode: StockMode

    var id: String { typeId }   // ForEach で使う
}

// ── 商品（products 相当）────────────────
struct Product: Identifiable {
    let id: String
    let typeId: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?     // nil なら sats単価なし
    var stock: Int?         // none は nil
    let stockMode: StockMode
    let attr1: String?
    let attr2: String?

    // 画像ファイル名は商品IDと同一（A-17）
    var imageName: String { id }
}

// ── カートの1行（この画面では表示用の模擬）──
struct CartLine {
    let product: Product
    var qty: Int
}

// ── 種類定義（../開発/6_データベース.md より）
let productTypes: [ProductType] = [
    ProductType(typeId: "sticker",   name: "ステッカー",   stockMode: .counted),
    ProductType(typeId: "keyholder", name: "キーホルダー", stockMode: .unique),
]

// ── 商品のサンプル（../開発/6_データベース.md より）
// KH-005 は在庫0（SOLD OUT の例）
let products: [Product] = [
    Product(id: "ST-001", typeId: "sticker",   name: "ステッカー まる",     priceJpy: 300, priceSats: 500,  stock: 10, stockMode: .counted, attr1: "黄", attr2: "まる"),
    Product(id: "ST-002", typeId: "sticker",   name: "ステッカー さんかく", priceJpy: 300, priceSats: 500,  stock: 10, stockMode: .counted, attr1: "赤", attr2: "さんかく"),
    Product(id: "ST-003", typeId: "sticker",   name: "ステッカー しかく",   priceJpy: 300, priceSats: nil,  stock: 10, stockMode: .counted, attr1: "青", attr2: "しかく"),
    Product(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01", priceJpy: 800, priceSats: 1200, stock: 1,  stockMode: .unique, attr1: "赤", attr2: "○"),
    Product(id: "KH-002", typeId: "keyholder", name: "キーホルダー 02", priceJpy: 800, priceSats: 1200, stock: 1,  stockMode: .unique, attr1: "青", attr2: "△"),
    Product(id: "KH-003", typeId: "keyholder", name: "キーホルダー 03", priceJpy: 800, priceSats: 1200, stock: 1,  stockMode: .unique, attr1: "緑", attr2: "□"),
    Product(id: "KH-005", typeId: "keyholder", name: "キーホルダー 05", priceJpy: 800, priceSats: 1200, stock: 0,  stockMode: .unique, attr1: "紫", attr2: "○"),
    Product(id: "KH-008", typeId: "keyholder", name: "キーホルダー 08", priceJpy: 800, priceSats: 1200, stock: 1,  stockMode: .unique, attr1: "緑", attr2: "☆"),
    Product(id: "KH-020", typeId: "keyholder", name: "キーホルダー 20", priceJpy: 800, priceSats: 1200, stock: 1,  stockMode: .unique, attr1: "紫", attr2: "☆"),
]
```

---

## 14-1. 1マスの状態を `enum` で表す

パネルの1マスは、次の3つのどれかです。

| 表示 | いつ |
| --- | --- |
| 通常（追加） | 追加できる |
| SOLD OUT | 在庫管理ありで在庫0 |
| 追加済み | 一点物型がすでにカートにある |

```swift
enum PanelState {
    case normal    // 通常（追加できる）
    case soldOut   // SOLD OUT（在庫0）
    case added     // 追加済み（一点物型がカートにある）

    var label: String {
        switch self {
        case .normal:  return "追加"
        case .soldOut: return "SOLD OUT"
        case .added:   return "追加済み"
        }
    }

    // タップで追加してよいか
    var canAdd: Bool { self == .normal }
}

/// 状態を決める。在庫0の判定を先に見るのがポイント。
func panelState(for product: Product, cart: [CartLine]) -> PanelState {
    // 在庫管理なし型は常に販売可（SOLD OUT にしない）
    if product.stockMode == .none { return .normal }
    // 在庫管理ありで在庫0 → SOLD OUT
    if (product.stock ?? 0) <= 0 { return .soldOut }
    // 一点物型がすでにカートにある → 追加済み
    if product.stockMode == .unique,
       cart.contains(where: { $0.product.id == product.id }) {
        return .added
    }
    return .normal
}
```

---

## 14-2. 画像の有無を調べる

商品画像はビルド時にアプリへ同梱します。画像ファイル名は商品IDと同じ（`KH-008` → `"KH-008"`）。OSによって画像の型が違うので `#if` で分けます。

```swift
/// 名前の画像がアプリに入っているか。
func hasImage(_ name: String) -> Bool {
    #if os(macOS)
    return NSImage(named: name) != nil
    #else
    return UIImage(named: name) != nil
    #endif
}
```

- 画像が**ある**商品 → 画像を表示
- 画像が**ない**商品 → 商品ID・商品名・属性の**文字表示**で代替（A-1）

---

## 14-3. パネル1マスのView

画像（または文字）＋商品ID＋商品名＋状態ラベルを並べます。

```swift
struct ProductCell: View {
    let product: Product
    let state: PanelState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                thumb
                Text(product.id).font(.caption).monospaced()
                Text(product.name).font(.caption2).lineLimit(1)
                Text(state.label)
                    .font(.caption2).bold()
                    .foregroundStyle(state == .soldOut ? Color.red : Color.secondary)
            }
            .frame(width: 110, height: 140)
            .padding(6)
            .background(Color.gray.opacity(0.12))
            .cornerRadius(8)
            // SOLD OUT は薄く見せる（タップしても追加しない）
            .opacity(state == .soldOut ? 0.5 : 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumb: some View {
        if hasImage(product.imageName) {
            // 画像がある商品
            Image(product.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
        } else {
            // 画像がない商品は文字表示で代替
            VStack(spacing: 2) {
                Text(product.attr1 ?? "-")
                Text(product.attr2 ?? "-")
            }
            .font(.caption2)
            .frame(width: 80, height: 80)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(4)
        }
    }
}
```

---

## 14-4. 商品パネル本体（種類タブ＋グリッド）

`Picker`（`.segmented`）で種類を切り替え、`LazyVGrid` でタイルを並べます。カートは `@State` で模擬します。

```swift
struct ProductPanelView: View {
    // 選んでいる種類（種類タブ）
    @State private var selectedTypeId: String = productTypes[0].typeId
    // カート（模擬。タップで増える）
    @State private var cart: [CartLine] = []
    // 追加できなかったときのメッセージ
    @State private var notice = ""

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    // いま選んでいる種類の商品だけ
    private var shownProducts: [Product] {
        products.filter { $0.typeId == selectedTypeId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 種類ごとのタブ
            Picker("種類", selection: $selectedTypeId) {
                ForEach(productTypes) { t in
                    Text(t.name).tag(t.typeId)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(shownProducts) { p in
                        ProductCell(product: p, state: panelState(for: p, cart: cart)) {
                            tap(p)
                        }
                    }
                }
                .padding()
            }

            // 動作確認用の表示
            if !notice.isEmpty {
                Text(notice).font(.caption).foregroundStyle(Color.red)
            }
            Text("カート: " + cartText).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 680, height: 560)
    }

    private var cartText: String {
        cart.isEmpty ? "空" : cart.map { "\($0.product.id)×\($0.qty)" }.joined(separator: ", ")
    }

    /// マスをタップしたときの追加処理。
    private func tap(_ p: Product) {
        switch panelState(for: p, cart: cart) {
        case .normal:
            if let i = cart.firstIndex(where: { $0.product.id == p.id }) {
                cart[i].qty += 1              // 数量管理型・在庫管理なし型は数量+1
            } else {
                cart.append(CartLine(product: p, qty: 1))   // 一点物型は常に1
            }
            notice = ""
        case .soldOut:
            notice = "\(p.name) は SOLD OUT です"
        case .added:
            notice = "\(p.name) はカート追加済みです"
        }
    }
}
```

---

## 14-5. @main の入口

画面を出すには、アプリの入口を付けます（起動すると自動で表示されます）。

```swift
@main
struct PanelApp: App {
    var body: some Scene {
        WindowGroup {
            ProductPanelView()   // ← 起動時にこれが自動で出る
        }
    }
}
```

---

## できた合図

- 上部のタブで「ステッカー」「キーホルダー」を切り替えられる
- 各マスに画像（または文字）・商品ID・商品名・状態が出る
- `KH-005`（在庫0）は **SOLD OUT** で、タップすると「SOLD OUT です」と出て追加されない
- `KH-001` をタップ → カートに入り、そのマスは「**追加済み**」になる。もう一度タップすると「追加済みです」と出る
- `ST-001` を2回タップするとカート表示が `ST-001×2` になる

---

## ポイント

- 状態の判断は `panelState(for:cart:)` にまとめ、画面側は `PanelState` の `label` を見るだけにする
- **在庫管理なし型（`none`）は SOLD OUT にしない**。まずここで分岐して抜ける
- 一点物型（`unique`）は「カートに1行だけ」「数量は常に1」。だから追加済みを別表示にする
- 画像が無いときは**文字表示で代替**する（`hasImage` で判定）
- 種類は `Picker`（`.segmented`）で切り替える＝「種類ごとのタブ」。`LazyVGrid` でタイルを並べる
- カートはこの画面では `@State` の模擬。本番では共通のカートにつなぐ
