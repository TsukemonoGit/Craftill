# Swiftの違い（JS / TS / C#経験者向け）

## 1. 演算子の前後の空白
```swift
let c1 = a + b   // OK
let c2 = a+b     // OK
let c3 = a +b    // エラー
```
両側に空白、または両側とも空白なし。C# / JS にはない規則。

## 2. 条件式に括弧は不要。`{ }` は必須
```swift
if x > 0 { print("正") }   // OK
// if (x > 0) print("正")  // エラー（{ } を省略できない）
```
C# は括弧が必須で `{ }` は省略可。Swiftは逆。

## 3. 条件は Bool のみ（truthy / falsy がない）
```swift
let n = 1
// if n { }        // エラー
if n != 0 { }      // OK
```
C# と同じ。JS / TS とは違う。

## 4. 型の暗黙変換がない
```swift
let a: Int = 3
let b: Double = 1.5
// let c = a + b          // エラー
let c = Double(a) + b     // OK
```
C# は `int + double` が通る。Swiftは通らない。

## 5. 型は名前の後ろに書く。引数名は呼び出し時に書く
```swift
let price: Int = 300

func add(price: Int, tax: Int) -> Int { price + tax }
add(price: 300, tax: 30)       // 引数名を書く（C# の名前付き引数は任意。Swiftは基本必須）

func add2(_ price: Int, _ tax: Int) -> Int { price + tax }
add2(300, 30)                  // _ を付けた引数は名前を書かない
```
- 1つの式だけの関数は `return` を省略できる
- C# の `var` は型推論のみ。Swiftの `let` / `var` は「変更できるか」を表す（型推論は両方で効く）

## 6. null がない。代わりにオプショナル
```swift
var s: Int? = nil     // Int? は Int とは別の型
// let t: Int = s     // エラー
if let v = s { print(v) }   // 確認してから取り出す
let w = s ?? 0              // nil のときの代わりの値（C# の ?? と同じ）
let x = s!                  // 強制取り出し。nil だと実行時にクラッシュ
```
- C# の `int?` に近いが、Swiftは参照型（class）も含めて、nil にしたい型にはすべて `?` が必要
- C# の `!` はコンパイラ警告を消すだけ。Swiftの `!` は nil のときクラッシュする

## 7. struct は値型。配列・文字列も値型
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

## 8. `let` は中身も変えられない（struct の場合）
```swift
struct P { var n: Int }
let p = P(n: 1)
// p.n = 5        // エラー
```
JS の `const` は中身を変えられる。C# の `readonly` に近いが、Swiftはその変数全体が対象。

## 9. 関数の引数は変更できない（`inout` で参照渡し可能）
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

## 10. enum は「関連値」を持てる。switch は「パターンマッチング」

### enum は関連値（Associated Values）を持てる
C# や TS の enum は単なる数値の別名だが、Swift の enum はケースごとに「異なる型や複数の値」を保持できる（TS の判別共用体 / Union 型に近い）。

```swift
struct Product { let name: String }

// カート行
struct CartLine {
    let product: Product
    var qty: Int
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

### Swift の switch は「パターンマッチング」
C# や JS の `switch` は「値の一致を判定するだけ」だが、**Swift の `switch` は「データ構造を分解するパターンマッチング」** である。これが最大の違い。

```swift
// ① 値の一致を判定
case .added(Product(name: "りんご"), qty: 3):

// ② 型の一致だけを判定（値は無視）
case .added(_, _):

// ③ 条件付きで判定（where 句）
case .added(let p, let qty) where qty > 0:

// ④ 値を取り出す（バインディング）← これが最も一般的
case .added(let p, let qty):
```

これらはすべて「パターン」としての `case` の使い方であり、**`let` の有無で「値の一致」と「値の取り出し」を区別している**。

#### なぜ `let` が必要なのか？
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

#### `.` の正体：型名のショートカット
`case .added(let p, let qty):` の `.` は「型名（`AddResult`）の省略」。

```swift
// ① 型名をちゃんと書いた場合
case AddResult.added(let p, let qty):

// ② 型名を省略して . だけ書いた場合（一般的）
case .added(let p, let qty):
```

この2つは完全に同じ意味。`.` は「型名は省略したけど、列挙型のケースを参照しています」という目印。

#### パターンマッチングは switch 以外にも使える
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

### switch の基本ルール
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

### switchで複数のケースに同じ処理を書く

#### `,` で並べる
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

#### 残りをまとめて `default`
```swift
switch c {
case .red:
    print("赤")
default:                 // red 以外すべて
    print("赤以外")
}
```

#### Int の範囲も書ける
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

## 11. `++` / `--` がない
```swift
var i = 0
i += 1       // OK
// i++       // エラー
```
C# / JS にはある。

## 12. 文字列は Int の添字で取り出せない
```swift
let s = "abc"
// s[0]                          // エラー（C# の s[0] は通る）
let first = s.first               // Optional("a")
let second = s[s.index(s.startIndex, offsetBy: 1)]   // "b"
```

## 13. 範囲外アクセス・オーバーフローはクラッシュする
```swift
let arr = [1, 2, 3]
// arr[5]    // 実行時にクラッシュ
```
- C# は `IndexOutOfRangeException` で、`try/catch` で受けられる。Swiftの配列の範囲外アクセスによるクラッシュは `do/catch` で受けられない
- `Int` の上限超えも通常の算術演算ではクラッシュする。C# は通常の設定では整数演算が折り返す
- JS は配列の範囲外アクセスで `undefined` になる

## 14. 文字列補間は `\( )`
```swift
let name = "A"
print("こんにちは \(name)")     // JS の `${name}` / C# の $"{name}" に相当
```

## 15. 範囲
```swift
for i in 0..<3 { print(i) }    // 0, 1, 2
for i in 0...3 { print(i) }    // 0, 1, 2, 3
```
`for (int i = 0; i < 3; i++)` 形式の `for` はない。

## 16. 命名の慣習
- 型（struct / enum / class）は `UpperCamelCase`: `Product`
- 変数・関数・プロパティは `lowerCamelCase`: `priceJpy`
- C# はメソッドとプロパティが `UpperCamelCase`。Swiftは `lowerCamelCase`

## 17. 行末の `;` は不要
改行が文の区切り。1行に複数の文を書くときだけ `;` を使う。

## 18. エラー処理は `throws` / `try` / `try?` / `try!`
```swift
enum MyError: Error { case bad }

func g(_ x: Int) throws -> Int {
    if x < 0 { throw MyError.bad }
    return x
}
```
- C# / JS は例外を `throw` するだけで、呼び出し側に `try` を書く義務はない。Swiftは `throws` 付きの関数を呼ぶ際、必ず `try`（または `try?` / `try!`）を明示する必要がある。

### 通常の `try`（`do-catch` と組み合わせる）
```swift
do {
    let r = try g(1)       // throws の関数を呼ぶときは try が必須
    print(r)
} catch {
    print("失敗: \(error)") // MyError.bad などがここに入る
}
```

### `try?`（エラー時に `nil` を返す）
```swift
let r1 = try? g(1)   // Int? 型になる。成功時は 1、失敗時は nil
let r2 = try? g(-1)  // nil になる（エラー内容は破棄される）
```
- C# / JS にはない構文。「成功した値」か「失敗して nil」の2択で扱いたい場合に便利。エラーの詳細が不要なときに `do-catch` を省略できる。
- 戻り値の型は自動的に Optional（`Int?` など）になる。

### `try!`（失敗時に強制クラッシュ）
```swift
let r3 = try! g(1)   // Int 型になる。成功時は 1
// let r4 = try! g(-1) // 実行時にクラッシュする
```
- 「この引数なら絶対にエラーにならない」と確信できる場合のみ使用する。C# で例外が来ないとわかっている場合に `catch` を書かないのと似ているが、Swiftでは万が一エラーになるとアプリが落ちるため注意が必要。

## 19. インスタンス生成に `new` は不要
```swift
struct P { var n: Int }
let a = P(n: 1)    // C# の new P(...) に相当
```

## 20. クロージャの `$0` は JavaScript の `a => ...` の `a` に相当

クロージャは、関数に渡す処理を `{ }` で書いたもの。`map`・`filter`・`reduce` などで「渡された値をどう処理するか」を指定するときによく使う。

### JavaScript / TypeScript と Swift の対応

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

### `$0` は何を表すか

JavaScriptでは、クロージャに渡される値に自分で引数名を付ける。

```javascript
nums.map(a => a * 2);
```

ここでの `a` は、`map` が順番に渡す各要素を受け取る引数。

Swiftでは、引数名を省略して `$0` と書ける。

```swift
nums.map { $0 * 2 }
```

この2つは同じ意味。`$0` はクロージャに渡された**1番目の引数**を表す。

引数名を明示して書くこともできる。

```swift
nums.map { a in a * 2 }
```

- `{ $0 * 2 }`：引数名を省略した書き方
- `{ a in a * 2 }`：引数名を `a` と宣言した書き方

同じクロージャの中では、`$0` による省略記法と `a in` のような引数宣言を混ぜない。

### `$0`・`$1`・`$2` の意味

| Swift | 意味 |
| --- | --- |
| `$0` | 1番目の引数 |
| `$1` | 2番目の引数 |
| `$2` | 3番目の引数 |

番号は `0` から始まる。

`map` と `filter` は、各要素を1つずつクロージャに渡すため、通常は `$0` を使う。

```swift
nums.map { $0 * 2 }           // 各要素を2倍にする
nums.filter { $0 % 2 == 0 }   // 偶数だけ残す
```

`reduce` は、累計値と現在の要素という2つの引数を受け取る。

```swift
[1, 2, 3].reduce(0) { $0 + $1 } // 6
```

- `$0`：現在の累計値
- `$1`：現在処理している要素

計算は `0 + 1 → 1 + 2 → 3 + 3 → 6` と進む。

`sorted` は、比較する2つの要素を受け取る。

```swift
nums.sorted { $0 > $1 } // [4, 3, 2, 1]
```

- `$0`：比較対象の1つ目
- `$1`：比較対象の2つ目
- `$0 > $1`：1つ目を2つ目より前に並べる条件

### 文字列にも使える

```swift
let upper = "KH8"

let letters = upper.filter { $0.isLetter }
let letters2 = upper.filter { char in char.isLetter }
```

どちらも `"KH"` になる。

`filter` は文字列の各文字を1つずつクロージャに渡すため、`$0` は `"K"`、`"H"`、`"8"` の順に各文字を表す。`upper` は文字列全体であり、`$0` とは別物。

### 使い分け

- 短い処理：`$0` を使うと簡潔
- 長い処理や意味を明確にしたい処理：`item in` など、名前を付けると読みやすい

**覚え方：** JavaScript の `a => ...` にある `a` を、Swiftでは短いクロージャなら `$0` と書ける。引数が2つなら `$0` と `$1` を使う。

## 21. キーパス (`\.`) と `\.self`
SwiftUI の `ForEach` などで見かける `\.` は「キーパス（Key Path）」と呼ばれる機能。プロパティへの参照を型安全に渡す仕組み。

```swift
let cart = ["ST-001", "KH-008"]

// 配列の要素そのものを ID として使う
ForEach(cart, id: \.self) { item in
    Text(item)
}
```

- **`\.self` の意味**: 「その要素そのもの」を指す。JS/TS でいう `item => item` に近い。
- **なぜ必要か**: `ForEach` は配列のどの要素が変更されたかを画面に正確に反映させるため、一意の ID を必要とする。要素が `String` や `Int` などの基本的な型（`Hashable` プロトコルに準拠）の場合、値そのものを ID として使えるため `\.self` を指定する。
- **構造体の場合**: 独自構造体（例: `Product`）の配列では、一意になるプロパティ（例: `id`）を指定する。`id: \.id` と書くことで、「各要素の `id` プロパティを ID として使う」ことを意味する。これは C# のプロパティ参照に近いが、コンパイル時に型チェックが効く点が優れている。
