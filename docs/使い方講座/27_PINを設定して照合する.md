# 27. PINを設定して照合する

元: `../siyou.md` A-11（認証）

**ゴール**: 初回起動時に**PINを設定**し、操作の前に**照合する**。
誤入力のときの挙動（失敗回数・ロック）も作る。
どの操作にPINが要るか／要らないかを一覧で確認する。

> 画面は出さず、`print` で結果を見る**純ロジック**の練習。**ブック（Book）**で作る。
> PINの保存場所は、練習として `UserDefaults` を使う。
> **レッスン同士は独立**。このファイルだけで完結する。

---

## 前提データ（このまま貼れば動く）

```swift
import Foundation

// PINの桁数（仮置き、Q21）
let pinLength = 4

// UserDefaultsのキー
let pinKey = "app.pin"
let failKey = "app.pin.failCount"

// 何回間違えたらロックするか（仮置き、Q21）
let maxFailures = 3
```

---

## 1. PINを設定する（初回起動）

```swift
/// PINを設定する。4桁の半角数字だけ受け付ける
func setPin(_ pin: String) -> String {
    let isAllDigits = pin.allSatisfy { $0.isNumber }
    if pin.count != pinLength || !isAllDigits {
        return "PINは\(pinLength)桁の数字にしてください"
    }
    UserDefaults.standard.set(pin, forKey: pinKey)
    UserDefaults.standard.set(0, forKey: failKey)   // 失敗回数もリセット
    return "PINを設定しました"
}

/// PINが設定済みか
func isPinSet() -> Bool {
    let saved = UserDefaults.standard.string(forKey: pinKey) ?? ""
    return !saved.isEmpty
}
```

- `pin.allSatisfy { $0.isNumber }` … 全部の文字が数字かどうか
- `UserDefaults.standard.set(...)` … 端末の簡単な保存場所に書く（`03_レッスン.md` の保存と同じ）

---

## 2. 照合する

```swift
/// 入力PINが保存済みPINと一致するか
func verifyPin(_ pin: String) -> Bool {
    let saved = UserDefaults.standard.string(forKey: pinKey) ?? ""
    return !saved.isEmpty && pin == saved
}
```

---

## 3. 誤入力の扱い

```swift
/// 失敗回数
func failCount() -> Int {
    UserDefaults.standard.integer(forKey: failKey)
}

/// ロック中か（規定回数失敗した）
func isLocked() -> Bool {
    failCount() >= maxFailures
}

/// 1回失敗を記録する
func recordFailure() {
    UserDefaults.standard.set(failCount() + 1, forKey: failKey)
}

/// 失敗回数を戻す（照合に成功したとき）
func resetFailures() {
    UserDefaults.standard.set(0, forKey: failKey)
}
```

`UserDefaults.standard.integer(forKey:)` … 整数として読む（未設定なら 0）。

---

## 4. PINが要る操作・要らない操作（A-11）

```swift
enum Operation {
    // ── PIN必須 ──
    case voidSale       // 販売取消
    case adjustStock    // 在庫手動調整
    case reimportCSV    // CSV再取り込み
    case export         // エクスポート
    case abortMixed     // sats確認済み併用会計の中断
    case setRefunded    // 返金済みフラグ設定

    // ── PIN不要 ──
    case addAdhoc       // 野良追加
    case addToCart      // カート追加
    case removeFromCart // カート削除

    var label: String {
        switch self {
        case .voidSale:       return "販売取消"
        case .adjustStock:    return "在庫手動調整"
        case .reimportCSV:    return "CSV再取り込み"
        case .export:         return "エクスポート"
        case .abortMixed:     return "sats確認済み併用会計の中断"
        case .setRefunded:    return "返金済みフラグ設定"
        case .addAdhoc:       return "野良追加"
        case .addToCart:      return "カート追加"
        case .removeFromCart: return "カート削除"
        }
    }

    var requiresPin: Bool {
        switch self {
        case .voidSale, .adjustStock, .reimportCSV, .export, .abortMixed, .setRefunded:
            return true
        case .addAdhoc, .addToCart, .removeFromCart:
            return false
        }
    }
}
```

---

## 5. PINゲートを通して実行する

```swift
/// 操作を実行する。PIN必須の操作は照合できたときだけ通す
func run(_ op: Operation, pin: String?) -> String {
    if !op.requiresPin {
        return "\(op.label): 実行しました（PIN不要）"
    }
    if isLocked() {
        return "\(op.label): ロック中（\(maxFailures)回失敗）"
    }
    guard let pin = pin else {
        return "\(op.label): PIN未入力のため中止"
    }
    if verifyPin(pin) {
        resetFailures()
        return "\(op.label): 実行しました（PIN確認OK）"
    } else {
        recordFailure()
        return "\(op.label): PINが違います（失敗\(failCount())回）"
    }
}

// PIN設定前は、初期投入（種類定義・商品マスタの取り込み）のみ行える（仮置き）
func isInitialImportAllowed() -> Bool {
    return !isPinSet()
}
```

---

## 6. 動かしてみる

```swift
// 練習用に毎回まっさらから始める
UserDefaults.standard.removeObject(forKey: pinKey)
UserDefaults.standard.removeObject(forKey: failKey)

// 初回起動
print("PIN設定済み?", isPinSet())   // false
print(setPin("12"))                 // PINは4桁の数字にしてください
print(setPin("1234"))               // PINを設定しました
print("PIN設定済み?", isPinSet())   // true
print("初期投入してよい?", isInitialImportAllowed())  // false

// 操作を実行する
print(run(.addToCart, pin: nil))    // PIN不要 → 実行
print(run(.voidSale,  pin: nil))    // PIN未入力 → 中止
print(run(.voidSale,  pin: "0000")) // 失敗1回
print(run(.voidSale,  pin: "1111")) // 失敗2回
print(run(.voidSale,  pin: "1234")) // 実行（PIN確認OK）→ 失敗リセット
print(run(.export,    pin: "1234")) // 実行（PIN確認OK）

// 誤入力を続けてロックさせる
print(run(.adjustStock, pin: "0000"))  // 失敗1回
print(run(.adjustStock, pin: "0000"))  // 失敗2回
print(run(.adjustStock, pin: "0000"))  // 失敗3回
print(run(.export,      pin: "1234"))  // ロック中 → 正しいPINでも通さない
```

**できた合図**:
```
PIN設定済み? false
PINは4桁の数字にしてください
PINを設定しました
PIN設定済み? true
初期投入してよい? false
カート追加: 実行しました（PIN不要）
販売取消: PIN未入力のため中止
販売取消: PINが違います（失敗1回）
販売取消: PINが違います（失敗2回）
販売取消: 実行しました（PIN確認OK）
エクスポート: 実行しました（PIN確認OK）
在庫手動調整: PINが違います（失敗1回）
在庫手動調整: PINが違います（失敗2回）
在庫手動調整: PINが違います（失敗3回）
エクスポート: ロック中（3回失敗）
```

---

## 7. PINは平文で置かない考え方（軽く）

ここでは練習として `UserDefaults` に**そのまま**保存した。実運用では次を意識する。

- PINそのものではなく、**ハッシュ（一方向の変換）**にしてから保存するのが望ましい
- さらに安全にするなら、端末の保護領域 **Keychain** に置く（`UserDefaults` はバックアップに含まれやすい）
- 桁数・忘れたときの復旧方法は **Q21（未確定）**。PIN設定前は**初期投入のみ**行える（A-11）

---

## まとめ

- 初回起動で PIN（4桁の半角数字）を設定し、`UserDefaults` に保存する
- 誤入力は**失敗回数を数え**、規定回数で**ロック**。成功したら失敗回数を戻す
- PIN必須: **販売取消・在庫手動調整・CSV再取り込み・エクスポート・sats確認済み併用会計の中断・返金済みフラグ設定**
- PIN不要: **野良追加・カート追加・カート削除**
- 実運用では**平文保存を避ける**（ハッシュ／Keychain）。仕様の詳細は Q21
