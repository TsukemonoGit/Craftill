# @Observableで状態を共有する

元: `../siyou.md` A-3

**カート**と**会計状態**は、1つの画面だけでなく、商品パネル・カート・支払方法…と**アプリ全体で共有**したい値です（A-3）。
これを1つのクラスにまとめ、`@Observable` を付けると、**中身が変わったら使っている画面が自動で描き直され**ます。

- `@Observable` … クラスに付ける印。**読んだプロパティだけ**が更新の対象になる（`import Observation`）。
- `@State` … そのクラスの**実体を1つ作る**（アプリの入口で1回）。
- `@Environment` … 作った実体を**下の画面へ配る**（受け取る側）。

> **Svelteとの対比**: `@Observable` クラス ≒ Svelte の **store（`writable`）**。`@State` で1つ作る ≒ `const cart = writable(...)`。`@Environment` で受け取る ≒ `$cart` で読む。`cart.add()` ≒ store のメソッド。カートの追加・削除を store の**メソッド**にするのがポイントです。
> 古い書き方の `ObservableObject` ＋ `@Published` との違いは最後にまとめます。

画面（UI）を出すので、**アプリ（App）**として新しく作ります。

---

## 前提データ

```swift
import SwiftUI
import Observation      // @Observable

// ── 在庫の扱い（種類ごと）──
enum StockMode: String { case counted, unique, none }

// ── 商品（products 相当）──
struct Product: Identifiable {
    let id: String
    let typeId: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?      // nil なら sats単価なし
    var stock: Int?          // 在庫管理なし型は nil
    let stockMode: StockMode
}

// ── カートの1行（登録商品と野良を同じ形で持つ）──
struct CartLine {
    let id: String          // 登録商品は商品ID、野良は "ADHOC-1" など
    let typeId: String?     // 登録商品は種類ID、野良は nil
    let name: String        // カートに入れた時点の商品名
    let unitPriceJpy: Int   // カートに入れた時点の円単価
    let unitPriceSats: Int? // カートに入れた時点のsats単価
    var qty: Int
    let isAdhoc: Bool       // 野良かどうか
}

// ── 会計の状態（A-4）──
enum SaleState: String, CaseIterable {
    case idle             // 待機中
    case scanning         // スキャン中
    case choosingPayment  // 支払方法選択
    case cashInput        // 現金入力中
    case satsWaiting      // sats待ち
    case done             // 完了
}

// ── 商品のサンプル（../開発/6_データベース.md）──
let products: [Product] = [
    Product(id: "ST-001", typeId: "sticker",   name: "ステッカー まる",     priceJpy: 300, priceSats: 500,  stock: 10, stockMode: .counted),
    Product(id: "ST-002", typeId: "sticker",   name: "ステッカー さんかく", priceJpy: 300, priceSats: 500,  stock: 10, stockMode: .counted),
    Product(id: "ST-003", typeId: "sticker",   name: "ステッカー しかく",   priceJpy: 300, priceSats: nil,  stock: 10, stockMode: .counted),
    Product(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-002", typeId: "keyholder", name: "キーホルダー 02", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-005", typeId: "keyholder", name: "キーホルダー 05", priceJpy: 800, priceSats: 1200, stock: 0, stockMode: .unique),  // 在庫0（SOLD OUT）
    // KH-003〜KH-020 も同じ形（円800・sats1200・在庫1・一点物）。全20点は ../開発/6_データベース.md
]
```

---

## 1. アプリ全体の状態を `@Observable` にする

カートと会計状態を1つにまとめ、追加・削除を**メソッド**にします（A-3）。

```swift
@Observable
final class CartStore {
    var lines: [CartLine] = []      // カート（野良の明細も含む）
    var saleState: SaleState = .idle

    // 派生値（持たずに毎回計算する）
    var totalJpy: Int { lines.reduce(0) { $0 + $1.unitPriceJpy * $1.qty } }

    /// 登録商品をカートに追加する（A-1 の種類ごとのルール）。
    @discardableResult
    func add(_ p: Product) -> String {
        // 在庫管理ありで在庫0なら SOLD OUT（追加しない）
        if p.stockMode != .none, (p.stock ?? 0) <= 0 {
            return "\(p.name) は SOLD OUT です"
        }
        // 一点物型は、すでにカートにあればエラー。数量は常に1
        if p.stockMode == .unique, lines.contains(where: { $0.id == p.id }) {
            return "\(p.name) はカート追加済みです"
        }
        if let i = lines.firstIndex(where: { $0.id == p.id }), p.stockMode != .unique {
            let next = lines[i].qty + 1
            if p.stockMode == .counted, let stock = p.stock, next > stock {
                return "\(p.name) は在庫 \(stock) を超えています"
            }
            lines[i].qty = next                      // 数量管理型・在庫管理なし型は +1
        } else {
            lines.append(CartLine(id: p.id, typeId: p.typeId, name: p.name, unitPriceJpy: p.priceJpy,
                                  unitPriceSats: p.priceSats, qty: 1, isAdhoc: false))
        }
        if saleState == .idle { saleState = .scanning }   // 初回追加でスキャン中へ（A-4）
        return "追加: \(p.name)"
    }

    /// 行を削除する。
    func remove(_ id: String) {
        lines.removeAll { $0.id == id }
        if lines.isEmpty { saleState = .idle }        // カートが空になったら待機中へ（A-4）
    }

    /// 数量を増減する。0になったら行を削除する（A-3）。
    func changeQty(_ id: String, by delta: Int) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        let next = lines[i].qty + delta
        if next <= 0 { remove(id) } else { lines[i].qty = next }
    }

    /// 会計を終えたら空にする。
    func reset() {
        lines = []
        saleState = .idle
    }
}
```

- `@Observable` … `var` を普通に書き換えてよい。`@Published` のような印は不要。
- 追加・削除を**メソッド**にまとめたので、画面側は `cart.add(p)` を呼ぶだけ。
- 派生値 `totalJpy` は持たず、読むたびに計算する（`$derived` 相当）。

---

## 2. 1つ作って、配る（`@State` → `@Environment`）

実体は**アプリの入口で1つ**だけ作り、`.environment(cart)` で下の画面へ配ります。

```swift
@main
struct ShopApp: App {
    @State private var cart = CartStore()   // アプリに1つだけ作る

    var body: some Scene {
        WindowGroup {
            RegisterView()
                .environment(cart)          // 下の画面へ配る
        }
    }
}
```

受け取る側は `@Environment(CartStore.self)` と書くだけで、**同じ1つの実体**を見られます。

```swift
struct RegisterView: View {
    @Environment(CartStore.self) private var cart   // 受け取る
    @State private var notice = ""

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // ── 左: 商品パネル（タップで追加）──
            VStack(alignment: .leading, spacing: 6) {
                Text("商品").font(.headline)
                ForEach(products) { p in
                    Button("\(p.id) \(p.name)") { notice = cart.add(p) }
                }
            }
            .padding()

            Divider()

            // ── 右: カート ──
            VStack(alignment: .leading, spacing: 6) {
                Text("カート（\(cart.saleState.rawValue)）").font(.headline)
                ForEach(cart.lines) { line in
                    HStack(spacing: 8) {
                        Text(line.name)
                        Spacer()
                        Button("－") { cart.changeQty(line.id, by: -1) }
                        Text("×\(line.qty)")
                        Button("＋") { cart.changeQty(line.id, by: 1) }
                        Text("¥\(line.unitPriceJpy * line.qty)").frame(width: 80, alignment: .trailing)
                        Button("削除") { cart.remove(line.id) }
                    }
                }
                Text("現金　¥\(cart.totalJpy)").bold()
                if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(.red) }
            }
            .padding()
        }
        .frame(width: 720, height: 460)
    }
}
```

**別の画面からも同じ実体**が見えるので、たとえば合計だけ別Viewに置いても値がそろいます。

```swift
struct TotalBadge: View {
    @Environment(CartStore.self) private var cart   // 同じカートを見ている
    var body: some View {
        Text("合計 ¥\(cart.totalJpy)")
    }
}
```

---

## 3. 受け取った側で書き換える（`@Bindable`）

`@Environment(CartStore.self)` は**読む・メソッドを呼ぶ**には十分です。
`Picker` や `Stepper` のように **Binding（`$`）が要る**ときは、`@Bindable` で書き換え可能な版を作ります。

```swift
struct SaleStatePicker: View {
    @Environment(CartStore.self) private var cart
    var body: some View {
        @Bindable var cart = cart              // Binding を作る
        Picker("会計状態", selection: $cart.saleState) {   // $ で双方向に
            ForEach(SaleState.allCases, id: \.self) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
    }
}
```

---

## 4. 古い書き方との違い

| | 古い（〜iOS 16） | 新しい（@Observable） |
| --- | --- | --- |
| クラスの印 | `class C: ObservableObject` | `@Observable final class C` |
| 変更通知 | 変える `var` に `@Published` | **不要**（自動） |
| 実体を作る | `@StateObject` | `@State` |
| 配る | `.environmentObject(cart)` | `.environment(cart)` |
| 受け取る | `@EnvironmentObject var cart: C` | `@Environment(C.self) var cart` |
| 更新の範囲 | `@Published` のどれか1つで全体 | **読んだプロパティだけ** |

- 古い書き方は `@Published` を付け忘れると画面が更新されません。新しい方は**付ける印が減って**間違えにくいです。
- 新しい方の「読んだプロパティだけ更新」は、大きな状態でも**無駄な再描画が減る**利点があります。

---

## できた合図

- 商品をタップするとカートに追加され、会計状態が `.idle` から **`.scanning`** になる
- `ST-001` を2回押すと `ST-001×2`。`KH-001` を2回押すと「カート追加済みです」と出る
- 在庫0の `KH-005` を押すと「SOLD OUT です」と出て追加されない
- 「－」で0になると行が消え、全部消えると会計状態が **`.idle`** に戻る
- 合計が `現金 ¥...` に出る（`TotalBadge` と同じ値）

---

## ポイント

- アプリ全体で共有する状態（カート・会計状態）は **`@Observable` クラス**にまとめる。
- 追加・削除は、画面ではなく**クラスのメソッド**に書く（種類ごとのルールは A-1）。
- **入口で `@State` で1つ作り、`.environment` で配り、`@Environment` で受け取る**。
- 値の更新で**読んだプロパティだけ**が描き直される。`@Published` は不要。
- `$`（Binding）が要る部品には **`@Bindable`** を使う。
- 古い `ObservableObject` ＋ `@Published` は `@StateObject` / `@EnvironmentObject` と組だった。新しくなり、印が減って分かりやすくなった。
