# Svelteで理解するSwift

Svelteが分かる人向けに、Swift / SwiftUI / Xcode を**対応づけて**説明する資料。
「あれはSvelteでいう何？」と思ったらここを見る。

---

## 一番大事な違い
- Swiftは**全部 `.swift` ファイル**。`.svelte` / `.ts` のような拡張子の分け方は無い
- 役割は**中身**で決まる
  - `struct ○○: View` に従ったもの＝**UI部品**
  - それ以外の `func` / `struct` / `class` / `enum`＝**処理**
- **UIもただのSwiftコード**。境界は「`View` かどうか」だけ

> SwiftUIの View は、Svelteでいう `.svelte` ファイル1個ぶんに近い。
> 上のほうの `let` / `@State` が `<script>`、`var body` の中がマークアップ。

---

## 対応表（早見）
| Svelte | Swift / SwiftUI |
| --- | --- |
| `.svelte` ファイル | `struct ○○: View { var body: some View }` |
| `.ts` ファイル | 普通の `.swift`（`func` / `class` / `struct`） |
| コンポーネントを入れ子 | Viewの中にViewを入れる |
| `export let prop` | Viewのプロパティ `let prop: String`（外から渡す） |
| `bind:value`（双方向） | `@Binding var value` |
| `let count = 0`＋`$:`（リアクティブ） | `@State var count = 0` |
| 派生値 `$: x = a*2` | 計算プロパティ `var x: Int { a*2 }` |
| store（`writable`） | `@Observable` クラス（古: `ObservableObject`＋`@Published`） |
| グローバルなstore | 共有した `@Observable` を `@Environment` で配る |
| `on:click={fn}` | `Button("...") { fn() }` / `.onTapGesture { }` |
| `{#if x}...{/if}` | `if x { ... }`（bodyの中） |
| `{#each items as item}` | `ForEach(items, id: \.self) { item in ... }` |
| `<slot/>` | `@ViewBuilder` のクロージャプロパティ |
| `onMount(() => {})` | `.onAppear { }` |
| `onDestroy` | `.onDisappear { }` |
| `import Foo from './Foo.svelte'` | **不要**（同じアプリ内の `.swift` は自動で見える） |
| `import { x } from 'pkg'` | `import Framework`（SwiftUIなど） |
| TSの `interface` | `struct`（データの形） |
| TSの `type A = B \| C` | `enum`（選択肢のどれか1つ） |
| `async/await` | `async/await`（ほぼ同じ） |
| `?.` / `??` | `?.` は無い／`??`（nilのときの代わり）はある |
| `null` / `undefined` | `nil`（1種類だけ） |

---

## 例① UI部品（.svelte 相当）
**Svelte**
```svelte
<script lang="ts">
  export let label: string;
  let count = 0;
</script>

<button on:click={() => count++}>{label}: {count}</button>
```

**SwiftUI**
```swift
import SwiftUI

struct CounterButton: View {
    let label: String                  // export let 相当（外から渡す）
    @State var count = 0               // 画面が持つ状態

    var body: some View {              // ← ここがマークアップ
        Button("\(label): \(count)") { // ← on:click 相当
            count += 1
        }
    }
}
```

## 例② 処理（.ts 相当）
**Svelte/TS**
```ts
export function total(items: { price: number }[]): number {
  return items.reduce((s, i) => s + i.price, 0);
}
```

**Swift**
```swift
func total(_ items: [Product]) -> Int {
    var sum = 0
    for p in items { sum += p.priceJpy }
    return sum
}
```

## 例③ 組み合わせ（でろでろつながる）
```swift
struct RegisterView: View {
    var body: some View {
        VStack {
            CounterButton(label: "個数")
            Text("合計 ¥\(total(products))")
        }
    }
}
```

## 例④ 状態と派生値
**Svelte**
```svelte
<script>
  let qty = 1;
  let price = 300;
  $: subtotal = qty * price;
</script>
```

**SwiftUI**
```swift
struct Line: View {
    @State var qty = 1
    let price = 300
    var subtotal: Int { qty * price }   // 派生値は計算プロパティ
    var body: some View { Text("¥\(subtotal)") }
}
```

## 例⑤ 配列を並べる・条件分岐
```swift
// {#each cart as line} 相当
ForEach(cart) { line in
    Text(line.name)
}

// {#if cart.isEmpty} 相当
if cart.isEmpty {
    Text("カートは空です")
} else {
    Text("合計 ¥\(total(cart))")
}
```

---

## Playgrounds と Xcode
- **Playgrounds**（今やってるやつ）… 1ファイルに全部書いて練習。関数もUIも試せる
- **Xcode**（Macが来たら）… 同じことを**複数の `.swift` ファイル**に分けるプロジェクト
  - 例: `RegisterView.swift`（UI）／`Cart.swift`（処理）／`Product.swift`（データの形）
  - 分け方は自由。**Svelteみたいに「これがUIファイル」と決まっているわけではない**

## ハマりやすい違い（JS脳の注意）
- View は **`class` ではなく `struct`**（値のコピーで動く。`this` が無い）
- Svelteみたいな**自動リアクティブは無い**。状態は `@State` など**印を付けたものだけ**が更新の対象
- **自分のファイルは import 不要**（同じアプリ内は名前だけで見える）。フレームワークだけ `import SwiftUI`
- 小文字スタートの名前（`let name`）は普通、画面に自動では出ない（`Text(name)` と書く）
- 文字に値を埋め込むのは `"\(count)"`（Svelteの `{count}` 相当）
