# 他言語から見たSwift ― Svelte / JS / TS / C#

> **前:** [画面と保存](04_画面と保存.md) ｜ **入口:** [はじめに](00_はじめに.md) ｜ **次:** [Macへ](06_Macへ_Xcode.md)

すでにSvelteやJS / TS / C#を知っている人向けの比較資料です。
第1部はSvelteとSwiftUIの対応、第2部はJS / TS / C#とSwiftの文法の違いをまとめています。
Swiftが初めての場合は、先に `01_Swiftの基礎.md` を読むと分かりやすいです。

## 第1部: Svelteから見るSwift

### 一番大事な違い
- Swiftは**全部 `.swift` ファイル**。`.svelte` / `.ts` のような拡張子の分け方は無い
- 役割は**中身**で決まる
  - `struct ○○: View` に従ったもの＝**UI部品**
  - それ以外の `func` / `struct` / `class` / `enum`＝**処理**
- **UIもただのSwiftコード**。境界は「`View` かどうか」だけ

> SwiftUIの View は、Svelteでいう `.svelte` ファイル1個ぶんに近い。
> 上のほうの `let` / `@State` が `<script>`、`var body` の中がマークアップ。

---

### 対応表（早見）
| Svelte | Swift / SwiftUI |
| --- | --- |
| `.svelte` ファイル | `struct ○○: View { var body: some View }` |
| `.ts` ファイル | 普通の `.swift`（`func` / `class` / `struct`） |
| コンポーネントを入れ子 | Viewの中にViewを入れる |
| `let { prop } = $props()` | Viewのプロパティ `let prop: String`（外から渡す） |
| `bind:value`（双方向） | `@Binding var value` |
| `let count = $state(0)` | `@State var count = 0` |
| 派生値 `let x = $derived(a*2)` | 計算プロパティ `var x: Int { a*2 }` |
| `$effect(() => {})` | `.onChange { }` / `.task { }` / `.onAppear { }` |
| store（`writable`） | `@Observable` クラス（古: `ObservableObject`＋`@Published`） |
| グローバルなstore | 共有した `@Observable` を `@Environment` で配る |
| `onclick={fn}` | `Button("...") { fn() }` / `.onTapGesture { }` |
| `{#if x}...{/if}` | `if x { ... }`（bodyの中） |
| `{#each items as item}` | `ForEach(items, id: \.id) { item in ... }`（`Identifiable` なら `ForEach(items)`） |
| `<slot/>` | `@ViewBuilder` のクロージャプロパティ |
| `onMount(() => {})` | `.onAppear { }` |
| `onDestroy` | `.onDisappear { }` |
| `import Foo from './Foo.svelte'` | **不要**（同じアプリ内の `.swift` は自動で見える） |
| `import { x } from 'pkg'` | `import Framework`（SwiftUIなど） |
| TSの `interface` | `struct`（データの形） |
| TSの `type A = B \| C` | `enum`（選択肢のどれか1つ） |
| `async/await` | `async/await`（ほぼ同じ） |
| `?.` / `??` | `?.`（Optional chaining）も `??`（nilのときの代わり）もある |
| `null` / `undefined` | `nil`（1種類だけ） |

> `id:` は、Svelte の `{#each items as item (item)}` の `(item)` と同じ役割（要素を識別するキー）。`CartLine` のように `id` を持つ型なら `id: \.id`、`String` の配列なら `id: \.self` を使う。他言語との対応は `05_他言語から見たSwift.md` §21。

---

### 例① UI部品（.svelte 相当）
**Svelte**
```svelte
<script lang="ts">
  let { label } = $props();
  let count = $state(0);
</script>

<button onclick={() => count++}>{label}: {count}</button>
```

**SwiftUI**
```swift
import SwiftUI

struct CounterButton: View {
    let label: String                  // $props() 相当（外から渡す）
    @State var count = 0               // $state 相当（画面が持つ状態）

    var body: some View {              // ← ここがマークアップ
        Button("\(label): \(count)") { // ← onclick 相当
            count += 1
        }
    }
}
```

### 例② 処理（.ts 相当）
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
- `Product` の正は `base/Types.swift`。ここでは `priceJpy` を持つ型として読む
- 実際の合計は `base/3_標準ロジック.md` §1 の `totals()` を使う（自分で作り直さない）

### 例③ 組み合わせ（部品をつなぐ）
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

### 例④ 状態と派生値
**Svelte**
```svelte
<script>
  let qty = $state(1);
  let price = 300;
  let subtotal = $derived(qty * price);
</script>
```

**SwiftUI**
```swift
struct Line: View {
    @State var qty = 1                        // $state 相当
    let price = 300
    var subtotal: Int { qty * price }   // $derived 相当（計算プロパティ）
    var body: some View { Text("¥\(subtotal)") }
}
```

### 例⑤ 配列を並べる・条件分岐
```swift
// {#each cart as line} 相当
ForEach(cart, id: \.id) { line in
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

### Playgrounds と Xcode
- **Playgrounds**（今やってるやつ）… 1ファイルに全部書いて練習。関数もUIも試せる
- **Xcode**（Macが来たら）… 同じことを**複数の `.swift` ファイル**に分けるプロジェクト
  - 例: `RegisterView.swift`（UI）／`Cart.swift`（処理）／`Product.swift`（データの形）
  - 分け方は自由。**Svelteみたいに「これがUIファイル」と決まっているわけではない**

### ハマりやすい違い（JS脳の注意）
- View は **`class` ではなく `struct`**（値のコピーで動く。`this` が無い）
- Svelteみたいな**自動リアクティブは無い**。状態は `@State` など**印を付けたものだけ**が更新の対象
- **自分のファイルは import 不要**（同じアプリ内は名前だけで見える）。フレームワークだけ `import SwiftUI`
- 小文字スタートの名前（`let name`）は普通、画面に自動では出ない（`Text(name)` と書く）
- 文字に値を埋め込むのは `"\(count)"`（Svelteの `{count}` 相当）

## 第2部: JS / TS / C#から見るSwift

### 1. 演算子の前後の空白
```swift
let c1 = a + b   // OK
let c2 = a+b     // OK
let c3 = a +b    // エラー
```
両側に空白、または両側とも空白なし。C# / JS にはない規則。

### 2. 条件式に括弧は不要。`{ }` は必須
```swift
if x > 0 { print("正") }   // OK
// if (x > 0) print("正")  // エラー（{ } を省略できない）
```
C# は括弧が必須で `{ }` は省略可。Swiftは逆。

#### 条件は `,` で並べられる
```swift
if x > 0, y > 0 { print("両方正") }
if x > 0 && y > 0 { print("両方正") }   // 同じ意味
```
- `,` で区切られた各要素が条件1つ。すべて真のときだけ `{ }` が実行される
- 左から順に評価し、偽が出た時点で打ち切る（`&&` と同じ短絡評価）
- `if` / `guard` / `while` で共通の文法
- OR は `,` で書けない。`||` を使う
- `,` と `&&` / `||` は併用できる。1つの要素の中では `&&` / `||` が先に評価される
```swift
if a > 0 || b > 0, c > 0 { }   // (a > 0 || b > 0) かつ c > 0
```
- `,` が `&&` と違う点は、要素に `let`（オプショナルバインディング）を書けること。§6 を参照

### 3. 条件は Bool のみ（truthy / falsy がない）
```swift
let n = 1
// if n { }        // エラー
if n != 0 { }      // OK
```
C# と同じ。JS / TS とは違う。

### 4. 型の暗黙変換がない
```swift
let a: Int = 3
let b: Double = 1.5
// let c = a + b          // エラー
let c = Double(a) + b     // OK
```
C# は `int + double` が通る。Swiftは通らない。

### 5. 型は名前の後ろに書く。引数名は呼び出し時に書く
```swift
let price: Int = 300

func add(price: Int, tax: Int) -> Int { price + tax }
add(price: 300, tax: 30)       // 引数名を書く（C# の名前付き引数は任意。Swiftは基本必須）

func add2(_ price: Int, _ tax: Int) -> Int { price + tax }
add2(300, 30)                  // _ を付けた引数は名前を書かない
```
- 1つの式だけの関数は `return` を省略できる
- C# の `var` は型推論のみ。Swiftの `let` / `var` は「変更できるか」を表す（型推論は両方で効く）

### 6. null がない。代わりにオプショナル
```swift
var s: Int? = nil     // Int? は Int とは別の型
// let t: Int = s     // エラー
if let v = s { print(v) }   // 確認してから取り出す
let w = s ?? 0              // nil のときの代わりの値（C# の ?? と同じ）
let x = s!                  // 強制取り出し。nil だと実行時にクラッシュ
```
- C# の `int?` に近いが、Swiftは参照型（class）も含めて、nil にしたい型にはすべて `?` が必要
- C# の `!` はコンパイラ警告を消すだけ。Swiftの `!` は nil のときクラッシュする

#### `if let` と `,`（§2 の条件リスト）
```swift
if let i = idx, i > 0 { print(i) }                  // 取り出して、さらに条件
if let i = idx, let j = jdx, i < j { print(i, j) }  // 取り出しを複数
```
- `let` は条件リストの1要素として書ける。取り出せれば真、nil なら偽
- 前の要素で取り出した変数を、後の要素で使える（上の例では `i`）
- 1つでも偽（または nil）なら `{ }` は実行されない
- `if let` で取り出した変数は `{ }` の中だけで使える。外でも使う場合は `guard let`（§22）

### 7. struct は値型。配列・文字列も値型
```swift
struct P { var n: Int }
var a = P(n: 1)
var b = a        // コピー
b.n = 2
print(a.n)       // 1（a は変わらない）

var xs = [1, 2, 3]
var ys = xs      // 値としてコピーされる
ys.append(4)
print(xs.count)  // 3
```
- struct の値型は C# と同じ
- C# の配列 / `List` は参照型で共有される。Swiftの配列は値型（必要に応じてコピーされる）
- JS のオブジェクト / 配列は参照が共有される

### 8. `let` は中身も変えられない（struct の場合）
```swift
struct P { var n: Int }
let p = P(n: 1)
// p.n = 5        // エラー
```
JS の `const` は中身を変えられる。C# の `readonly` に近いが、Swiftはその変数全体が対象。

### 9. 関数の引数は変更できない（`inout` で参照渡し可能）
```swift
// デフォルトでは引数は let 扱いで変更できない
func f(_ x: Int) {
    // x += 1     // エラー
}

// inout を付けると、呼び出し元の変数を直接書き換えられる（C# の ref と同じ）
func increment(_ x: inout Int) {
    x += 1
}

var num = 10
increment(&num)  // 呼び出し側も & を付けて「書き換えに同意」する必要がある
print(num)       // 11
```
- C# の値型引数はデフォルトでコピーだが、変更したい場合は `ref` を使う。Swift もこれに近く、配列（値型）を関数内で `append` などで書き換えたい場合に `inout` が必須になる。
- JS / TS の配列やオブジェクトは参照型なので、関数内での変更が自動的に呼び出し元に反映されるが、Swift の配列は値型のため、明示的に `inout` を使わないと反映されない。

### 10. enum は「関連値」を持てる。switch は「パターンマッチング」

#### enum は関連値（Associated Values）を持てる
C# や TS の enum は単なる数値の別名だが、Swift の enum はケースごとに「異なる型や複数の値」を保持できる（TS の判別共用体 / Union 型に近い）。

```swift
struct Product: Equatable { let name: String }

// カートの1行（形は base/Types.swift の CartLine と同じ）
struct CartLine {
    let id: String
    let typeId: String?
    let name: String
    let unitPriceJpy: Int
    let unitPriceSats: Int?
    var qty: Int
    let isAdhoc: Bool
}

// 追加結果（成功時は商品と数量、失敗時はエラー理由を持つ）
enum AddResult {
    case added(Product, qty: Int)  // 1つ目は型のみ、2つ目は qty というラベル付き
    case failed(String)
}

func message(_ r: AddResult) -> String {
    switch r {
    case .added(let p, let qty):     // 関連値を p と qty として取り出す（値の束縛）
        return "追加: \(p.name) × \(qty)"
    case .failed(let reason):
        return "エラー: \(reason)"
    }
}
```
- `case added(Product, qty: Int)` のように、ケースごとに保持するデータ型を定義できる。
- `switch` 文の中で `let p, let qty` のように書くことで、格納されている値を変数として取り出せる（これを「値の束縛 / バインディング」と呼ぶ）。
- ラベル（`qty:`）は任意だが、意味を明確にしたい場合に付ける。`Product` のように型名だけで意味が明らかな場合は省略されることが多い。

#### Swift の switch は「パターンマッチング」
C# や JS の `switch` は「値の一致を判定するだけ」だが、**Swift の `switch` は「データ構造を分解するパターンマッチング」** である。これが最大の違い。

```swift
// ① 値の一致を判定（where 句で中身を見る）
case .added(let p, let qty) where p.name == "りんご" && qty == 3:

// ② 型の一致だけを判定（値は無視）
case .added(_, _):

// ③ 条件付きで判定（where 句）
case .added(let p, let qty) where qty > 0:

// ④ 値を取り出す（バインディング）← これが最も一般的
case .added(let p, let qty):
```

> `case .added(Product(name: "りんご"), qty: 3):` のように書くこともできますが、`Product` が `Equatable` のときだけです。中身を条件で見るなら `where` のほうが分かりやすいです。

これらはすべて「パターン」としての `case` の使い方であり、**`let` の有無で「値の一致」と「値の取り出し」を区別している**。

##### なぜ `let` が必要なのか？
もし `let` なしで `case .added(p, qty):` と書くと、それは「外で宣言した変数 `p` と `qty` の値と一致するか」を判定する意味になる。

```swift
let p = Product(name: "りんご")  // 外で宣言
let qty = 3                      // 外で宣言

switch r {
case .added(p, qty):             // r.added の中身が、外の変数 p と qty と「一致するか」を判定
    print("一致した")
}
```

つまり、**「外で宣言した変数に代入する」方式は、Swift の「パターンマッチングで値を取り出す」機能とは互換性がない**ため、`case` の中で `let` を使って「この case ブロック内だけで使える新しい変数を宣言する」方式になっている。

##### `.` の正体：型名のショートカット
`case .added(let p, let qty):` の `.` は「型名（`AddResult`）の省略」。

```swift
// ① 型名をちゃんと書いた場合
case AddResult.added(let p, let qty):

// ② 型名を省略して . だけ書いた場合（一般的）
case .added(let p, let qty):
```

この2つは完全に同じ意味。`.` は「型名は省略したけど、列挙型のケースを参照しています」という目印。

##### パターンマッチングは switch 以外にも使える
この「パターンマッチング」機能は `switch` 文だけでなく、`if` 文や `guard` 文でも使える。

```swift
// if case（switch の1ケースだけ使う場合）
if case .added(let p, let qty) = r {
    print("追加: \(p.name) × \(qty)")
}

// guard case（早期リターンと組み合わせる場合）
guard case .added(let p, let qty) = r else {
    return
}
```

つまり、**「パターンマッチング」は Swift の言語機能として一般的に使えるものであり、`switch` はその代表的な使い方の1つ**。

#### switch の基本ルール
```swift
enum Color { case red, blue }
let c = Color.red
switch c {
case .red:  print("赤")    // 下の case には流れ落ちない
case .blue: print("青")
}
```
- 全ケースを書くか `default:` を付ける。C# の switch 文は網羅を要求しない
- C# と同じく流れ落ちない。ただし `break` は不要（C# は必要）

#### switchで複数のケースに同じ処理を書く

##### `,` で並べる
```swift
enum Color { case red, blue, green, yellow }
let c = Color.red

switch c {
case .red, .yellow:      // red または yellow
    print("暖色")
case .blue, .green:      // blue または green
    print("寒色")
}
```

##### 残りをまとめて `default`
```swift
switch c {
case .red:
    print("赤")
default:                 // red 以外すべて
    print("赤以外")
}
```

##### Int の範囲も書ける
```swift
let n = 5

switch n {
case 0:
    print("ゼロ")
case 1...9:              // 1 から 9
    print("1桁")
default:
    print("2桁以上")
}
```
- C# の `case A: case B:` と並べる書き方は、Swiftでは `case .a, .b:` と1行にする
- 1つの `case` には、1つ以上の文が必要

### 11. `++` / `--` がない
```swift
var i = 0
i += 1       // OK
// i++       // エラー
```
C# / JS にはある。

### 12. 文字列は Int の添字で取り出せない
```swift
let s = "abc"
// s[0]                          // エラー（C# の s[0] は通る）
let first = s.first               // Optional("a")
let second = s[s.index(s.startIndex, offsetBy: 1)]   // "b"
```

### 13. 範囲外アクセス・オーバーフローはクラッシュする
```swift
let arr = [1, 2, 3]
// arr[5]    // 実行時にクラッシュ
```
- C# は `IndexOutOfRangeException` で、`try/catch` で受けられる。Swiftの配列の範囲外アクセスによるクラッシュは `do/catch` で受けられない
- `Int` の上限超えも通常の算術演算ではクラッシュする。C# は通常の設定では整数演算が折り返す
- JS は配列の範囲外アクセスで `undefined` になる
- クラッシュする書き方の一覧と回避は `02_Optionalと安全.md`

### 14. 文字列補間は `\( )`
```swift
let name = "A"
print("こんにちは \(name)")     // JS の `${name}` / C# の $"{name}" に相当
```

### 15. 範囲
```swift
for i in 0..<3 { print(i) }    // 0, 1, 2
for i in 0...3 { print(i) }    // 0, 1, 2, 3
```
`for (int i = 0; i < 3; i++)` 形式の `for` はない。

### 16. 命名の慣習
- 型（struct / enum / class）は `UpperCamelCase`: `Product`
- 変数・関数・プロパティは `lowerCamelCase`: `priceJpy`
- C# はメソッドとプロパティが `UpperCamelCase`。Swiftは `lowerCamelCase`

### 17. 行末の `;` は不要
改行が文の区切り。1行に複数の文を書くときだけ `;` を使う。

### 18. エラー処理は `throws` / `try` / `try?` / `try!`
```swift
enum MyError: Error { case bad }

func g(_ x: Int) throws -> Int {
    if x < 0 { throw MyError.bad }
    return x
}
```
- C# / JS は例外を `throw` するだけで、呼び出し側に `try` を書く義務はない。Swiftは `throws` 付きの関数を呼ぶ際、必ず `try`（または `try?` / `try!`）を明示する必要がある。

#### 通常の `try`（`do-catch` と組み合わせる）
```swift
do {
    let r = try g(1)       // throws の関数を呼ぶときは try が必須
    print(r)
} catch {
    print("失敗: \(error)") // MyError.bad などがここに入る
}
```

#### `try?`（エラー時に `nil` を返す）
```swift
let r1 = try? g(1)   // Int? 型になる。成功時は 1、失敗時は nil
let r2 = try? g(-1)  // nil になる（エラー内容は破棄される）
```
- C# / JS にはない構文。「成功した値」か「失敗して nil」の2択で扱いたい場合に便利。エラーの詳細が不要なときに `do-catch` を省略できる。
- 戻り値の型は自動的に Optional（`Int?` など）になる。

#### `try!`（失敗時に強制クラッシュ）
```swift
let r3 = try! g(1)   // Int 型になる。成功時は 1
// let r4 = try! g(-1) // 実行時にクラッシュする
```
- 「この引数なら絶対にエラーにならない」と確信できる場合のみ使用する。C# で例外が来ないとわかっている場合に `catch` を書かないのと似ているが、Swiftでは万が一エラーになるとアプリが落ちるため注意が必要。
- `try!` のようなクラッシュする書き方の一覧は `02_Optionalと安全.md`

### 19. インスタンス生成に `new` は不要
```swift
struct P { var n: Int }
let a = P(n: 1)    // C# の new P(...) に相当
```

### 20. クロージャの `$0` は JavaScript の `a => ...` の `a` に相当

クロージャは、関数に渡す処理を `{ }` で書いたもの。`map`・`filter`・`reduce` などで「渡された値をどう処理するか」を指定するときによく使う。

#### JavaScript / TypeScript と Swift の対応

**JavaScript / TypeScript**
```javascript
const nums = [1, 2, 3, 4];

nums.map(a => a * 2);               // [2, 4, 6, 8]
nums.filter(a => a % 2 === 0);      // [2, 4]
nums.reduce((s, a) => s + a, 0);    // 10
[1, 2, 3, 4].sort((a, b) => b - a); // 降順
```

**Swift**
```swift
let nums = [1, 2, 3, 4]

nums.map { $0 * 2 }                 // [2, 4, 6, 8]
nums.filter { $0 % 2 == 0 }         // [2, 4]
nums.reduce(0) { $0 + $1 }          // 10
nums.sorted { $0 > $1 }             // [4, 3, 2, 1]
```

- JSの `a => a * 2` の `a` を、Swiftでは引数名を省略して `$0` と書ける（`{ a in a * 2 }` と名前を付けてもよい）
- `$1` は2番目の引数：`reduce` では現在の要素、`sorted` では比較相手
- 同じクロージャの中で `$0` と `a in` を混ぜない
- 短い処理は `$0`、長い・意味をはっきりさせたい処理は名前を付ける

> `$0`・`$1`・`$2` の詳しい説明、`reduce`/`sorted` の動き、文字列の例、使い分けは
> `01_Swiftの基礎.md` の「`$` って？」にまとめてある。

### 21. キーパス (`\.`) と `\.self`

SwiftUI の `ForEach` などで見かける `\.` は「キーパス（Key Path）」と呼ばれる機能です。プロパティへの参照を型安全に渡す仕組みです。

#### `\.self` の意味
`\.self` は「**その要素そのもの**」を指します。

#### 他言語・フレームワークとの対応
| 言語・フレームワーク | 「要素そのもの」 | 特定のプロパティ |
| :--- | :--- | :--- |
| **SwiftUI** | `id: \.self` | `id: \.id` |
| **Svelte** | `{#each items as item (item)}` | `{#each items as item (item.id)}` |
| **React** | `key={item}` | `key={item.id}` |

配列の要素が「追加・削除・並び替え」されたとき、フレームワークが「**どの要素が変わったか**」を特定して、画面の更新を最小限にするために使う。

- `String` / `Int` など基本の型は値そのものが一意なので `\.self`（要素そのもの）を使う
- Svelte の `(item)` の詳しい話は `05_他言語から見たSwift.md`
- React の `key={item}` は SwiftUI の `id: \.self` と同じ意味

### 22. `guard`（早期脱出）

#### 基本
```swift
guard 条件 else {
    // 条件が false のときだけ実行される
    return   // 必ずスコープを抜ける
}
// 条件が true のときだけここに来る
```
- `if` は「条件が真のとき `{ }` を実行」。`guard` は「条件が偽のとき `{ }` を実行して抜ける」
- 条件の書き方は `if` と同じ（§2 の `,` 条件リスト、§6 の `let` がそのまま使える）
- `else` の `{ }` は必ずスコープを抜ける。抜けないとコンパイルエラー
- 使える文：`return` / `throw` / `fatalError()` など。`continue` / `break` はループ内のみ
- JS / C# の `if (!cond) return;` による早期リターンに相当

#### `if let` との違い：変数の有効範囲
```swift
// if let: { } の中だけ
if let v = s {
    print(v)       // OK
}
// print(v)        // エラー

// guard let: guard 以降のスコープ全体
guard let v = s else { return }
print(v)           // OK
```
- `if let` はネストが深くなりやすい
- `guard let` は取り出した変数を後続の処理全体で使えるため、ネストが浅くなる
- `if let` / `guard let` / `if var` / `while let` の比較は `02_Optionalと安全.md` §8

#### 例：複数条件
```swift
for id in targets {
    guard id > 0,
          let i = inventory.firstIndex(where: { $0.id == id }),
          let current = inventory[i].stock else {
        continue
    }
    print("\(id): 在庫 \(current)")
}
```
- `guard` から `else` の前までが条件。3要素を `,` で並べている
- 1つでも偽（または nil）なら `else { continue }` が実行され、次のループへ進む
- すべて真なら `i` と `current` が `guard` 以降で使える
- 括弧がない代わりに、1要素1行で改行すると区切りが見やすい
