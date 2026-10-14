# レッスン23: 種類定義CSVを読み込む

元: `../siyou.md` A-1

このレッスンは**ブック（Book）**で進めます。  
ここでは「種類定義CSV」の読み込みと検証の考え方を、純ロジックで試します。  
**レッスン同士は独立**です。このファイルだけで完結します。

---

## 前提データ

まず、このレッスンに必要な型・データを全部定義しておきます。

```swift
// 在庫の扱い（種類ごとに決まる）
enum StockMode: String {
    case counted = "counted"   // 数量管理型
    case unique  = "unique"    // 一点物型
    case none    = "none"      // 在庫管理なし型
}

// 商品1個分のデータ（レッスンの試作用）
struct Product {
    let id: String        // 商品ID 例: "KH-008"
    let name: String      // 商品名 例: "キーホルダー 08"
    let priceJpy: Int     // 円価格 例: 800
    let priceSats: Int?   // sats価格（空なら nil）
    var stock: Int?       // 在庫（uniqueは0/1、countedは0以上、noneはnil）
}

// 種類定義（種類定義CSVに対応するデータ）
struct ProductType {
    let typeId: String           // type_id（例: "sticker"）
    let name: String             // 表示名（例: "ステッカー"）
    let idPrefix: String         // id_prefix（例: "ST"）
    let idDigits: Int            // id_digits（例: 3）
    let stockMode: StockMode     // stock_mode
    let attrLabel1: String?      // attr_label_1
    let attrLabel2: String?      // attr_label_2
    let attrLabel3: String?      // attr_label_3
}

// テスト用の商品リスト（DBのサンプルに合わせる）
let products: [Product] = [
    Product(id: "ST-001", name: "ステッカー まる",   priceJpy: 300, priceSats: 500,  stock: 10),
    Product(id: "ST-002", name: "ステッカー さんかく", priceJpy: 300, priceSats: 500,  stock: 10),
    Product(id: "ST-003", name: "ステッカー しかく", priceJpy: 300, priceSats: nil,  stock: 10),
    Product(id: "KH-001", name: "キーホルダー 01",   priceJpy: 800, priceSats: 1200, stock: 1),
    Product(id: "KH-008", name: "キーホルダー 08",   priceJpy: 800, priceSats: 1200, stock: 1),
]

// テスト用の種類定義リスト（DBのサンプルに合わせる）
var productTypes: [ProductType] = [
    ProductType(
        typeId: "sticker",
        name: "ステッカー",
        idPrefix: "ST",
        idDigits: 3,
        stockMode: .counted,
        attrLabel1: "色",
        attrLabel2: "模様",
        attrLabel3: nil
    ),
    ProductType(
        typeId: "keyholder",
        name: "キーホルダー",
        idPrefix: "KH",
        idDigits: 3,
        stockMode: .unique,
        attrLabel1: "色",
        attrLabel2: "模様",
        attrLabel3: nil
    )
]
```

---

## 1. 種類定義CSVの列

**種類定義CSV**（`product_types`）の列（順序は問わず、列名で識別します）。

| 列 | 必須 | 値・規則 |
| --- | --- | --- |
| `type_id` | 必須 | 半角英数字とアンダースコア。一意 |
| `name` | 必須 | 表示名。空は不可 |
| `id_prefix` | 必須 | 半角英大文字・数字。ハイフンを含まない。種類間で一意 |
| `id_digits` | 必須 | 1以上の整数 |
| `stock_mode` | 必須 | `counted`／`unique`／`none` |
| `attr_label_1`〜`attr_label_3` | 任意 | 属性ラベル。左から詰める（`attr_label_2` が空で `attr_label_3` に値がある場合はエラー） |

**ポイント**: CSV取り込みでは**1行でもエラーがあれば全体を取り込まない**。エラーは「行番号・列名・理由」で一覧にします。

---

## 2. 検証ルールを考える（重要な点だけ）

取り込み時にチェックする主なルール：

- `type_id` が空でないか
- `type_id` に使える文字は**半角英数字とアンダースコア**か（簡易チェック）
- `type_id` の**重複**がないか
- `name` が空でないか
- `id_prefix` が空でないか。ハイフン`-`を含まないか
- `id_prefix` に使える文字は**半角英大文字・数字**か（簡易チェック）
- `id_prefix` の**重複**（種類間で一意）がないか
- `id_digits` が**1以上の整数**か
- `stock_mode` が `counted` / `unique` / `none` のいずれかか
- 属性ラベルは**左から詰める**。つまり `attr_label_2` が空（nil/空文字）で、`attr_label_3` に値がある場合は**エラー**

**できた合図**: これらのルールを「読むだけ」で頭に入れておく。

---

## 3. ブックで検証関数を試す

簡単な形で、属性ラベルの「左詰め」ルールだけまず試してみましょう。

```swift
// 属性ラベルが左詰めになっているかチェック
// attr2が空で attr3に値がある → false
func isAttrLabelsPacked(_ l1: String?, _ l2: String?, _ l3: String?) -> Bool {
    let v1 = (l1 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let v2 = (l2 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let v3 = (l3 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    
    // attr_label_2 が空で attr_label_3 に値がある場合はエラー
    if v2.isEmpty && !v3.isEmpty {
        return false
    }
    return true
}

print(isAttrLabelsPacked("色", "模様", nil))   // true（正しい）
print(isAttrLabelsPacked("色", nil, "模様"))   // false（左詰めではない → エラー）
print(isAttrLabelsPacked(nil, nil, nil))     // true（空でもOK）
print(isAttrLabelsPacked("色", "", "模様"))    // false（空文字も空扱い）
```

- `.trimmingCharacters(in: .whitespacesAndNewlines)` で前後の空白を取り除く（CSVの「値の前後の空白は取り除く」に対応）
- 「空かどうか」は `isEmpty` で判定します

**できた合図**: 2番目と4番目が `false` と出る。

---

## 4. id_prefix・id_digits・stock_mode をチェックする

次に、`id_prefix`（重複・不正文字）、`id_digits`（1以上の整数）、`stock_mode`（`counted/unique/none`）を簡易にチェックしてみます。

```swift
func isValidStockMode(_ s: String) -> Bool {
    switch s {
    case "counted", "unique", "none":
        return true
    default:
        return false
    }
}

func isValidIdPrefixFormat(_ p: String) -> Bool {
    // 空は別でチェック
    if p.isEmpty { return false }
    // ハイフンを含まない
    if p.contains("-") { return false }
    // 半角英大文字・数字だけか（簡易）
    let allowed = CharacterSet.uppercaseLetters.union(.decimalDigits)
    let set = CharacterSet(charactersIn: p)
    return allowed.isSuperset(of: set)
}

func isValidIdDigits(_ d: Int) -> Bool {
    return d >= 1  // 1以上の整数
}

print(isValidStockMode("counted"))  // true
print(isValidStockMode("other"))    // false
print(isValidIdPrefixFormat("ST"))  // true
print(isValidIdPrefixFormat("st"))  // false（小文字 → NG）
print(isValidIdPrefixFormat("S-T")) // false（ハイフンあり → NG）
print(isValidIdDigits(3))           // true
print(isValidIdDigits(0))           // false
```

**ポイント**: 実際のCSV取り込みでは「数字の文字列」をIntに変換してからチェックします。

---

## 5. ProductType を作って確認

冒頭で定義した `ProductType` とサンプルデータを使って、今の定義が正しい形か確認してみましょう。

```swift
// サンプルの種類定義を表示
for pt in productTypes {
    print("typeId:\(pt.typeId), prefix:\(pt.idPrefix), digits:\(pt.idDigits), mode:\(pt.stockMode.rawValue)")
    print("  attrs: \(pt.attrLabel1 ?? "-") / \(pt.attrLabel2 ?? "-") / \(pt.attrLabel3 ?? "-")")
}
```

**できた合図**: `sticker`（ST・3・counted）と `keyholder`（KH・3・unique）が出て、属性ラベルが色／模様になっているのが確認できる。

---

## まとめ

- 種類定義CSVは**種類（ProductType）そのものの定義**を読み込みます
- **type_idの重複・id_prefixの重複**は種類間での一意性チェック
- **属性ラベルは左詰め**（2が空で3に値 → エラー）
- `id_digits` は**1以上の整数**、`stock_mode` は `counted/unique/none` の3択
- 取り込み時は**1行でもエラーがあれば全体を取り込まない**、という方針です

このレッスンでは**検証の考え方**をブックで試しました。エラーは「行番号・列名・理由」の構造体でまとめて一覧表示すると分かりやすくなります。
