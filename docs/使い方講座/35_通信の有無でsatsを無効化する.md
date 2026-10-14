# 35. 通信の有無でsatsを無効化する

元: `../siyou.md` A-10 #4

sats払いはWoS（Wallet of Satoshi）を使うため、通信が要ると見込まれる。だから**オフラインのときはsats払いを選べなく**し、理由を画面に出す。
あわせて「カートにsats単価のある行が1つもない」ときも選べない（A-6-1）。

- 判定（可否を決める計算）は**純ロジックなので「ブック（Book）」**で試す。
- 接続状態の見張りと画面は**「アプリ（App）」**で行う。
- `Network`フレームワークはMac/iPad共通なので、**コードは同じ**（OS分岐は不要）。

---

## 前提データ
```swift
struct Product {
    let id: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?   // nil は「sats単価なし（現金で受け取る）」
    var stock: Int?
}

// カートの1行
struct CartLine {
    let id: String
    let name: String
    let unitPriceJpy: Int
    let unitPriceSats: Int?   // nil は「sats単価なし（現金で受け取る）」
    var qty: Int
}

struct Cart {
    var lines: [CartLine]
}

// 6_データベース.md のサンプル（一部抜粋。KH-003〜KH-020 も同様）
let products: [Product] = [
    Product(id: "ST-001", name: "ステッカー まる",   priceJpy: 300, priceSats: 500,  stock: 10),
    Product(id: "ST-002", name: "ステッカー さんかく", priceJpy: 300, priceSats: 500,  stock: 10),
    Product(id: "ST-003", name: "ステッカー しかく",  priceJpy: 300, priceSats: nil,  stock: 10),
    Product(id: "KH-001", name: "キーホルダー 01",   priceJpy: 800, priceSats: 1200, stock: 1),
    Product(id: "KH-002", name: "キーホルダー 02",   priceJpy: 800, priceSats: 1200, stock: 1),
    Product(id: "KH-008", name: "キーホルダー 08",   priceJpy: 800, priceSats: 1200, stock: 1),
]

// カートに商品を1行足す（数量1。在庫チェックや重複判定はここでは省略）
func addLine(_ product: Product, to cart: inout Cart) {
    let line = CartLine(id: product.id, name: product.name,
                        unitPriceJpy: product.priceJpy,
                        unitPriceSats: product.priceSats, qty: 1)
    cart.lines.append(line)
}
```

---

## 1. 可否を判定する（ブック）
```swift
/// sats払いが選べるかどうか。
enum SatsAvailability: Equatable {
    case available      // 選べる
    case noConnection   // 通信がない
    case noSatsItem     // sats単価のある行がない
}

/// 接続状態とカートから、sats払いが選べるかを判定する。
/// - Parameters:
///   - isConnected: 通信につながっているか（OSの報告）
///   - cart: いまのカート
func satsAvailability(isConnected: Bool, cart: Cart) -> SatsAvailability {
    if !isConnected {
        return .noConnection          // 通信なしを最優先で出す
    }
    let hasSatsItem = cart.lines.contains { $0.unitPriceSats != nil }
    if !hasSatsItem {
        return .noSatsItem            // sats単価のある行が1つもない
    }
    return .available
}

/// 選べないときの理由（選べるときは nil）。
func satsUnavailableReason(_ a: SatsAvailability) -> String? {
    switch a {
    case .available:    return nil
    case .noConnection: return "通信がないためsats払いは使えません（現金のみ）"
    case .noSatsItem:   return "選択不可（sats単価のある商品がありません）"
    }
}

// ── 試す ──
var cart = Cart(lines: [])
addLine(products[0], to: &cart)   // ST-001（sats 500）
addLine(products[2], to: &cart)   // ST-003（satsなし）

print(satsAvailability(isConnected: true,  cart: cart))   // available
print(satsAvailability(isConnected: false, cart: cart))   // noConnection

var cashOnly = Cart(lines: [])
addLine(products[2], to: &cashOnly)   // ST-003 だけ（sats単価なし）
print(satsUnavailableReason(satsAvailability(isConnected: true, cart: cashOnly))!)
// 選択不可（sats単価のある商品がありません）
```
- `.noSatsItem` は「現金でしか受け取れないカート」。野良商品・ST-003 だけの場合がこれ
- 通信なしを先に見るので、両方に当てはまるときは「通信がない」を出す

**できた合図**: `available` / `noConnection` と、最後に「選択不可（sats単価のある商品がありません）」が出る。

---

## 2. 接続状態を見張る（アプリ）
OSが報告する接続状態を `NWPathMonitor` で受け取る。`Network`は共通なのでOS分岐は不要。

```swift
import Network
import Combine

/// OSが報告する接続状態を保持する。
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.monitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = (path.status == .satisfied)
            // pathHandler は別スレッドで来る。画面用にメインへ戻す
            Task { @MainActor in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    /// 見張りを止める（画面を閉じるとき）。
    func stop() {
        monitor.cancel()
    }
}
```
- `path.status == .satisfied` … 通信が使える状態
- `pathUpdateHandler` は**バックグラウンドで呼ばれる**ので、`Task { @MainActor }` で画面側へ渡す

### 支払方法選択画面に反映する
```swift
import SwiftUI

struct PaymentSelectView: View {
    @StateObject private var net = NetworkMonitor()
    let cart: Cart

    var body: some View {
        let availability = satsAvailability(isConnected: net.isConnected, cart: cart)
        VStack(alignment: .leading, spacing: 12) {
            Button("sats払い") { /* sats待ちへ進む */ }
                .disabled(availability != .available)   // 選べないときは押せない

            if let reason = satsUnavailableReason(availability) {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)         // 押せない理由を表示
            }

            Button("現金") { /* 現金入力中へ進む */ }
        }
        .padding()
    }
}
```
- `.disabled(...)` で選択肢を無効化する。理由は `Text` で必ず出す
- `availability != .available` は「選べない」という意味（`enum` は `==`／`!=` で比べられる）

---

## ポイント・つまずき
- `NWPathMonitor` は**Apple公式**（`import Network`）。MacでもiPadでも同じコードで動く
- 接続あり＝WoSが動く保証ではない。接続ありでもWoSが動かない場合は、sats待ち画面の「方法選び直し」で現金へ切り替える
- ただし **sats確認済み（済ボタン承認後）の併用会計は切り替えられない**（A-6-3）。この判定は「支払方法選択」の段階だけで使う
- 接続状態の取得方法はP0で実機確認する事項（A-16）

**できた合図**: 通信を切ると「sats払い」が押せなくなり、理由「通信がないためsats払いは使えません（現金のみ）」が出る。sats単価のないカートでは「選択不可（sats単価のある商品がありません）」が出る。
