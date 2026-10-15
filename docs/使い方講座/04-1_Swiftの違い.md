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
var ys = xs      // 配列もコピー
ys.append(4)
print(xs.count)  // 3
```
- struct の値型は C# と同じ
- C# の配列 / `List` は参照型で共有される。Swiftの配列はコピーされる
- JS のオブジェクト / 配列は参照が共有される

## 8. `let` は中身も変えられない（struct の場合）
```swift
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
- C# は `IndexOutOfRangeException` で、`try/catch` で受けられる。Swiftのクラッシュは `do/catch` で受けられない
- `Int` の上限超えもクラッシュする。C# は通常の設定では折り返す
- JS は `undefined` になる

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
let a = P(n: 1)    // C# の new P(...) に相当
```
