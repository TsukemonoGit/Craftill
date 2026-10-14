# 30. SOLD OUTを判定する

元: `../siyou.md` A-1（SOLD OUT）、A-2（商品パネル）

**ゴール**: 在庫管理ありの種類で在庫が0なら「SOLD OUT」にして、カートに追加しない。
在庫管理なし型（`none`）は SOLD OUT にならない。商品パネルの表示（通常／SOLD OUT／追加済み）を `enum` で表す。

> 純ロジックの練習。**ブック（Book）**で作る。

---

## 前提データ（このまま貼れば動く）

```swift
import Foundation

// ── 在庫の扱い（種類ごと）────────────────
enum StockMode {
    case counted   // 数量管理型（ステッカー。在庫を数で持つ）
    case unique    // 一点物型（キーホルダー。在庫は1か0）
    case none      // 在庫管理なし型（今回は商品なし）
}

// ── 種類の定義（product_types 相当）──────
struct ProductType {
    let typeId: String       // 例: "sticker"
    let name: String         // 例: "ステッカー"
    let idPrefix: String     // 例: "ST"
    let idDigits: Int        // 例: 3
    let stockMode: StockMode
    let attrLabel1: String?  // 例: "色"
    let attrLabel2: String?  // 例: "模様"
    let attrLabel3: String?  // 例: nil
}

// ── 商品（products 相当）────────────────
struct Product {
    let id: String
    let typeId: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?      // nil なら sats払いでも現金で受け取る
    var stock: Int?          // none は nil
    let attr1: String?
    let attr2: String?
    let attr3: String?
    let isPublic: Bool
}

// ── 種類定義（`../開発/6_データベース.md` より）
let productTypes: [ProductType] = [
    ProductType(typeId: "sticker", name: "ステッカー", idPrefix: "ST", idDigits: 3,
                stockMode: .counted, attrLabel1: "色", attrLabel2: "模様", attrLabel3: nil),
    ProductType(typeId: "keyholder", name: "キーホルダー", idPrefix: "KH", idDigits: 3,
                stockMode: .unique, attrLabel1: "色", attrLabel2: "模様", attrLabel3: nil),
    // 説明用: 在庫管理なし型（今回の商品構成では使わない）
    ProductType(typeId: "made", name: "受注品", idPrefix: "MO", idDigits: 3,
                stockMode: .none, attrLabel1: nil, attrLabel2: nil, attrLabel3: nil),
]

// ── 商品のサンプル（`../開発/6_データベース.md` より）
let products: [Product] = [
    Product(id: "ST-001", typeId: "sticker", name: "ステッカー まる",    priceJpy: 300, priceSats: 500,  stock: 10, attr1: "黄", attr2: "まる",   attr3: nil, isPublic: true),
    Product(id: "ST-002", typeId: "sticker", name: "ステッカー さんかく", priceJpy: 300, priceSats: 500,  stock: 10, attr1: "赤", attr2: "さんかく", attr3: nil, isPublic: true),
    Product(id: "ST-003", typeId: "sticker", name: "ステッカー しかく",   priceJpy: 300, priceSats: nil,  stock: 10, attr1: "青", attr2: "しかく",  attr3: nil, isPublic: true),
    Product(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01",   priceJpy: 800, priceSats: 1200, stock: 1,  attr1: "赤", attr2: "○",       attr3: nil, isPublic: true),
    Product(id: "KH-002", typeId: "keyholder", name: "キーホルダー 02",   priceJpy: 800, priceSats: 1200, stock: 1,  attr1: "青", attr2: "△",       attr3: nil, isPublic: true),
    Product(id: "KH-008", typeId: "keyholder", name: "キーホルダー 08",   priceJpy: 800, priceSats: 1200, stock: 1,  attr1: "緑", attr2: "☆",       attr3: nil, isPublic: true),
    Product(id: "KH-020", typeId: "keyholder", name: "キーホルダー 20",   priceJpy: 800, priceSats: 1200, stock: 1,  attr1: "紫", attr2: "☆",       attr3: nil, isPublic: true),
    Product(id: "MO-001", typeId: "made",    name: "受注品 A",           priceJpy: 500, priceSats: nil,  stock: nil, attr1: nil, attr2: nil,       attr3: nil, isPublic: false),
]

// ── カート（メモリ上の1行）──────────────
struct CartLine {
    var product: Product
    var qty: Int
}
var cart: [CartLine] = []
```

---

## 30-1. 表示を3つに分ける `enum`

商品パネルの1マスは、次の3つのどれかになる。

| 表示 | いつ |
| --- | --- |
| 通常（追加） | 追加できる |
| SOLD OUT | 在庫管理ありで在庫0 |
| 追加済み | 一点物型がすでにカートにある |

```swift
enum PanelState {
    case normal    // 通常（追加できる）
    case soldOut   // SOLD OUT（在庫管理ありで在庫0）
    case added     // 追加済み（一点物型でカートにある）

    var label: String {
        switch self {
        case .normal:  return "追加"
        case .soldOut: return "SOLD OUT"
        case .added:   return "追加済み"
        }
    }

    // タップして追加してよいか
    var canAdd: Bool { self == .normal }
}
```

- `var label: String { ... }` は**計算プロパティ**（`1_初心者メモ.md` 参照）
- `self == .normal` は「自分が `.normal` のときだけ true」

---

## 30-2. 状態を判定する関数

判定の順番が大事。**在庫0かどうかを先に**見る。

```swift
// 種類を引く
func productType(_ product: Product) -> ProductType? {
    productTypes.first { $0.typeId == product.typeId }
}

// カートに入っている数量（無ければ0）
func cartQty(_ id: String) -> Int {
    cart.first { $0.product.id == id }?.qty ?? 0
}

/// 商品パネルの表示を決める。
func panelState(for product: Product) -> PanelState {
    guard let pt = productType(product) else { return .normal }

    // 在庫管理なし型は常に販売可。SOLD OUT にしない
    if pt.stockMode == .none {
        return .normal
    }
    // 在庫管理ありの種類で在庫0 → SOLD OUT
    if (product.stock ?? 0) <= 0 {
        return .soldOut
    }
    // 一点物型がすでにカートにある → 追加済み
    if pt.stockMode == .unique && cartQty(product.id) >= 1 {
        return .added
    }
    return .normal
}
```

- `pt.stockMode == .none` の判定を**最初に**かけるのがポイント。ここで抜けると、在庫0でも SOLD OUT にならない
- `product.stock ?? 0` … `stock` が `nil`（在庫管理なし）なら 0 とみなす

---

## 30-3. 追加処理とつなぐ

パネルをタップしたときの動き。**`canAdd` のときだけ**カートに入れる。

```swift
/// パネルをタップしたときの追加。追加できたら true。
func tapPanel(_ product: Product) -> Bool {
    let state = panelState(for: product)
    guard state.canAdd else {
        print("\(product.id): \(state.label) なので追加しない")
        return false
    }
    if let i = cart.firstIndex(where: { $0.product.id == product.id }) {
        cart[i].qty += 1
    } else {
        cart.append(CartLine(product: product, qty: 1))
    }
    print("\(product.id): カートに追加した")
    return true
}
```

---

## 30-4. 動かしてみる

```swift
// ① 在庫あり → 通常
print("ST-001:", panelState(for: products[0]).label)   // 追加

// ② 在庫0 → SOLD OUT（完了して0になった想定）
var sold = products[2]          // ST-003 をコピー
sold.stock = 0
print("ST-003:", panelState(for: sold).label)          // SOLD OUT

// ③ 一点物をカートに入れる → 追加済み
_ = tapPanel(products[3])       // KH-001 を追加
print("KH-001:", panelState(for: products[3]).label)   // 追加済み

// ④ 在庫管理なし型は在庫を0にしても SOLD OUT にならない
var noneP = products[7]         // MO-001 をコピー
noneP.stock = 0
print("MO-001:", panelState(for: noneP).label)         // 追加（SOLD OUTにならない）
```

**できた合図**:
- `ST-001: 追加`
- `ST-003: SOLD OUT`
- `KH-001: 追加済み`
- `MO-001: 追加`

---

## ポイント
- **在庫管理ありの種類**（`counted`・`unique`）だけが SOLD OUT になる
- 在庫管理なし型（`none`）は在庫0でも常に販売可（SOLD OUT にしない）
- 一点物型がカートにある間は「追加済み」。タップしても追加しない（エラー表示の元）
- 表示の判断は `enum PanelState` にまとめておくと、画面側は `.label` と `.canAdd` を見るだけで済む
