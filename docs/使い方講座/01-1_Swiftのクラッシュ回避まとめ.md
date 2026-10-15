# Swiftのクラッシュパターンと回避方法まとめ

Swiftは `try/catch` で受ける代わりに、**クラッシュする操作を事前に避ける**書き方が基本。
クラッシュするコードは `// クラッシュ` と記載（実行しない）。

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
| 11 | 文字列の `String.Index` の範囲外 | `index(_:offsetBy:limitedBy:)` |
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
- 文字列からの変換 `Int("abc")` は Optional が返るので安全（レッスン5の `Int(digits) ?? 0`）

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
- `someThrowingFunc` は `throws` の付いた関数（レッスン49）

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
- CSVの取り込み（レッスン13）で同じIDが2行あるときに該当する

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

// let c = s[s.index(s.startIndex, offsetBy: 10)]     // クラッシュ

if let idx = s.index(s.startIndex, offsetBy: 10, limitedBy: s.endIndex) {
    print(s[idx])
} else {
    print("範囲外")
}
```
- `limitedBy:` を付けた形は、超えたとき nil が返る
- `endIndex` 自体を指した `s[endIndex]` はクラッシュするため、先頭からの文字数を使うときは `s.count` と比べて確認する

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
- `@Observable`（レッスン54）の `@Environment` で渡す場合の挙動は不明

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
