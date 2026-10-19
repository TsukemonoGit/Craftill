# Optionalと安全 ― 落ちないコードの書き方

> **前:** [Swiftの基礎](01_Swiftの基礎.md) ｜ **入口:** [はじめに](00_はじめに.md) ｜ **次:** [レジアプリの設計](03_レジアプリの設計.md)

`nil` かもしれない値を安全に扱う方法と、実行時に落ちる書き方を避ける方法をまとめたファイルです。
`if let` / `guard let` / `??` の使い分け、よくあるエラー、クラッシュ14パターンを扱います。

## `Int?` の `?`（オプショナル）って？
**「値が入っているかもしれないし、何も入っていない(nil)かもしれない」** という意味。
- `ST-003` は satsの値段が**空（NULL）**。それが `nil`（ニル＝空っぽ）
- `nil` のときは「sats払いはできない」と判断する

使うときは、空かどうか確認してから取り出す：
```swift
if let sats = product.priceSats {   // 入っていれば取り出す
    print("sats価格は \(sats)")
} else {
    print("この商品はsats払いなし") // 空っぽのとき
}
```

## `guard let` って？
`if let` の親戚で、「**ダメなら先に抜ける**」書き方。
`../06_QRを試す.md` に `guard let ciImage = filter.outputImage else { return nil }` として出てくる。

> `if let` / `guard let` / `if var` / `while let` / `if case` の**比較表と例は `02_Optionalと安全.md`** にまとめてある。
> ここでは「空かどうかを確認して取り出す書き方が2つある」ことだけ押さえればよい
> （`if let` ＝ `{ }` の中だけで使える／`guard let` ＝ そのあと全部で使える）。

## 1. 要点
- `if let` は、nil になりうる値（`?` が付く型 = Optional）から中身を取り出すための書き方
- nil になりえない `Int` / `String` などには使えない（エラーになる）
- Optional はSwiftの多くの場面で返ってくるため、`if let` はよく出てくる

---

## 2. 前提: `Int?` は `Int` とは別の型
```swift
let s: Int? = 5
```
- `s` は「`5` が入った箱」。`5` そのものではない
- 箱は「中身がある」か「空（nil）」のどちらか
- `+` や `>` などの計算・比較は、箱ではなく中身に対して行う
- `Int?` 以外も同じ。`String?` / `[Int]?` / `Product?` など、`型?` はすべて箱

```swift
let a: Int? = 5
// print(a + 1)        // エラー。箱のままでは計算できない
```

---

## 3. 基本の書き方
```swift
let s: Int? = 5

if let v = s {
    print(v + 1)       // 6。v は箱から出した中身（Int）
}
```
読み方: 「`s` に値が入っていれば、その中身を `v` に入れて `{ }` を実行する」

- この `=` は代入（比較は `==`）
- `s` が nil のときは `{ }` を飛ばす
- `v` は `{ }` の中でだけ使える

### `else` を付ける
```swift
let s: Int? = nil

if let v = s {
    print("値あり: \(v)")
} else {
    print("nil だった")      // こちらが実行される
}
```

### 同じ名前で取り出す
```swift
let s: Int? = 5

if let s {                 // if let s = s と同じ意味（Swift 5.7以降）
    print(s + 1)           // 6。この s は Int
}
```

### 複数をまとめる
```swift
let a: Int? = 1
let b: Int? = 2

if let x = a, let y = b {  // 両方に値があるときだけ実行
    print(x + y)           // 3
}

if let v = a, v > 0 {      // 取り出せて、かつ v > 0
    print(v)
}
```
- `,` は「かつ」。左が成り立ったときだけ右を調べる

---

## 4. なぜ変数を作るのか
`if let` の `v` は、箱から出した中身を入れる場所。

### 条件を通っても、型は `Int?` のまま
```swift
let n: Int? = 5

if n != nil {
    // print(n + 1)        // エラー。n はここでも Int?
    print(n! + 1)          // 6。! で取り出す必要がある
}
```
- Swiftは「条件を通ったから nil ではない」と判断して型を `Int` に変えない
- 型を `Int` にするには、`if let` / `guard let` / `!` / `??` のどれかを使う

### Optional の正体は enum
```swift
let s: Int? = 5

switch s {
case .some(let v):         // 中身がある
    print(v + 1)
case .none:                // 空（nil）
    print("nil")
}
```
- `if let v = s { ... } else { ... }` は、この `switch` を短く書いたもの

### 設計意図について
- 変数が `var` のとき、確認してから使うまでの間に値が変わる事故を、取り出した `v` が防ぐという説明がされることが多い
- 公式の設計意図の記述は未確認

---

## 5. 変数が `Int` か `Int?` かで書き方が変わる
```swift
let a: Int = 5
if a > 0 { print(a) }               // OK。if let は不要

let b: Int? = 5
// if b > 0 { }                     // エラー。Int? は > で比較できない
if let v = b, v > 0 { print(v) }    // OK
if (b ?? 0) > 0 { }                 // OK。nil のときは 0 として扱う
if b == 5 { }                       // OK。== と != は Optional のまま使える
```

| 変数の型 | `if n > 0 { }` |
| --- | --- |
| `Int` | そのまま書ける |
| `Int?` | エラー。`if let v = n, v > 0` か `(n ?? 0) > 0` にする |

---

## 6. Optional が返ってくる場面
```swift
let arr = [1, 2, 3]
let dict = ["a": 1]

if let v = arr.first { print(v) }          // 配列の先頭（空なら nil）
if let v = dict["a"] { print(v) }          // Dictionary の検索（なければ nil）
if let v = Int("123") { print(v) }         // 文字列→数値（変換できなければ nil）

let x: Any = 5
if let v = x as? Int { print(v) }          // 型の変換（できなければ nil）

// if let v = try? someThrowingFunc() { }  // try?（失敗したら nil）

if let data = UserDefaults.standard.data(forKey: "cart") { }   // 保存データ（なければ nil）
```
- `03_レジアプリの設計.md` のレッスン8（永続化）の復元処理もこの形

### このアプリでの使いどころ
```swift
// Product の priceSats は Int?（sats単価なし = nil）
if let s = p.priceSats {
    sats += s                   // sats単価がある行
} else {
    jpyForSats += p.priceJpy    // sats単価がない行
}
```
- `03_レジアプリの設計.md` のレッスン4の `totals()` がこの形
- `stock`（在庫を数えない商品は nil）も同様

---

## 7. 取り出し方の比較
```swift
let s: Int? = 5

if let v = s { print(v) }      // 値があるときだけ実行
let a = s ?? 0                 // nil のときの代わりの値を決める
let b = s!                     // 決めつけて取り出す。nil だとクラッシュ
```

| 書き方 | nil のとき | 用途 |
| --- | --- | --- |
| `if let v = s { }` | `{ }` を飛ばす | 値があるときだけ処理したい |
| `s ?? 0` | 代わりの値を使う | 値がなくても続行したい |
| `s!` | クラッシュ | 絶対に nil でないと言い切れる場合のみ |

---

## 8. 仲間の書き方
### `guard let`（nil なら関数を抜ける）
```swift
func f(_ s: Int?) {
    guard let v = s else {
        print("nil")
        return                 // 必ず関数を抜ける処理を書く
    }
    print(v)                   // ここから下で v を使える
}
```
- `if let` は `{ }` の中でだけ `v` を使える
- `guard let` は、同じ階層の以降の行すべてで `v` を使える

### `if var`（取り出した値を変更したいとき）
```swift
let s: Int? = 5

if var v = s {
    v += 1
    print(v)                   // 6
}
```

### `while let`（nil になるまで繰り返す）
```swift
var stack = [1, 2, 3]

while let x = stack.popLast() {
    print(x)                   // 3, 2, 1
}
```

### `if case`（enum の関連値を取り出す）
```swift
enum Result2 {
    case ok(Int)
    case fail(String)
}

let r = Result2.ok(10)

if case .ok(let v) = r {
    print(v)                   // 10
}
```
- `if let v = s` は `if case .some(let v) = s` を短く書いたもの
- `if case` は Optional 以外の enum にも使える

| 書き方 | 使う場面 |
| --- | --- |
| `if let v = s { }` | 値があるときだけ処理する |
| `guard let v = s else { return }` | 値がなければ関数を抜ける。以降で `v` を使う |
| `if var v = s { }` | 取り出した値を変更する |
| `while let x = ... { }` | nil になるまで繰り返す |
| `if case .xxx(let v) = e { }` | enum の特定のケースのときだけ関連値を取り出す |

---

## 9. TypeScript との違い
```ts
// TypeScript
function f(n: number | null) {
    if (n !== null) {
        console.log(n + 1);    // n は number に絞り込まれる
    }
}
```
```swift
// Swift
func f(_ n: Int?) {
    if n != nil {
        // print(n + 1)        // エラー。絞り込まれない
    }
}
```
- TypeScript は条件で型が絞り込まれる。Swiftは絞り込まれない

## よくあるつまずき（エラー別）

エラー文は英語ですが、見る場所はだいたい決まっています。まずはここを確認してください。

| エラー / 症状 | 原因 | 見る場所 |
| --- | --- | --- |
| `Expressions are not allowed at the top level` | 「アプリ」用のファイルに、一番外側の `print` や `let` を書いた | 「つまずき①」 |
| `Cannot find 'Product' in scope` | `base/Types.swift` を貼っていない／貼る順序が違う | `03_レジアプリの設計.md` のレッスン2、`00_はじめに.md` の `base/` の節 |
| `Value of optional type ... must be unwrapped` | `Int?` などの Optional を、そのまま `Int` として使った | 「`Int?` の `?`」、`02_Optionalと安全.md` |
| `Unexpectedly found nil while unwrapping` | `!` で nil を取り出した | `02_Optionalと安全.md` §1 |
| `Index out of range` | 配列の範囲外を読んだ | `02_Optionalと安全.md` §2 |
| `Cannot convert value of type ...` | 型が合っていない（`String` と `Int` など） | 「型を書けば入れられる」、`01_Swiftの基礎.md` |
| `Missing argument label ... in call` | 呼び出すときのラベルが違う | 「引数のラベル（`_` や日本語）」 |
| `Cannot assign to property: 'self' is immutable`／画面が変わらない | View の変数に `@State` が付いていない | 「View（画面）の中の変数はどこに書く？」 |
| `Type ... does not conform to protocol 'Identifiable'` | `ForEach` の要素に `id` がない | `ForEach(items, id: \.id)` を使う |
| `No such module ...` | `import` 名が違う／その環境に無い | 「Playgrounds って？」、`06_Macへ_Xcode.md` |

> 直せないときは、**エラー文の最初の1行**を検索するか、この表に戻ってください。
> 実行時に落ちる系（`Index out of range` など）は、`02_Optionalと安全.md` に全部まとめてあります。

## 安全の原則

1. `!` / `try!` / `as!` は原則使わない。使うなら「ここで nil になったら設計が壊れている」と説明できる場所だけ
2. 配列は `indices.contains(i)` / `first` / `last` で範囲を確認する
3. 割り算・剰余の前に、0 でないことを確認する
4. 変換は `as?` / `Int(exactly:)` のように、失敗を値で返すものを使う
5. 再帰には必ず終了条件を書く
6. 外から来た値（CSV・QR・手入力）は、使う前に正規化と検証をする

## 一覧

| # | クラッシュする操作 | 回避 |
| --- | --- | --- |
| 1 | Optionalの `!`（強制取り出し） | `if let` / `guard let` / `??` |
| 2 | 配列の範囲外アクセス | 範囲確認 / `first` / `last` / 自作の安全な添字 |
| 3 | 空配列への `removeFirst()` `removeLast()` | `isEmpty` 確認 / `popLast()` |
| 4 | `Int` のオーバーフロー | `addingReportingOverflow` / `&+` |
| 5 | 整数の0除算・0での剰余 | 割る前に0を確認 |
| 6 | `Int(Double)` の変換（NaN・無限大・範囲外） | `Int(exactly:)` |
| 7 | `try!` | `do/catch` / `try?` |
| 8 | `as!`（強制キャスト） | `as?` |
| 9 | `Dictionary(uniqueKeysWithValues:)` でキー重複 | `Dictionary(_:uniquingKeysWith:)` |
| 10 | 下限が上限より大きい範囲（`5...1`） | 大小を確認してから範囲を作る |
| 11 | 文字列の `String.Index` の範囲外 | `offset < s.count` を確認 / `index(_:offsetBy:limitedBy:)` |
| 12 | 初期化前の `Int!` の使用 | `Int!` を使わず `Int?` にする |
| 13 | `@EnvironmentObject` の渡し忘れ | 親の View で必ず `.environmentObject(...)` を付ける |
| 14 | 終わらない再帰 | 終了条件を必ず書く |

---

## 1. Optionalの `!`
```swift
let s: Int? = nil

// let a = s!                     // クラッシュ

if let v = s { print(v) }         // 値があるときだけ実行
let b = s ?? 0                    // nil のときの代わりの値

func f(_ x: Int?) {
    guard let v = x else { return }   // nil なら関数を抜ける
    print(v)                          // 以降は v を普通の Int として使える
}
```
- `guard let` は「条件を満たさないときに早めに抜ける」書き方

## 2. 配列の範囲外アクセス
```swift
let arr = [10, 20, 30]
let i = 5

// let a = arr[i]                 // クラッシュ

if arr.indices.contains(i) { print(arr[i]) }   // 範囲確認
print(arr.first ?? 0)                          // 空でも nil が返る

extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}
print(arr[safe: 5] ?? 0)          // 0
```
- Dictionary の `d["x"]` は元から Optional が返るので安全

## 3. 空配列への `removeFirst()` `removeLast()`
```swift
var xs: [Int] = []

// xs.removeFirst()               // クラッシュ
// xs.remove(at: 3)               // クラッシュ（範囲外）

if !xs.isEmpty { xs.removeFirst() }
let last = xs.popLast()           // Optional。空なら nil
```

## 4. Int のオーバーフロー
```swift
let big = Int.max

// let a = big + 1                // クラッシュ

let r = big.addingReportingOverflow(1)
print(r.overflow)                 // true
let w = big &+ 1                  // 折り返してよいときは &+ &- &*
```

## 5. 0除算
```swift
let a = 10
let b = 0

// let c = a / b                  // クラッシュ
// let d = a % b                  // クラッシュ

if b != 0 { print(a / b) }
```
- `Double` の0除算はクラッシュせず、`inf` や `nan` になる

## 6. `Int(Double)` の変換
```swift
let d = Double.nan

// let a = Int(d)                 // クラッシュ（NaN・無限大・Intに入らない大きさ）

if let n = Int(exactly: 3.0) { print(n) }   // 3
let m = Int(exactly: 3.5)                   // nil（小数があるため）
let k = Int(exactly: d)                     // nil
```
- `Int(3.5)` はクラッシュせず `3`（小数点以下を切り捨て）
- 文字列からの変換 `Int("abc")` は Optional が返るので安全（`03_レジアプリの設計.md` レッスン5の `Int(digits) ?? 0`）

## 7. `try!`
```swift
// let r = try! someThrowingFunc()     // 失敗するとクラッシュ

do {
    let r = try someThrowingFunc()
    print(r)
} catch {
    print("失敗")
}

let r2 = try? someThrowingFunc()       // 失敗したら nil
```
- `someThrowingFunc` は `throws` の付いた関数（`49_エラー処理を書く.md`）

## 8. `as!`
```swift
let x: Any = "abc"

// let n = x as! Int              // クラッシュ

if let n = x as? Int { print(n) } // 変換できなければ nil
```

## 9. Dictionary のキー重複
```swift
let pairs = [("a", 1), ("a", 2)]

// let d = Dictionary(uniqueKeysWithValues: pairs)    // クラッシュ

let d = Dictionary(pairs, uniquingKeysWith: { first, second in second })
print(d)    // ["a": 2]（重複したときは後の値を採用）
```
- CSVの取り込み（`13_商品マスタCSVを取り込む.md`）で同じIDが2行あるときに該当する

## 10. 範囲の大小
```swift
let lo = 5
let hi = 1

// for i in lo...hi { }           // クラッシュ（下限 > 上限）

if lo <= hi {
    for i in lo...hi { print(i) }
}
// 0..<n は n が 0 でも安全（空の範囲になる）。n が負だとクラッシュ
```

## 11. 文字列の位置
```swift
let s = "abc"
let offset = 10

// let c = s[s.index(s.startIndex, offsetBy: offset)]   // クラッシュ

if offset >= 0 && offset < s.count,
   let idx = s.index(s.startIndex, offsetBy: offset, limitedBy: s.index(before: s.endIndex)) {
    print(s[idx])
} else {
    print("範囲外")
}
```
- `limitedBy:` を付けた形は、上限を超えたとき nil が返る
- ただし `limitedBy: s.endIndex` にすると、`offset == s.count` のときに `endIndex` が返り、`s[idx]` でクラッシュする。**必ず `offset < s.count` を確認**する
- 文字数で扱うなら `Array(s)` にして `chars[offset]` も分かりやすい（大きな文字列ではコピーが発生する）

## 12. `Int!`（暗黙アンラップ）
```swift
var a: Int! = nil
// let b = a + 1                  // クラッシュ

var c: Int? = nil                 // 通常の Optional にして if let / ?? で扱う
```

## 13. `@EnvironmentObject` の渡し忘れ
```swift
// 子の View が @EnvironmentObject var store: Store を宣言しているのに、
// 親が .environmentObject(store) を付けていないと、表示時にクラッシュする

ContentView()
    .environmentObject(store)     // 親で必ず付ける
```
- `@Observable`（`54_@Observableで状態を共有する.md`）の `@Environment` で渡す場合の挙動は不明

## 14. 終わらない再帰
```swift
func countdown(_ n: Int) {
    // countdown(n - 1) だけだと止まらずクラッシュ（スタックオーバーフロー）
    if n <= 0 { return }          // 終了条件
    countdown(n - 1)
}
```

---

## 意図的にクラッシュさせるもの（バグの検出用）
```swift
// fatalError("ここには来ない")          // 常にクラッシュ
// precondition(x > 0, "x は正")        // 条件を満たさないとクラッシュ
// assert(x > 0)                        // デバッグビルドのみクラッシュ
```
- 自分で書くことは少ない。ライブラリのコードに含まれる

---
