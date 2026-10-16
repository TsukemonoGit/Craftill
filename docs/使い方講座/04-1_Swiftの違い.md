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

## 9. 関数の引数は変更できない
```swift
func f(_ x: Int) {
    // x += 1     // エラー（引数は let 扱い）
}
```
C# の引数は変更できる。

## 10. switch は網羅が必須。`break` は不要
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

## 18. エラー処理は `throws` / `try`
```swift
enum MyError: Error { case bad }

func g(_ x: Int) throws -> Int {
    if x < 0 { throw MyError.bad }
    return x
}

do {
    let r = try g(1)       // throws の関数を呼ぶときは try が必須
    print(r)
} catch {
    print("失敗")
}
```
- C# は例外を `throw` するだけで、呼び出し側の記述は不要
- Swiftは `throws` の関数を呼ぶとき `try` を書く

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