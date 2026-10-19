# 追加レッスン: カート画面をSwiftUIで作る

元: `../siyou.md` A-3、A-7、A-19-7
受け入れテスト C-6 #33・#49・#50

**カート画面**は、追加済みの商品と合計を表示する画面です（A-3）。
レジ画面の右側に並べて表示します（`../開発/5_画面構成.md` の図）。

**このレッスンは画面（View）を書くレッスンです。**
「どの型を使うか」「どの関数に任せるか」は `base/` に決まっています。

| 担当 | 正 |
| --- | --- |
| `CartLine` / `Product` / `Totals` | `base/2_型定義.md`（=`base/Types.swift`） |
| 合計の2行 `totalLines` | `base/3_標準ロジック.md` §1 |
| ＋／− と削除 `increase` / `decrease` / `remove` | `base/5_カート編集.md` §3・§4・§5 |
| 返り値の3つの意味 `CartEdit` | `base/5_カート編集.md` §2 |

---

## まず土台をペーストする

1. `base/Types.swift` の**型だけ**（上の4行に書く「使うとこ」まで）
2. `base/3_標準ロジック.md` の **§1 合計**
3. `base/5_カート編集.md` の **§1〜§6**（通しの確認は要らない）

> **`Totals` も `totalLines` も書き直さないでください。** `base/` のものです。
> このレッスンで書くのは **View と、画面が `base/5` を呼ぶ方法**だけです。

---

## わざと間違う①: 数量を画面で直接書き換える

A-3 はこう書いています。

> **「＋」で数量を増やす**。「−」で減らす。**0 になったら確認ダイアログを出す**

「− で0になったら確認」は**守らなければなりません**。
画面が `qty` を直接書くと、**「在庫を見ること」「確認を出すこと」を全部すっ飛ばせます**。

```swift NG
// わざと間違う版①：画面がカートを直接書き換える
struct CartView: View {
    @State private var cart: [CartLine] = initialCart

    /// 数量を増減する。0になったら行を削除する
    private func changeQty(_ id: String, by delta: Int) {
        guard let i = cart.firstIndex(where: { $0.id == id }) else { return }
        let next = cart[i].qty + delta
        if next <= 0 {
            cart.remove(at: i)              // ★ 確認ダイアログを飛ばしている
        } else {
            cart[i].qty = next              // ★ 在庫を見ていない
        }
    }
}
```

**何が壊れるか**

| # | 破綻 | 違反 |
| --- | --- | --- |
| 1 | 在庫 1 の**一点物型**を ＋ で何個でも入れられる | A-1、base/5 §3 `increase` |
| 2 | **在庫 3 の商品を ＋ で 10 個**入れられる。会計が終わるまで気づかない | A-3、base/5 §3 `increase` |
| 3 | **在庫管理なし型と数量管理型を区別しない**（どちらも無制限） | A-1、base/5 §1 `addCheck` |
| 4 | 0 になったら**即削除**。確認ダイアログが出ない | A-3、C-6 #49・#50 |
| 5 | 削除を**取り消せない** | A-3 |

**破綻 2 がいちばん危険**です。`commitSale`（`base/3` §4）が坐在**チェックしてもう失敗する**ので、
「カートに入れて会計に進む → 最後にエラー」になります。
**入れ秒钟に弾く**のが A-3 の要求です。

---

## わざと間違う②: `imageName` を `CartLine` に入れる

`CartLine` は `base/Types.swift` のものを使います。**画像 field はありません**。

```swift NG
// わざと間違う版②：カート行に画像名を持たせる
struct CartLine: Identifiable {
    let id: String
    let name: String
    var qty: Int
    let imageName: String?   // ★ 在庫表と二重に持つことになる
}
```

**これが駄目な理由**は `stock` を `CartLine` に持たせるのと**同じ**です（A-7）。

| | 在庫 | 画像 |
| --- | --- | --- |
| 本当の場所 | `products.stock`（在庫表） | `products.image_ref`（在庫表） |
| 持ち回ると | 減算のときにずれる | **画像を入れ替えても古い名前が出る** |

**その理由**：A-14 で「`has_image` は保持項目ではない。`image_ref` から導出する」と決めています。
**カートの行も同じ方針で、画像の有無は在庫表から引きます。**

---

## 1. ＋／− は `base/5` に委譲する

画面の `＋` `−` ボタンは、**index を `base/5` に渡すだけ**にします。

```swift
/// 数量の増減を **base/5** に任せる。画面はこの返り値を受け取るだけ
func changeQty(_ i: Int, by delta: Int,
               cart: inout [CartLine],
               inventory: [Product],
               types: [ProductType]) -> CartEdit {
    delta > 0
        ? increase(at: i, cart: &cart, inventory: inventory, types: types)
        : decrease(at: i, cart: &cart, inventory: inventory, types: types)
}
```

- `delta > 0` なら `increase`、そうでなければ `decrease`
- **`cart` は `inout`**。`increase` はできるなら即実行する
- 返り値は **`CartEdit`**（`.applied` / `.needsConfirm` / `.rejected`）

> **`delta` で `if` を書かなくていい。** 0 はボタンから来ません（`＋` と `−` だけ）。

---

## 2. `CartEdit` の3つを `.alert` につなぐ

`CartEdit` は **「確認ダイアログが要るか」**で3つに分かれています（`base/5` §2）。
画面は **3つの case を `.alert` に渡すだけ**。ロジックを持ちません（A-19-9 #9）。

| `CartEdit` | 画面がすること |
| --- | --- |
| `.applied(メッセージ)` | 何もしない（`cart` はもう変わっている） |
| `.needsConfirm( CartDelete )` | **削除の確認ダイアログ**を出す。まだ何も変えていない |
| `.rejected(理由)` | **理由のダイアログ**を出す。在庫超過・一点物 |

```swiftui
/// `.alert` に渡すもの。**UI の型**なので base/ には無い
struct CartAlert: Identifiable {
    enum Kind {
        case delete(CartDelete)     // 「削除しますか」
        case reject(String)         // 「なぜできないか」
    }
    let id = UUID()
    let kind: Kind

    var title: String {
        switch kind {
        case .delete: return "カートから削除しますか"
        case .reject: return "追加できません"
        }
    }
    var message: String {
        switch kind {
        case .delete(let d): return "\(d.message) を削除します"
        case .reject(let m):  return m
        }
    }
    /// 削除の確認のときだけ「削除」ボタンを出す（A-19-9 #9）
    var showDeleteButton: Bool {
        if case .delete = kind { return true }
        return false
    }
}
```

```swiftui
struct CartView: View {
    @State private var cart: [CartLine] = initialCart
    @State private var alert: CartAlert? = nil

    let inventory: [Product] = initialInventory
    let types: [ProductType] = initialTypes

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("カート").font(.headline).padding(.horizontal).padding(.top)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(cart.enumerated()), id: \.element.id) { i, line in
                        CartRow(line: line,
                                imageRef: inventory.first { $0.id == line.id }?.imageRef,
                                onMinus: { change(i, by: -1) },
                                onPlus:  { change(i, by: +1) })
                        Divider()
                    }
                }
                .padding(.horizontal)
            }

            Divider()

            // 合計の2行：**base/3 §1** を呼ぶだけ（画面は計算しない）
            let lines = totalLines(cart)
            VStack(alignment: .trailing, spacing: 4) {
                Text(lines.satsLine).font(.body)
                Text(lines.cashLine).font(.body)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding()
        }
        .frame(width: 560, height: 460)
        .alert(item: $alert) { a in
            if a.showDeleteButton {
                // 削除の確認 → OK で performDelete、キャンセルは何もしない
                return Alert(title: Text(a.title),
                             message: Text(a.message),
                             primaryButton: .destructive(Text("削除")) {
                                 if case .delete(let d) = a.kind {
                                     performDelete(d, cart: &cart)
                                 }
                             },
                             secondaryButton: .cancel())
            } else {
                return Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
            }
        }
    }

    /// ＋／− ボタンが呼ぶ。**判定は base/5、表示だけここ**（A-19-9 #9）
    private func change(_ i: Int, by delta: Int) {
        let r = changeQty(i, by: delta, cart: &cart, inventory: inventory, types: types)
        switch r {
        case .applied:      break                            // もう済んでいる
        case .needsConfirm(let d): alert = CartAlert(kind: .delete(d))
        case .rejected(let m):     alert = CartAlert(kind: .reject(m))
        }
    }
}
```

> **`switch` に `.applied` の分岐が要るのは明示するため**です。
> ここで `cart` を触ったら `base/5` と二重で数えます。

---

## 3. カート1行のView

画像（または文字）・商品名（野良はラベル付き）・単価・数量・小計を横に並べます。
**画像は `imageRef` を `View` の引数で受け取ります**（`CartLine` には無い・§わざと間違う②）。

```swiftui
struct CartRow: View {
    let line: CartLine
    let imageRef: String?    // **在庫表から引いた**画像参照。CartLine には持たせない
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
                Text("¥\(line.unitPriceJpy) ・ \(satsText)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("−", action: onMinus)
                Text("\(line.qty)").frame(minWidth: 24)
                Button("＋", action: onPlus)
            }

            Text("¥\(line.subtotalJpy)")            // base/2 の計算プロパティ
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    /// sats単価が空（nil）なら「―（現金）」（A-3、A-6-1）
    private var satsText: String {
        if let s = line.unitPriceSats { return "\(s) sats" }
        return "―（現金）"
    }

    @ViewBuilder
    private var thumb: some View {
        if let ref = imageRef, hasImage(ref) {
            Image(ref).resizable().scaledToFit().frame(width: 48, height: 48)
        } else {
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

## 4. 開いたときのサンプルデータ

SwiftUI の `App` までは `swift file.swift` では動かないので、**型と関数の確認は下の「通しの確認」で**
行います。View を書くときのサンプルデータです（**base の型と同じ形**）。

```swiftui
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

let initialTypes: [ProductType] = [
    ProductType(typeId: "sticker", name: "ステッカー", idPrefix: "ST", idDigits: 3,
                stockMode: .counted, attrLabel1: "色"),
    ProductType(typeId: "keyholder", name: "キーホルダー", idPrefix: "KH", idDigits: 3,
                stockMode: .unique, attrLabel1: "色"),
    ProductType(typeId: "ticket", name: "入場券", idPrefix: "TB", idDigits: 3,
                stockMode: .none),
]

let initialInventory: [Product] = [
    Product(id: "ST-001", typeId: "sticker", name: "ステッカー まる",
            priceJpy: 300, priceSats: 500, stock: 3, imageRef: "ST-001"),
    Product(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01",
            priceJpy: 800, priceSats: 1200, stock: 1, imageRef: "KH-001"),
    Product(id: "TB-001", typeId: "ticket", name: "入場券",
            priceJpy: 1000, priceSats: nil, stock: nil),
]

let initialCart: [CartLine] = [
    CartLine(product: initialInventory[1], qty: 1),   // 一点物型
    CartLine(product: initialInventory[0], qty: 2),   // 数量管理型
    CartLine(product: initialInventory[2], qty: 1),   // 在庫管理なし型
    CartLine.adhoc(id: "ADHOC-01", name: "委託品A",
                   priceJpy: 1200, priceSats: nil, qty: 1),
]

/// 名前の画像がアプリに入っているか
func hasImage(_ name: String) -> Bool {
    #if os(macOS)
    return NSImage(named: name) != nil
    #else
    return UIImage(named: name) != nil
    #endif
}

@main
struct CartApp: App {
    var body: some Scene {
        WindowGroup { CartView() }
    }
}
```

**初期カート合計の期待値**（下の通しの確認と一致します）:

```
sats払い　2200sats ＋ 2200円
現金　　　3600円
```

- sats 1200×1 ＋ 500×2 = **2200sats**
- 現金分（sats単価なし）＝ 入場券 1000×1 ＋ 委託品A 1200×1 = **2200円**
- 現金合計 ＝ 800×1 ＋ 300×2 ＋ 1000×1 ＋ 1200×1 = **3600円**

---

## 5. 通しの確認

下のコードを、**土台（`base/Types.swift` の型 ＋ `base/3` §1 ＋ `base/5` §1〜§6
＋ §1 の `changeQty`）の下に続けて置いて**、`swift` で動かします。

```swift
// ════════ 通しの確認（カート画面の増減は base/5 に任せる）════════

let types15: [ProductType] = [
    ProductType(typeId: "sticker", name: "ステッカー", idPrefix: "ST", idDigits: 3,
                stockMode: .counted, attrLabel1: "色", attrLabel2: nil, attrLabel3: nil),
    ProductType(typeId: "keyholder", name: "キーホルダー", idPrefix: "KH", idDigits: 3,
                stockMode: .unique, attrLabel1: "色", attrLabel2: nil, attrLabel3: nil),
    ProductType(typeId: "ticket", name: "入場券", idPrefix: "TB", idDigits: 3,
                stockMode: .none, attrLabel1: nil, attrLabel2: nil, attrLabel3: nil),
]
var inventory15: [Product] = [
    Product(id: "ST-001", typeId: "sticker", name: "ステッカー まる", priceJpy: 300, priceSats: 500, stock: 3),
    Product(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01", priceJpy: 800, priceSats: 1200, stock: 1),
    Product(id: "TB-001", typeId: "ticket", name: "入場券", priceJpy: 1000, priceSats: nil, stock: nil),
]
var cart15: [CartLine] = [
    CartLine(product: inventory15[1], qty: 1),      // 一点物型
    CartLine(product: inventory15[0], qty: 2),      // 数量管理型
    CartLine(product: inventory15[2], qty: 1),      // 在庫管理なし型
    CartLine.adhoc(id: "ADHOC-01", name: "委託品A", priceJpy: 1200, priceSats: nil, qty: 1),
]

// ── 画面の ＋／− ボタンが呼ぶ関数（base/5 の increase / decrease に委譲）──
func changeQty8(_ i: Int, by delta: Int,
                cart: inout [CartLine],
                inventory: [Product],
                types: [ProductType]) -> CartEdit {
    delta > 0 ? increase(at: i, cart: &cart, inventory: inventory, types: types)
              : decrease(at: i, cart: &cart, inventory: inventory, types: types)
}

func p8(_ s: String) { print("  " + s) }
func num8(_ v: Int?) -> String { v.map(String.init) ?? "nil" }
func rows8() -> String {
    cart15.map { "\($0.name)×\($0.qty)" }.joined(separator: " / ")
}
func show8(_ r: CartEdit) -> String {
    switch r {
    case .applied(let m):      return "applied(\(m))"
    case .needsConfirm(let d): return "needsConfirm(\(d.message))"
    case .rejected(let m):     return "rejected(\(m))"
    }
}

// ── 画面が持つ唯一の数え上げ（base/3 §1 のもの）──
func totalRows8() -> String {
    let (satsLine, cashLine) = totalLines(cart15)
    return satsLine + " / " + cashLine
}

print("【1】初期状態")
p8(rows8())
p8(totalRows8())

print("【2】＋/− は base/5 に任せる（在庫を見る）")
p8(show8(changeQty8(1, by: +1, cart: &cart15, inventory: inventory15, types: types15)))
p8(rows8())
p8("在庫 ST-001 = " + num8(inventory15[0].stock))

print("【3】在庫を超える＋ は rejected（何も変わらない）")
let before3 = rows8()
p8(show8(changeQty8(1, by: +1, cart: &cart15, inventory: inventory15, types: types15)))
p8("カートが変わらない: " + String(before3 == rows8()))

print("【4】一点物型は数量1固定")
p8(show8(changeQty8(0, by: +1, cart: &cart15, inventory: inventory15, types: types15)))
p8(show8(changeQty8(0, by: -1, cart: &cart15, inventory: inventory15, types: types15)))

print("【5】在庫管理なし型と野良は上限なし（A-1）")
p8(show8(changeQty8(2, by: +1, cart: &cart15, inventory: inventory15, types: types15)))
p8(show8(changeQty8(3, by: +1, cart: &cart15, inventory: inventory15, types: types15)))
p8(rows8())

print("【6】− で0になるときは needsConfirm（まだ消えていない）")
p8(show8(changeQty8(2, by: -1, cart: &cart15, inventory: inventory15, types: types15)))
p8(show8(changeQty8(2, by: -1, cart: &cart15, inventory: inventory15, types: types15)))
p8("ダイアログが出るまでカートは4行: " + String(cart15.count == 4))
p8("0にならない減りではダイアログが出ない: " + show8(changeQty8(1, by: -1, cart: &cart15, inventory: inventory15, types: types15)))

print("【7】確認の結果を反映する")
let d7 = CartDelete(index: 2, name: "入場券", qty: 2)
p8("削除: " + performDelete(d7, cart: &cart15))
p8("キャンセル: " + cancelDelete())
p8(rows8())

print("【8】合計の2行は base/3 §1（画面は計算しない）")
p8(totalRows8())
```

**期待される出力**:
```
【1】初期状態
  キーホルダー 01×1 / ステッカー まる×2 / 入場券×1 / 委託品A×1
  sats払い　2200sats ＋ 2200円 / 現金　　　3600円
【2】＋/− は base/5 に任せる（在庫を見る）
  applied(ステッカー まる ×3)
  キーホルダー 01×1 / ステッカー まる×3 / 入場券×1 / 委託品A×1
  在庫 ST-001 = 3
【3】在庫を超える＋ は rejected（何も変わらない）
  rejected(在庫超過: ステッカー まる（在庫 3）)
  カートが変わらない: true
【4】一点物型は数量1固定
  rejected(キーホルダー 01 は一点物なので数量1固定です)
  rejected(キーホルダー 01 は一点物なので数量1固定です)
【5】在庫管理なし型と野良は上限なし（A-1）
  applied(入場券 ×2)
  applied(委託品A ×2)
  キーホルダー 01×1 / ステッカー まる×3 / 入場券×2 / 委託品A×2
【6】− で0になるときは needsConfirm（まだ消えていない）
  applied(入場券 ×1)
  needsConfirm(入場券 ×1)
  ダイアログが出るまでカートは4行: true
  0にならない減りではダイアログが出ない: applied(ステッカー まる ×2)
【7】確認の結果を反映する
  削除: 削除: 入場券 ×2
  キャンセル: 何もしませんでした
  キーホルダー 01×1 / ステッカー まる×2 / 委託品A×2
【8】合計の2行は base/3 §1（画面は計算しない）
  sats払い　2200sats ＋ 2400円 / 現金　　　3800円
```

---

## できた合図（Xcode で動かしたとき）

- 4行（KH-001×1／ST-001×2／TB-001×1／野良 委託品A×1）が表示される
- `TB-001` と野良の行は sats単価が「**―（現金）**」になっている
- 野良の行に「**野良**」のラベルが付いている
- 合計が上の2行になる
- `ST-001`（在庫3）の `＋` を4回押すと、**3回目で「在庫超過」ダイアログ**が出て止まる
- `KH-001`（一点物型）の `＋` `−` は**「一点物なので数量1固定」**になる
- `TB-001` と野良は `＋` を何回押しても増える
- `−` で0になりそうなときは**削除の確認ダイアログ**が出て、**「キャンセル」なら行が残る**

---

## 考えてみる（答えはない）

1. `.alert` は **削除の確認**と**拒否の理由**の2種類を1つの `CartAlert` にまとめています。
   受け入れテスト C-6 #49・#50 はこの2つを**別々に**区別して見ています。
   もし `CartEdit` に **`case deleted(String)`**（実行済み）を足すなら、何が変わりそうですか。
2. `＋／−` は **`index`** で `base/5` を呼んでいます。
   いま `ForEach(Array(cart.enumerated()))` で index を作っています。
   `id` で引く形に変えると、`needsConfirm` の `CartDelete.index` は
   **削除の確認を出すタイミングの値**を指すので—何が変わりますか。
3. `CartRow` に `imageRef` を引数で渡す方式是、**画面が在庫表を持つ**ことを要求します。
   もし `CartView` が `inventory` を持たない設計（`CartView(cart:)` だけ受け取る）になったら、
   画像はどこから取ることになりますか。

---

## ポイント

- **`Totals` / `totalLines` / `CartEdit` / `increase` / `decrease` は `base/` にある**。作らない
- **＋／− は `cart` を直接触らない**。`base/5` に委譲して `CartEdit` を受け取る
- **`cart` は `inout`**。`needsConfirm` を返す関数は **1行も書いていない**（`base/5` §4）
- **`CartEdit` の3つ**を `.alert` につなぐ。`.applied` は**何もしない**
- 削除の確認は **`CartDelete`**（商品名と数量だけ・A-3）。`performDelete` で初めて消える
- **画像は在庫表から引く**。`CartLine` に `imageName` を持たせない（A-7 と同じ考え方）
- **合計は `base/3` §1**。画面は `totalLines(cart)` を呼ぶだけ
- **sats単価が `nil` の行は「―（現金）」**（A-6-1）。sats払いでも現金で受け取る行がある
- **`−` で0にならない増減ではダイアログが出ない**（C-6 #50）

---

## 関連

- `09_カートを編集する.md` … ＋／−／削除のルールそのもの（`base/5` の由来）
- `07_カートの種類ごとの追加ルール.md` … `＋` ではなく「商品パネルから追加」の判定
- `28` / `29` / `30` … 一点物・在庫不足・SOLD OUT の判定（`base/5` §1 の分岐）
- `58_総合問題2_レジ画面を1本にする.md` … このカート画面を右ペインに置いて1枚にまとめる
- `16_現金の会計画面.md` … カートのとなりの現金会計画面
- `base/6_会計の状態機械.md` … 会計に進んだあとの遷移（A-19-9 #9「遷移はUIで書かない」）