# Macへ ― Xcodeプロジェクト作成

> **前:** [他言語から見たSwift](05_他言語から見たSwift.md) ｜ **入口:** [はじめに](00_はじめに.md) ｜ **次:** [追加レッスン](07_追加レッスン.md)

Macが届いたら最初に読むファイルです。
マルチプラットフォームのAppテンプレートでプロジェクトを作り、macOSを実行先にします。
カメラの許可、無料署名、ファイルの分け方も扱います。

## マルチプラットフォームとは
**1つのプロジェクトで、複数のプラットフォーム（iOS/iPadOS/macOS/tvOS/watchOS/visionOS）向けにビルドできる**テンプレート。共通コードを1つ書けば、各プラットフォームで動く。

## なぜこれで作るのか（今回の事情）
- 決定では **macOSのみ**（iPad版は当面作らない = Q19を先送り）
- でもマルチプラットフォームで作っておけば、**Supported Destinations を macOS だけ** にすればよく、**後でiPadを足したくなった時に追加するだけ**
- つまり「今はMacだけ、将来iPadの可能性も潰さない」が両立できる

---

## 作成手順
1. Xcode → **File > New > Project...**
2. 上部のプラットフォーム選択で **「Multiplatform」→「App」**
3. 入力:
   - **Product Name**: レジアプリの名前（例 `Reji`）
   - **Team**: 自分のApple ID（無料。後からでもよい）
   - **Organization Identifier**: 逆ドメイン風（例 `com.example`）
   - **Interface**: **SwiftUI**
   - **Language**: **Swift**
4. 保存場所を選んで作成
5. プロジェクト設定 → **TARGETS → General → 「Supported Destinations」** で対応プラットフォームを調整
   - **macOSを残し、使わないもの（iOS等）は外す**（今はmacOSだけ）
   - 実行先（Run destination）を **「My Mac」** にする（Simulatorではなく）

## コードの共通 / 分岐
- SwiftUIの部分は**そのまま全プラットフォームで共通**
- プラットフォームで違う所だけ `#if` で分ける:
```swift
#if os(macOS)
    // Mac用の処理
#elseif os(iOS)
    // iPad用の処理
#endif
```

---

## カメラ（QR読取）の注意
QRの**生成・読み取りのコード自体は共通**（CoreImage / Vision）。違うのは**カメラの許可の部分**。
- **macOS**: 既定でApp SandboxがON。カメラを使うには
  - Signing & Capabilities → **App Sandbox → Camera にチェック**（entitlement `com.apple.security.device.camera`）
  - Info に **`NSCameraUsageDescription`**（日本語の説明文）を追加
  - ※ 個人利用で配布しないなら、App Sandbox自体をOFFにする手もある（その場合はInfoだけで動く）
- **iOS/iPadOS**: Info に `NSCameraUsageDescription` を追加

**つまずき**: カメラ起動でクラッシュしたら、ほぼ**許可の設定漏れ**（entitlement か Info.plist）。
→ `37_QRをカメラで読み取る.md`

---

## 署名（無料）
- Team に**無料のApple ID**を選ぶ。有料のDeveloper Programは**不要**（決定）
- macOSは「Sign to Run Locally」で動く
- **署名の有効期限は7日**として扱う（決定）。切れたら再ビルド/再インストール
- 営業日の前に再導入する日取りを確保する（`../../開発/7_注意点と運用.md`）

---

## ファイルの分け方（自由）
- iPadで書いた `.swift` を**そのまま追加**できる
- 例: `Product.swift`（データの形）/ `Cart.swift`（処理）/ `RegisterView.swift`（UI）/ `QR.swift`（QR生成・読取）
- Svelteと違い「これがUIファイル」という決まりは無い（`.svelte`/`.ts` の分けは無い）
- 型は `base/Types.swift` を1ファイルとして追加すると、レッスンとの差分が減る

---

## iPadとMacの役割（どこで何ができるか）
| やること | iPad（Playgrounds） | Mac（Xcode） |
| --- | --- | --- |
| 部品（ロジック・UI）を書く | ○ | ○ |
| QRを画像として生成 | ○ | ○ |
| カメラでQRを読み取る（実地） | △（練習ページ不可。Appなら理論上可だが手間） | ○ |
| **macOSアプリとして完成・実行** | × | ○ |
| iPadアプリとして完成・実行 | ○ | ○ |

- QRはApple**公式フレームワーク**（`import` するだけ、インストール不要）
  - 生成: CoreImage（`CIFilter.qrCodeGenerator`）／読取: Vision（`VNDetectBarcodesRequest`）かAVFoundation
- iPadで書いたコードは**Macへコピーするだけ**でそのまま使える

---

## 参考
- 土台の作業: `../../開発/4_最小構成やること.md` の「1. 土台」
- 環境の決定: `../../開発/1_決定事項.md` 開発環境
- QR生成の練習: `../06_QRを試す.md`
- 画面の構成: `../../開発/5_画面構成.md`
