# Swiftの基礎 ― データと関数の形

> **前:** [はじめに](00_はじめに.md) ｜ **入口:** [はじめに](00_はじめに.md) ｜ **次:** [Optionalと安全](02_Optionalと安全.md)

Swiftの文法と、このアプリで使うデータの形をまとめたファイルです。
`struct` / `enum` / 関数 / 型 / 引数 / SwiftUIの変数の置き場所を扱います。
Optionalとクラッシュの話は `02_Optionalと安全.md` に分けています。

## Playgrounds って？
iPadの**Swift練習帳アプリ**。コードを書いて、すぐ実行して、結果を見られる。ファイルを作らなくていい。

1. App Storeで **「Swift Playgrounds」** を入れる
2. アプリを開く → **「新しいプレイグラウンド」→「ブック（Book）」** を選ぶ
3. 画面に出てくる `import SwiftUI` などは**消してOK**（残っていてもよい）
4. コードを書いて、**実行ボタン(▶)** を押す
5. `print("...")` と書くと、書いた文字が下/右の**コンソール**に出る

最初は「テンプレを消して `print("やあ")` と書いて▶」だけで十分。
アプリ内の**「コードを学ぼう」**という初心者コースが一番おすすめ。

### どれを使う？「ブック / アプリ / 教材ブック」
新規作成では **「アプリ」か「ブック」** を選ぶ（「Playground / Blank」ではない）。

| 名前 | 作り方 | 使える？ |
| --- | --- | --- |
| **ブック（Book）** | 新しいプレイグラウンド → ブック | ✅ 自由にコードを書ける。**レッスン・練習はこれ** |
| アプリ（App） | 新しいプレイグラウンド → アプリ | △ 本物のアプリ用。トップレベルに書けない（下の「つまずき①」） |
| 教材ブック（「コードを学ぼう」等） | ホームのBooks | ✕ 穴埋め式。自由なコードは貼れない |

### ブック と アプリ の違い（くわしく）
| | ブック（Book） | アプリ（App） |
| --- | --- | --- |
| 正体 | 1つの**ノート**（ドキュメント） | 1つの**アプリ本体** |
| 上から順に実行 | ✅ される | ✕（関数/structの中だけ） |
| 画面の出し方 | 自分で `setLiveView(...)` を書いた時 | 起動時に**自動**で出る |
| 入口 | 無い | `@main struct ...App: App` |
| 向いてる | 練習・試す・1画面プレビュー | 本物のアプリを作る |

**ブック**: ノート。コードを上から順に実行し、`print` の結果が出る。SwiftUIの画面は `PlaygroundPage.current.setLiveView(QRView())` と書いた時に出る（書かないと出ない）。1ファイルに関数もUIもまとめてOK。

**アプリ**: 入口（`@main`）があり、起動すると画面が自動で出て、動き続ける。`setLiveView` は書かない。
```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            QRView()   // ← 起動時にこれが自動で出る
        }
    }
}
```

**使い分け**: 今（iPad）は**ブック**（書いてすぐ試せる）。Macで本物のアプリを作る時は**アプリ**。

**Svelteでいうと**: アプリ ≒ アプリ本体／`+page.svelte`（入口が自動で表示）。ブック ≒ 自分で開いて実行するノート（直接の対応は無い）。

### つまずき①: 「Expressions are not allowed at the top level」
- **原因**: 「アプリ（App）」を作ってしまった。アプリのファイルは普通のSwiftファイル扱いで、一番外側（トップレベル）に `print` や `let x = ...` を書けない
- **直し方**: **「ブック（Book）」**で作り直す。ブックはトップレベルに書けて ▶ で動く
- 「トップレベル」＝関数やクラスの中ではなく、**ファイルの一番外側**のこと
- アプリで書きたい時は、コードを `func test() { ... }` に入れて、`ContentView` の `body` などから `test()` と呼ぶ

---

## `struct Product` って？
**「商品1つ分のデータを入れる箱の“形（ひな形）”」**。
`struct` は「構造体」。こういう項目をまとめて1つの仲間にします、という定義。
例えると**商品カードの雛形**。

```swift
struct Product {
    let id: String        // ID      例: "KH-008"
    let name: String      // 名前    例: "キーホルダー 08"
    let priceJpy: Int     // 円の値段 例: 800
    let priceSats: Int?   // satsの値段 例: 1200
    var stock: Int?       // 在庫     例: 1
}
```

| 書き方 | 意味 |
| --- | --- |
| `id` / `name` | 欄の名前 |
| `: String` | **文字（テキスト）** を入れる欄 |
| `: Int` | **整数（数字）** を入れる欄 |
| `let` | あとから**変えられない** |
| `var` | あとから**変えられる**（在庫は減るので `var`） |
| `: Int?` の `?` | **あるかも / 空っぽかも**（オプショナル。下で説明） |

> 補足: `let id, name: String` は「id と name は両方 String」という**省略した書き方**。上の例は1行ずつ書いた版で意味は同じ。
>
> **実際に使う `Product` は `base/Types.swift` に1つだけある**（`typeId` など項目が増える）。ここは形をつかむための簡略版。`base` と混ぜて貼ると二重定義になるので、レッスンでは `base` の方を使う。

## 関数の戻り値と `->`

### 戻り値なし（`->` を省略）
```swift
func f(_ x: Int) {
    print(x)
}
```

### 戻り値なし（`-> Void` と書いても同じ）
```swift
func f(_ x: Int) -> Void {
    print(x)
}
```

### 戻り値あり（`->` が必須）
```swift
func double(_ x: Int) -> Int {
    return x * 2
}

func double2(_ x: Int) -> Int { x * 2 }   // 式が1つなら return を省略できる
```

### 複数の値を返す（タプル）
```swift
func minMax(_ a: Int, _ b: Int) -> (min: Int, max: Int) {
    return (min(a, b), max(a, b))
}

let r = minMax(3, 5)
print(r.min, r.max)   // 3 5
```

- `->` は「この関数が返す型」を表す
- 何も返さない関数は `->` ごと省略するのが普通の書き方
- レッスン4の `totalLines` は、`(satsLine: String, cashLine: String)` という**タプル**を返す書き方（`totals()` 本体は `Totals` 構造体を返す）

## `enum StockMode` って？
**「決まった選択肢のうち、どれか1つ」** を表す型（`enum`＝列挙型）。
種類を3パターンに限定しておくと、変な値にならず安全。

```swift
enum StockMode {
    case counted   // 数量管理型（ステッカー。在庫を数で持つ）
    case unique    // 一点物型（キーホルダー。在庫は1か0）
    case none      // 在庫管理なし型（今回は使わない）
}
```
使い方: `let mode = StockMode.counted` → 「これは数量管理型」と決まる。

### enum の中にプロパティやメソッドを書ける
他の言語の `enum` は「定数の集まり」で終わりのことが多い。でも **Swiftの `enum` は“型”なので、中にプロパティ（getter）やメソッドを書ける**。
「その状態についての情報は、状態自身に持たせる」という書き方ができる。

> 実際の `SaleState` は `base/Types.swift` に**8状態**ある（`03_レジアプリの設計.md` のレッスン6）。ここは説明用に3つだけ書く。

```swift
enum SaleState {
    case idle             // 待機中
    case scanning         // スキャン中
    case done             // 完了

    var label: String {   // ← 中に getter（計算プロパティ）を定義
        switch self {     // self = 今のケース（.idle や .scanning）
        case .idle:     return "レジ待機中"
        case .scanning: return "商品をスキャン中"
        case .done:     return "会計完了"
        }
    }

    func isFinished() -> Bool {   // ← メソッドも書ける
        return self == .done
    }
}

let s = SaleState.scanning
print(s.label)        // 商品をスキャン中（カッコは付けない）
print(s.isFinished()) // false（メソッドはカッコが要る）
```

| 書き方 | 呼び方 | 意味 |
| --- | --- | --- |
| `var label: String { ... }` | `s.label` | **計算プロパティ**（getter）。`= 値` が無く、`{ }` の中を毎回実行して返す |
| `func isFinished() -> Bool { ... }` | `s.isFinished()` | メソッド。カッコを付けて呼ぶ |

- **計算プロパティは必ず `var`**。「再代入できる」という意味ではなく、そういう決まり（`let` は書けない）。読み取りだけなら `get { }` を省略して `{ ... }` と書ける
- 中で使う **`self`** は「今この値を呼んでいる実体」。`s.label` なら `self` は `.scanning`。`switch self` は「自分のケースで分岐する」という意味
- `case .idle:` は `case SaleState.idle:` の省略形

> Svelteでいうと、`var label { ... }` は **getter**（`get label() { ... }`）、`self` は **`this`** のイメージ。

---
以下の「View（画面）の中の変数はどこに書く？」のセクションを、`body` が計算プロパティであること、および `productID` がストアドプロパティであることを明確に区別する内容に修正してください。

---

## View（画面）の中の変数はどこに書く？
`struct QRView: View` も `struct Product` と同じ**構造体**です。
ここで重要なのは、構造体の中のプロパティが「格納型」と「計算型」の2種類に分かれることです。

```swift
struct QRView: View {
    // 1. ストアドプロパティ（格納型プロパティ）
    // インスタンス生成時に値がメモリに保持される。計算は行わない。
    let productID = "KH-008"

    // 2. 計算プロパティ（Computed Property）
    // アクセスされるたびに { } の中を実行し、UIの構造を計算して返す。
    // 値をメモリに保持せず、Viewプロトコルが必須とする要件。
    var body: some View {
        Text(productID)        // 上で定義したストアドプロパティを参照して使える
    }
}
```

変数（状態やデータ）は、基本的に **`body` の外（構造体の直下）にストアドプロパティとして**書きます。`body` はあくまで「そのプロパティの値を使って、画面に何を出力するかを計算する場所」です。

### `let` か `@State` か
| 書き方 | いつ使う | 変えたら画面は更新される？ |
| --- | --- | --- |
| `let productID = "KH-008"` | 決まった値（変わらない） | ー（変えられない） |
| `@State var count = 0` | 途中で変わる値 | ✅ 更新される |

- ふつうの `var` に変わる値を入れても**画面は更新されない**。変わる値は **`@State`** を付ける
- `@State` を変えると SwiftUI が `body`（計算プロパティ）をもう一度実行して**画面を描き直す**

```swift
struct CounterView: View {
    @State var count = 0             // 変わる値（ストアドプロパティ）

    var body: some View {            // 計算プロパティ
        VStack {
            Text("\(count)")
            Button("+1") { count += 1 }   // 変えると body が再計算され画面が更新される
        }
    }
}
```

### 書く場所のルール
- `var body` の**上**に書く（構造体のプロパティとして定義）
- `body { }` の中に `let x = ...` と書くこともできるが、それは**呼び出されるたびに作り直される一時的なローカル変数**
- 画面をまたいで使う値・後で変えたい値は**プロパティ**として外に書く

### QRViewの場合
```swift
struct QRView: View {
    let productID = "KH-008"   // 決まった値 → ストアドプロパティとして外に定義

    var body: some View {      // 計算プロパティ
        VStack(spacing: 12) {
            Text(productID)
            if let img = makeQR(productID) { ... }
        }
    }
}
```
→ `productID` を1か所にまとめたので、変えたい時は**ここだけ**変更すれば、`body` 内の計算結果（表示とQRの両方）に自動的に反映される。

---

## 変数の置き場所まとめ
Swiftは「**どこで生きるか**」で変数の種類が分かれる。

| 種類 | 例 | 見える範囲（スコープ） | 寿命（いつ消える） |
| --- | --- | --- | --- |
| 関数の中（ローカル） | `var sum = 0` | その関数の中だけ | 関数が終わると消える |
| 関数の引数 | `func f(_ x: Int)` | その関数の中 | 呼び出しごと |
| データ型のプロパティ | `struct Product { let id: String }` | そのインスタンス | インスタンスが消えるまで |
| Viewのプロパティ | `let productID` / `@State var count` | そのViewの中 | Viewが生きている間（`@State`はSwiftUIが保管） |
| 計算プロパティ | `var subtotal: Int { qty*price }` | その型の中 | 値を持たない（毎回計算） |
| グローバル / `static` | `let taxRate = 0.1` | アプリ全体 | アプリが終わるまで |

**決めている3つの軸**:
- **スコープ** … `{ }` のどこまで見えるか
- **寿命** … いつまで存在するか（ローカルは関数が終わると消える）
- **値型 or 参照型** … `struct` は**渡すとコピー**。だから View の `@State` は、View 本体ではなく **SwiftUI が別に持っている**（`struct` のままだと書き換えられないため）
- 頭に付ける**印**（`@State` / `@Binding` / `@Observable`）で「SwiftUI がどう扱うか」が決まる

> Svelte との対応は `05_他言語から見たSwift.md` 参照。

---

## `$` って？
Swiftの `$` は、使われ方が2種類ある。

| 書き方 | 場所 | 意味 |
| --- | --- | --- |
| `$0` `$1` `$2` | クロージャ（`{ }`）の中 | 引数の**省略記法** |
| `$count` `$name` | SwiftUI（`@State` などの前） | 変数への**つながり（Binding）** |

### ① `$0`（クロージャの引数の省略記法）
**クロージャ**＝`{ }` で囲んだ処理。`filter` や `map` に「各要素にこの処理をして」と渡すときに使う。
`$0` は、クロージャに渡された**1番目の引数**。

```swift
let upper = "KH8"
let letters = upper.filter { $0.isLetter }          // 省略記法
let letters2 = upper.filter { char in char.isLetter } // 同じ意味（引数名を宣言した版）
```
- `filter` は文字列の各文字を1つずつクロージャに渡す。`$0` はそのとき渡されている**1文字**
- `"KH8"` なら `$0` に `"K"` → `"H"` → `"8"` の順に入って実行される
- `upper.isLetter` ではない。`upper`（文字列全体）ではなく、その中の**1文字**が `$0`
- `char in` のような**引数名の宣言を省略できる**のが `$0` の役割

引数が複数あるときは `$0`, `$1`, `$2` と番号が増える。
```swift
[1, 2, 3].reduce(0) { $0 + $1 }   // $0=累計, $1=現在の要素 → 6
```

```swift
let nums = [1, 2, 3, 4]
nums.map { $0 * 2 }          // [2, 4, 6, 8]
nums.filter { $0 % 2 == 0 }  // [2, 4]
nums.sorted { $0 > $1 }      // [4, 3, 2, 1]
```

**ルール**:
- 番号は **0 から**始まる（`$1` から始まらない）
- 1つのクロージャの中で、`char in` のような**宣言と `$0` を混ぜられない**（どちらかに統一）
- 使っていない番号があるとエラーになることがある（`$1` を使うなら `$0` も使う必要がある）
- クロージャの中にクロージャがある場合、`$0` は**いちばん内側**のクロージャの引数
- 処理が長い・意味が分かりにくいときは、`char in` のように**名前を付けた方が読みやすい**

> Svelteでいうと、JSの `arr.filter(x => x > 0)` の `x` を、名前を付けずに `$0` と書くイメージ。

### ② `$名前`（Binding：SwiftUI）
`@State` で作った変数の前に `$` を付けると、**「値」ではなく「その変数へのつながり（Binding）」**になる。
`TextField` のように、**画面側から値を書き換えたい**部品に渡すときに使う。

```swift
struct NameView: View {
    @State var name = ""                    // 変わる値

    var body: some View {
        VStack {
            TextField("名前", text: $name)  // $name = 双方向のつながり（入力すると name が変わる）
            Text("こんにちは \(name)")      // name = ただの値（読むだけ）
        }
    }
}
```

| 書き方 | 渡すもの | できること |
| --- | --- | --- |
| `name` | 値のコピー | 読むだけ |
| `$name` | 変数へのつながり（`Binding`） | 読む＋**書き換える** |

- `TextField` は入力されたら `name` を書き換える必要がある。だから `$name` を渡す
- `Text(name)` は表示するだけなので `$` は要らない
- `Toggle` / `Slider` / `Picker` なども同じく `$変数名` を渡す
- `$` は `@State` のほか `@Binding` などを付けた変数にも使える

> Svelteでいうと、`bind:value={name}` が `TextField("名前", text: $name)` に近い。

---

## 言葉のミニ辞典
| 言葉 | かんたんに言うと |
| --- | --- |
| `struct` | データをまとめる箱の形 |
| `enum` | 決まった選択肢のどれか1つ |
| `let` / `var` | 変えられない / 変えられる |
| `String` / `Int` | 文字 / 整数 |
| `nil` / `?` | 空っぽ / 空っぽかも |
| `print()` | 文字を出力する |
| `if let` | 空っぽか確認して取り出す |
| `guard let` | 空っぽなら先に抜けて取り出す |
| `@State` | 変えると画面が更新される変数 |
| `_`（引数の前） | 呼ぶ時にラベルを付けない印 |
| `$0` `$1` | クロージャ `{ }` の1番目・2番目の引数（省略記法） |
| `$name` | `@State` 変数へのつながり（Binding）。書き換えたい部品に渡す |

## 引数のラベル（`_` や日本語）

Swiftの引数は **`ラベル 内部名: 型`** の順に書ける。
- **ラベル**＝**呼び出す時**に使う名前
- **内部名**＝**関数の中身**で使う名前
- 1つだけ書くと両方同じ。`_` を書くと**ラベル無し**になる。

```swift
func a(_ text: String) {}         // ラベル無し / 内部名 text          → a("KH-008")
func b(text: String) {}           // ラベル=内部名=text               → b(text: "KH-008")
func c(contents text: String) {}  // ラベル=contents / 内部名 text    → c(contents: "KH-008")
```

### 順番は常に固定
**ラベルがあってもなくても、引数の順番は定義した順に固定。** 入れ替えはできない。
```swift
func f(a: Int, b: Int) {}
f(a: 1, b: 2)   // ○
f(b: 2, a: 1)   // ✕ エラー
```
- 全部 `_` にすると呼ぶ時はラベル無しになるが、順番はやっぱり固定（`move(3, 7)` は x=3, y=7）
- **ラベルを付けても順番は自由にならない**

### JSのオブジェクト引数とは違う
JSの `fn({ text, size })` は**プロパティ名で決まり、順番は自由**。Swiftは**位置で決まり、順番は固定**。
ラベルは「何の値か」を分かりやすくするだけで、順番は変えられない。

### いつラベルを付ける／省略するか
個数ではなく**読みやすさ**で決める。Appleの基本は「**1個目は省略（`_`）、2個目以降はラベル**」。
```swift
func add(_ item: String, quantity: Int) {}   // 呼ぶ時: add("りんご", quantity: 3)
```

### なぜラベルと内部名を分けるのか
読み手が違うから。
- **ラベル**＝**呼び出しの文が自然に読める**ように選ぶ
- **内部名**＝**中身で意味が通る**ように選ぶ
```swift
func move(from source: Point, to destination: Point) { ... }
move(from: a, to: b)   // 呼ぶ側は "from a to b" と読める / 中では source, destination
```
同じ名前で足りる時は**1つだけ書く**。

### ラベルには日本語も使える
正確には、**関数名も内部名もラベルも、全部日本語にできる**。ただし普通はコード全体を英語で書く。
そのうえで、**ラベルだけ日本語**（関数名・内部名は英語）にすることもできる。ラベルは呼ぶ側の読みやすさのための名前なので、特にそうしやすい。
```swift
func addProduct(しな id: String, かず num: Int) {
    print("\(id) を \(num) 個")     // 中では英語の id / num を使う
}
addProduct(しな: "KH-008", かず: 1) // ← 呼ぶ時のラベルだけ日本語
```
**デメリット**（混ぜると摩擦が出るので、普通は英語に統一する）:
- Appleの資料・エラー・他人のコードは英語。日本語が混ざると読みにくい
- 日本語と英語が混ざると補完・検索・差分が使いにくい
- 人に見せる時・将来見返す時に困る

**ただし「絶対英語」ではなく慣習**。自分一人だけが読む個人アプリなら、**日本語ラベルもアリ**（読みやすさ優先）。
Appleの資料やサンプルをよく見て作るなら、英語に統一した方がスムーズ。

### コメントは日本語でOK（ラベルとは別）
| | 機械が見る？ | 日本語 |
| --- | --- | --- |
| **コメント** | 見ない（無視される） | ふつうに書く |
| **ラベル** | 見る（識別子） | 慣習的に英語 |

- コメントはコンパイラが無視する**人間向けの文章**。補完・型・実行に出ない → 日本語でOK
- ラベルは**コードの一部（識別子）**。呼び出し・補完・エラー・署名に出る → 混ぜると摩擦

### JSDoc（ドキュメントコメント）とは別
JSのJSDocは**コメント**。Swiftでいう **`///` のドキュメントコメント**が対応する。そこは日本語でOK。
**ラベルはそれとは別**で、呼び出し方そのものを変える**本物のコード**。

```js
// JS: JSDocはコメント。呼び方には影響しない
/**
 * 商品を追加する
 * @param {string} id 商品ID
 * @param {number} num 個数
 */
function addProduct(id, num) {}
addProduct("KH-008", 1)   // 順番で渡す
```

```swift
/// 商品を追加する
/// - Parameters:
///   - id: 商品ID
///   - num: 個数
func addProduct(しな id: String, かず num: Int) {}
addProduct(しな: "KH-008", かず: 1)   // ← ラベルは呼び方を変える本物のコード
```
- JSDoc（＝Swiftの `///`）は**説明を書く場所** → 日本語でOK
- ラベルは**呼び出し構文の一部** → 慣習的に英語

## 型を書けば入れられる
```swift
let a: Int? = nil        // OK
var b: Int? = nil        // OK。あとで値を入れられる
b = 5
```

## 型を書かないとエラー
```swift
// let c = nil           // エラー。nil だけでは何の型の nil か決まらない
```
- `nil` は「`Int?` の空」「`String?` の空」など、型ごとに別の空
- `: Int?` のように型を書いて、何の Optional かを決める

## 型が決まる場面では、型の指定なしで `nil` を渡せる
```swift
struct Product {
    let id: String
    let priceSats: Int?
}

let p = Product(id: "ST-003", priceSats: nil)    // priceSats は Int? と決まっているので OK
```
- `03_レジアプリの設計.md` のレッスン3の `priceSats: nil` がこの形
- 実際に使う `Product` は `base/Types.swift` に1つだけある。ここでは形の説明のために最小限を書いている

## `Int`（`?` なし）には入れられない
```swift
// let d: Int = nil      // エラー
```
- 「値なし」を許したい欄だけ `?` を付ける
- 在庫のように「管理しない種類がある」欄は `stock: Int?` になる（`base/Types.swift` の `Product`）

## 1. オーバーロード（同じ名前で引数の型違いの関数を2つ書く）
```swift
func show(_ s: String) {
    show([s])                  // 1つのときは配列にして、もう一方に任せる
}

func show(_ list: [String]) {
    for s in list {
        print(s)
    }
}

show("abc")                    // String の方が呼ばれる
show(["a", "b"])               // [String] の方が呼ばれる
```
- Swiftは、引数の型が違えば同じ名前の関数を複数書ける
- 呼ぶ側は、型を意識せず同じ名前で呼べる
- 実際の処理は片方（配列）に書き、もう片方は変換して渡すだけにする

## 2. 可変長引数（`String...`）
```swift
func show(_ items: String...) {
    for s in items {           // items は [String]
        print(s)
    }
}

show("abc")                    // 1つ
show("a", "b", "c")            // 複数
```
- 呼ぶ側は、値を `,` で並べて渡す
- 配列をそのまま渡すことはできない
```swift
let list = ["a", "b"]
// show(list)                  // エラー
```

## 3. enum を引数にする
```swift
enum StringOrList {
    case one(String)
    case many([String])
}

func show(_ x: StringOrList) {
    switch x {
    case .one(let s):     print(s)
    case .many(let list): list.forEach { print($0) }
    }
}

show(.one("abc"))
show(.many(["a", "b"]))
```
- 呼ぶ側が `.one(...)` / `.many(...)` と書く必要がある

## 4. ジェネリクス（共通の性質で受ける）
```swift
func count<T: Collection>(_ x: T) -> Int {
    x.count
}

print(count("abc"))            // 3（String は文字の集まり）
print(count(["a", "b"]))       // 2
```
- `String` も `[String]` も「Collection（要素の集まり）」という共通の性質を持つ
- 上の例は `String` を文字の集まりとして扱うため、`"abc"` が「1つの文字列」ではなく「3文字」として数えられる
- 「1つの文字列」と「文字列の配列」を区別したい場合には向かない
- ジェネリクスは `51_ジェネリクスを使う.md` で扱う

## 使い分け

| 方法 | 向いている場面 |
| --- | --- |
| オーバーロード | 呼ぶ側を `show("a")` / `show(["a"])` のままにしたい（TypeScript に最も近い） |
| 可変長引数 | 値を直接並べて渡す使い方が中心 |
| enum | 3つ以上の型を区別して扱いたい |
| ジェネリクス | 共通の性質で処理でき、型を区別しなくてよい |
