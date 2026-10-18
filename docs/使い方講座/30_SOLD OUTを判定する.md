# 追加レッスン: SOLD OUT を判定する

元: `../siyou.md` A-1、B-1、受け入れテスト C-6 #33
`02_練習メニュー.md` の「30. SOLD OUT を判定する」。

**SOLD OUT のルール**はこうです。

> 在庫管理ありの種類で **在庫0** の商品は、SOLD OUT。
> **在庫管理なし型は SOLD OUT にならない**（A-1、B-1）。

判定のコードは書きません。**`base/5_カート編集.md` の `isSoldOut` が持ちます**。
このレッスンは **「押せるか」と「追加できるか」をどう分けるか** を確かめます。

---

## まず土台をペーストする

1. `base/Types.swift` の**型だけ**
2. `base/5_カート編集.md` の §1

---

## `isSoldOut` の3行

```swift 断片
func isSoldOut(_ p: Product, in inventory: [Product], types: [ProductType]) -> Bool {
    guard let i = inventory.firstIndex(where: { $0.id == p.id }) else { return false }
    guard inventory[i].managesStock(in: types) else { return false }   // 在庫管理なし型は false
    return (inventory[i].stock ?? 0) == 0
}
```

読み順是关键です。

| 行 | 意味 |
| --- | --- |
| `guard let i = ...` | 在庫表に居なければ `false`（SOLD OUT とは无关） |
| `guard managesStock(in:)` | **在庫管理なし型を先に除外する**（B-1） |
| `stock ?? 0) == 0` | 在庫0か |

**2行目が無いと**、在庫管理なし型（`stock` が `nil`）が
`nil ?? 0 == 0` で **SOLD OUT 扱い**になります。
B-1 は「在庫管理なし型：在庫を表示しない（SOLD OUT にならない）」と明記しているので、
これはそのまま **C-6 #33 の違反** です。

---

## わざと間違う: `isSoldOut` と `addCheck` を別々に書く

「表示は `isSoldOut`」「追加は `addCheck`」と分けて書くと、
**両方が似ていて、片方だけ直される**事故が起きます。

```swift NG
// わざと間違う版：パネル側だけ別の判定を使う
func isSoldOutPanel(_ p: Product, inventory: [Product]) -> Bool {
    return (p.stock ?? 0) == 0        // ★ 在庫管理なし型も SOLD OUT になる
}
```

**何が壊れるか**

| 商品 | `isSoldOut`（正しい） | `isSoldOutPanel`（間違い） |
| --- | --- | --- |
| ST-001 ステッカー（在庫3） | `false` | `false` |
| ST-002 ステッカー（**在庫0**） | `true` | `true` |
| TB-001 入場券（**在庫管理なし**） | `false` | **`true`** ← B-1 に反する |

**同じ「在庫0か」を2か所で判定している**のが原因です。
`stock` を読むのは `addCheck` と `isSoldOut` の **2か所だけ**にしましょう。

> **`isSoldOut` は `addCheck` の `soldOut` の別名ではありません**。
> `addCheck` は「追加できるか」（3 penalized理由）、`isSoldOut` は「表示だけ」（真偽値）。
> 役割が違うので2つの関数に分けています。

---

## わざと間違う: NET表示だけ見て、追加を許す

逆に、**パネルは「追加済み」なのに、SOLD OUT の商品には「追加済み ALSOidasetasaily 显示」**ことがあります。

一点物型は「すでに入っているなら `duplicateUnique`」ですが、
その商品の在庫が0（A-7 で調整した結果）なら `.soldOut` のほうが先に来ます。
`addCheck` の並び順は、`soldOut` → `duplicateUnique` → `overStock` です。

**どちらの文言を出すかは `addCheckMessage` の1か所**で決まります。
UI 側で「在庫0で既に入っている」のような文言を書かないでください。

---

## 商品パネルの表示は3種類

A-1 と B-1 に書いている表示は **3 種類** です。
`PanelState` は enum で持ちます。

```swift 断片
enum PanelState {
    case normal                                  // 普通に追加できる
    case soldOut                                 // 在庫0
    case alreadyInCart                           // すでに入っている（一点物型）
    case overStock(current: Int, need: Int)      // 在庫を超える

    /// ボタンを押せるか（SOLD OUT と追加済みは押せない）
    var isEnabled: Bool {
        self == .normal
    }

    /// ボタンの下に書く1行
    var caption: String {
        switch self {
        case .normal:        return "タップで追加"
        case .soldOut:       return "SOLD OUT"
        case .alreadyInCart: return "カートに追加済み"
        case .overStock(let c, let n): return "在庫 \(c)／追加すると \(n) 個"
        }
    }
}
```

**`addCheck` の `AddCheck` と `PanelState` は 1 対 1** です。

| `AddCheck` | `PanelState` | 意味 |
| --- | --- | --- |
| `.ok` | `.normal` | 追加できる |
| `.soldOut` | `.soldOut` | 在庫0（A-1） |
| `.duplicateUnique` | `.alreadyInCart` | 一点物型ですでに入っている（C-6 #6） |
| `.overStock(c, n)` | `.overStock(c, n)` | 在庫不足（C-6 #7） |

変換は **1か所の関数**にしてください（`30-4`）。

```swift 断片
func panelState(for p: Product, qty: Int, cart: [CartLine],
                inventory: [Product], types: [ProductType]) -> PanelState {
    switch addCheck(product: p, qty: qty, cart: cart, inventory: inventory, types: types) {
    case .ok:                return .normal
    case .soldOut:           return .soldOut
    case .duplicateUnique:   return .alreadyInCart
    case .overStock(let c, let n): return .overStock(current: c, need: n)
    }
}
```

---

## 確かめる

`07_カートの種類ごとの追加ルール.md` の「通しの確認」をそのまま動かしてください。
【4】がこれです。

```
【4】在庫0は SOLD OUT（追加経路によらず不可・A-1 / C-6 #33）
  ST-002: rejected(SOLD OUT: ステッカー さんかく)
  isSoldOut(ST-002): true
  isSoldOut(ST-001): false
  isSoldOut(入場券): false　← 在庫管理なし型は SOLD OUT にならない（A-1）
```

**入場券が `false`** になっているのが要点です。
`isSoldOut` の **2行目**（`managesStock`）が効いています。

---

## 考えてみる（答えはない）

1. B-1 は、Web 側にも「残り N 個」「1点もの」「SOLD OUT」の3種類の表示を書いています。
   **同じ `isSoldOut` が快照（A-14 の `SnapshotProduct.stock`）から判定できる**でしょうか。
   `SnapshotProduct` には `ProductType.stockMode` がないはずです（送信するのは公開対象の種類だけ）。
   不足している情報をスナップショットに足すか、**表示側で種類と突き合わせる**か、どちらが正しいでしょうか。
2. C-6 #33 は「在庫0は SOLD OUT 表示、**カートにある一点物はエラー**」です。
   `isSoldOut` は「追加できるか」を見ず「在庫が0か」だけを見ます。
   **カートにすでに入っている一点物型の商品を、パネルはどう表示しますか**。
   `panelState` なら答えが出ますが、`isSoldOut` だけなら出せません。どちらを使いますか。
3. 営業中に別の端末が在庫を動かしたら、パネルの SOLD OUT 表示は
   **いつ**書き換わりますか。商品パネルを開いた瞬間だけだと、他で動かした在庫に追いつきません。
   A-14 のスナップショット送信（Cloudflare KV、`60秒以上`の遅延）と、
   B の「最終更新時刻」の表示とどう整合させますか。

---

## ポイント

- SOLD OUT は **在庫管理ありの種類で在庫0**。**在庫管理なし型はならない**（A-1、B-1）
- `isSoldOut` の **2行目**（`managesStock`）を落とすと、在庫管理なし型が SOLD OUT になる
- 在庫を読むのは **`addCheck` と `isSoldOut` の2か所だけ**
- **「押せるか」は `panelState(...).isEnabled`**。UI 側で在庫を読まない
- `AddCheck` と `PanelState` は **1 対 1**。変換は1か所の関数
- 1文の文言は **`addCheckMessage` / `PanelState.caption`**。UI 側で書かない
- 販売取消と**記録に残らない中断**は別の状態。混同しない（A-1、A-19-3）