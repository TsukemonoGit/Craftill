# `if` と `if let`

## 普通の `if`
```swift
let n = 5

if n > 0 {
    print("正の数")
}
```
- `if 条件 { 実行する処理 }`
- 条件が `true` のときだけ `{ }` の中を実行する

## `if let`（Optionalの中身を取り出す）
```swift
let s: Int? = 5       // Int? は「Int か nil」

if let v = s {
    print(v)          // 5
}
```
読み方: 「`s` に値が入っていれば、その中身を `v` に入れて `{ }` を実行する」

- `s` が `5` のとき: `v` が `5` になり、`{ }` を実行する
- `s` が `nil` のとき: `{ }` は実行せず飛ばす
- `v` の型は `Int`（`Int?` ではない）。`{ }` の中でだけ使える

## `nil` のとき
```swift
let s: Int? = nil

if let v = s {
    print(v)          // 実行されない
}
print("終わり")        // これは出る
```

## `else` を付ける
```swift
let s: Int? = nil

if let v = s {
    print("値あり: \(v)")
} else {
    print("nil だった")    // こちらが実行される
}
```

## 比較
```swift
let s: Int? = 5

// print(s + 1)           // エラー。s は Int? なので、そのまま計算できない

if let v = s {
    print(v + 1)          // 6。v は Int なので計算できる
}

print((s ?? 0) + 1)       // 6。nil のときは 0 を使う
```

## 複数をまとめて確認する
```swift
let a: Int? = 1
let b: Int? = 2

if let x = a, let y = b {      // 両方に値があるときだけ実行
    print(x + y)               // 3
}
```

## 同じ名前で取り出す
```swift
let s: Int? = 5

if let s {                     // if let s = s と同じ意味（Swift 5.7以降）
    print(s)
}
```

- `if let` の書き方はレッスン1⑦にも載っている
- `s!` は「nil ではないと決めつけて取り出す」書き方で、nil のときはクラッシュする。`if let` は nil のときに `{ }` を飛ばすのでクラッシュしない
