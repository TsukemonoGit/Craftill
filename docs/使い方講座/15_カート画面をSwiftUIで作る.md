# 追加レッスン: カート画面をSwiftUIで作る

元: `../siyou.md` A-3

**カート画面**は、追加済みの商品と合計を表示する画面です（A-3）。レジ画面の右側に並べて表示します（`../開発/5_画面構成.md` の図）。ここは画面（UI）を出すので、**アプリ（App）**として新しく作ります。

カートの1行に出すもの:

- **商品画像・商品名・円単価・sats単価・数量・小計**
- 野良商品には「**野良**」の表示を付ける
- sats単価が空（nil）の行は、sats単価を「**―（現金）**」と表示する（sats払いでも現金で受け取る行）

合計は**2行**で表示します（A-3）。

```
sats払い　○○sats ＋ ○○円
現金　　　○○円
```

- sats払いの○○sats … sats単価のある行の sats合計（Σ sats単価×数量）
- sats払いの○○円 … sats単価のない行の円合計（＝現金分。sats払いでも現金で受け取る分）
- 現金の○○円 … 全行の円合計（Σ 円単価×数量）
- 現金分が0円なら、sats払いは「○○sats」だけ表示する
- sats単価のある行が1行もなければ、sats払いは「選択不可（sats単価のある商品がありません）」と表示する

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

// ── 商品（products 相当）────────────────
struct Product {
    let id: String
    let typeId: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?     // nil なら sats単価なし
}

// ── カートの1行（登録商品と野良を同じ形で持つ）──
struct CartLine: Identifiable {
    let id: String          // 登録商品は商品ID、野良は "ADHOC-1" など
    let typeId: String?     // 登録商品は種類ID、野良は nil
    let name: String        // カートに入れた時点の商品名
    let unitPriceJpy: Int   // カートに入れた時点の円単価
    let unitPriceSats: Int? // カートに入れた時点のsats単価
    var qty: Int
    let isAdhoc: Bool       // 野良かどうか
    let imageName: String?  // 登録商品は商品ID（=画像名）。野良は nil
}

// ── 商品のサンプル（../開発/6_データベース.md より）
let products: [Product] = [
    Product(id: "ST-001", typeId: "sticker",   name: "ステッカー まる",     priceJpy: 300, priceSats: 500),
    Product(id: "ST-002", typeId: "sticker",   name: "ステッカー さんかく", priceJpy: 300, priceSats: 500),
    Product(id: "ST-003", typeId: "sticker",   name: "ステッカー しかく",   priceJpy: 300, priceSats: nil),  // sats単価なし
    Product(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01", priceJpy: 800, priceSats: 1200),
    Product(id: "KH-002", typeId: "keyholder", name: "キーホルダー 02", priceJpy: 800, priceSats: 1200),
]

// ── カートの初期値（登録商品＋野良）──
let initialCart: [CartLine] = [
    CartLine(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01", unitPriceJpy: 800, unitPriceSats: 1200, qty: 1, isAdhoc: false, imageName: "KH-001"),
    CartLine(id: "ST-001", typeId: "sticker", name: "ステッカー まる", unitPriceJpy: 300, unitPriceSats: 500, qty: 2, isAdhoc: false, imageName: "ST-001"),
    CartLine(id: "ST-003", typeId: "sticker", name: "ステッカー しかく", unitPriceJpy: 300, unitPriceSats: nil, qty: 1, isAdhoc: false, imageName: "ST-003"),
    CartLine(id: "ADHOC-1", typeId: nil, name: "委託品A", unitPriceJpy: 1200, unitPriceSats: nil, qty: 1, isAdhoc: true, imageName: nil),
]

/// 名前の画像がアプリに入っているか。
func hasImage(_ name: String) -> Bool {
    #if os(macOS)
    return NSImage(named: name) != nil
    #else
    return UIImage(named: name) != nil
    #endif
}
```

---

## 15-1. 合計を計算する

「sats合計」「現金分」「現金合計」の3つを区別して持ちます。円とsatsは**合算しません**。

```swift
struct Totals {
    var sats = 0         // sats単価のある行のsats合計
    var cashForSats = 0  // sats単価のない行の円合計（＝現金分）
    var cash = 0         // 全行の円合計
}

func totals(_ cart: [CartLine]) -> Totals {
    var t = Totals()
    for line in cart {
        if let s = line.unitPriceSats {
            t.sats += s * line.qty                       // sats単価がある行
        } else {
            t.cashForSats += line.unitPriceJpy * line.qty    // 現金で受け取る行
        }
        t.cash += line.unitPriceJpy * line.qty               // 現金合計には全部足す
    }
    return t
}
```

---

## 15-2. 合計の2行を作る

sats払いが選べるか、現金分があるかで、sats払いの行の出し方が変わります。

```swift
struct TotalLines {
    let satsLine: String
    let cashLine: String
}

func totalLines(_ cart: [CartLine]) -> TotalLines {
    let t = totals(cart)
    let hasSats = cart.contains { $0.unitPriceSats != nil }

    let satsLine: String
    if !hasSats {
        // 全行がsats単価なし → 選択不可
        satsLine = "sats払い　選択不可（sats単価のある商品がありません）"
    } else if t.cashForSats == 0 {
        // 現金分がない → satsだけ
        satsLine = "sats払い　\(t.sats)sats"
    } else {
        // sats ＋ 現金分
        satsLine = "sats払い　\(t.sats)sats ＋ \(t.cashForSats)円"
    }

    return TotalLines(satsLine: satsLine, cashLine: "現金　　　\(t.cash)円")
}
```

---

## 15-3. カート1行のView

画像（または文字）・商品名（野良はラベル付き）・単価・数量・小計を横に並べます。

```swift
struct CartRow: View {
    let line: CartLine
    let onMinus: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            thumb

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if line.isAdhoc {
                        Text("野良")
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.25))
                            .cornerRadius(4)
                    }
                    Text(line.name).font(.body)
                }
                // 円単価 ・ sats単価
                Text("¥\(line.unitPriceJpy) ・ \(satsText)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            // 数量の＋／－
            HStack(spacing: 8) {
                Button("−", action: onMinus)
                Text("\(line.qty)").frame(minWidth: 24)
                Button("＋", action: onPlus)
            }

            // 小計（円）
            Text("¥\(line.unitPriceJpy * line.qty)")
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    // sats単価が空（nil）なら「―（現金）」
    private var satsText: String {
        if let s = line.unitPriceSats { return "\(s) sats" }
        return "―（現金）"
    }

    @ViewBuilder
    private var thumb: some View {
        if let name = line.imageName, hasImage(name) {
            Image(name).resizable().scaledToFit().frame(width: 48, height: 48)
        } else {
            // 画像がない商品・野良は文字表示
            Text(line.isAdhoc ? "野良" : "画像なし")
                .font(.caption2)
                .frame(width: 48, height: 48)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
        }
    }
}
```

---

## 15-4. カート画面本体

```swift
struct CartView: View {
    @State private var cart: [CartLine] = initialCart

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("カート").font(.headline).padding(.horizontal).padding(.top)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(cart) { line in
                        CartRow(line: line,
                                onMinus: { changeQty(line.id, by: -1) },
                                onPlus:  { changeQty(line.id, by: +1) })
                        Divider()
                    }
                }
                .padding(.horizontal)
            }

            Divider()

            // 合計の2行
            let lines = totalLines(cart)
            VStack(alignment: .trailing, spacing: 4) {
                Text(lines.satsLine).font(.body)
                Text(lines.cashLine).font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding()
        }
        .frame(width: 560, height: 460)
    }

    /// 数量を増減する。0になったら行を削除する（A-3 の扱い）。
    private func changeQty(_ id: String, by delta: Int) {
        guard let i = cart.firstIndex(where: { $0.id == id }) else { return }
        let next = cart[i].qty + delta
        if next <= 0 {
            cart.remove(at: i)
        } else {
            cart[i].qty = next
        }
    }
}
```

---

## 15-5. @main の入口

```swift
@main
struct CartApp: App {
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
- `ST-003` と野良の行は sats単価が「**―（現金）**」になっている
- 野良の行に「**野良**」のラベルが付いている
- 合計が次の2行になる

```
sats払い　2200sats ＋ 1500円
現金　　　2900円
```

（内訳: sats 1200×1 + 500×2 = 2200sats、現金分 300×1 + 1200×1 = 1500円、現金合計 800+600+300+1200 = 2900円）

- 数量の「−」で 0 になると、その行が消える

---

## ポイント

- 合計は「**sats合計**」「**現金分**」「**現金合計**」の3つを区別して持つ。円とsatsは合算しない
- sats単価が `nil` の行は「**―（現金）**」と表示する（sats払いでも現金で受け取る行）
- 野良商品（`isAdhoc`）は「**野良**」を付けて登録商品と区別する
- 合計は支払方法ごとに**2行**。現金分が0なら sats だけ、sats単価の行が無ければ「選択不可」
- 画面側は `totalLines(cart)` を呼ぶだけにする（計算と表示を分ける）
- 数量の増減は `@State` のカートを書き換えれば、SwiftUI が自動で描き直す
