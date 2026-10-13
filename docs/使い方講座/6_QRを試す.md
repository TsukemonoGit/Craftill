# QRを試す（生成）

商品IDのQRを作る練習。`開発/4_最小構成やること.md` の「3. QR」の先取り。
**iPadのPlaygroundsにも、MacのXcodeにも同じコードで動く**ように `#if` で分岐してある。

> 試すのは **「ブック（Book）」** で作ったプレイグラウンド（「アプリ」ではない。詳細は `1_初心者メモ.md`）。
> アプリだと一番外側にコードを書けないので、このサンプルはブック向けです。

---

## 実行例（そのまま貼ってOK）
```swift
import SwiftUI
import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

#if os(macOS)
import AppKit
typealias QRImage = NSImage      // Mac の画像型
#else
import UIKit
typealias QRImage = UIImage      // iPad/iOS の画像型
#endif

#if os(iOS)
import PlaygroundSupport          // Playgroundsで表示する用
#endif

// ── QR画像を作る（共通の処理）────────────────
func makeQR(_ text: String) -> QRImage? {
    let filter = CIFilter.qrCodeGenerator()   // Apple公式のQR生成
    filter.message = Data(text.utf8)          // 中身 = 商品IDそのもの
    filter.correctionLevel = "M"              // 誤り訂正（L/M/Q/H）

    guard let ciImage = filter.outputImage else { return nil }

    // 生成直後は小さいので拡大（transformで拡大＝ぼやけない）
    let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))

    let context = CIContext()
    guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }

    #if os(macOS)
    return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width),
                                             height: CGFloat(cg.height)))
    #else
    return UIImage(cgImage: cg)
    #endif
}

// ── 画像を画面に出せる形に変える（ここだけ違う）──
func qrSwiftImage(_ img: QRImage) -> Image {
    #if os(macOS)
    return Image(nsImage: img)     // Mac
    #else
    return Image(uiImage: img)     // iPad/iOS
    #endif
}

// ── 画面 ────────────────────────────────
struct QRView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("KH-008").font(.headline)
            if let img = makeQR("KH-008") {
                qrSwiftImage(img)
                    .interpolation(.none)   // カリカリのまま
                    .resizable()
                    .frame(width: 250, height: 250)
            } else {
                Text("生成に失敗")
            }
        }
        .padding()
    }
}

// Playgroundsのときだけ表示（Xcodeのアプリでは不要）
#if os(iOS)
PlaygroundPage.current.setLiveView(QRView())
#endif
```

---

## macでは何が違う？（質問の答え）
「画像」を表す型がOSごとに違う。だから `#if os(macOS)` で切り替える。

| | iPad / iOS | Mac |
| --- | --- | --- |
| 画像の型 | `UIImage`（UIKit） | `NSImage`（AppKit） |
| SwiftUIで表示 | `Image(uiImage:)` | `Image(nsImage:)` |
| Playgroundsで表示 | `PlaygroundPage...setLiveView` | （Xcodeのアプリで使うので不要） |

- **QRを作る処理（CoreImage）はまったく同じ**。違うのは「画像の型」と「表示の仕方」だけ
- `typealias QRImage = ...` で、以降は `QRImage` と書けば両方で通る（同じコードを使い回せる）
- `#if` は「そのOSのときだけこの行をコンパイルする」という意味。Macでは `NSImage` 側、iPadでは `UIImage` 側だけが残る

---

## ポイント
- `CIFilter.qrCodeGenerator()` は**Apple公式**。`import CoreImage.CIFilterBuiltins` で使える
- 中身は `Data(text.utf8)` ＝**商品IDの文字列そのもの**（方針どおり）
- 小さいまま拡大すると**ぼやける**ので、`transform` で拡大 → 表示時に `.interpolation(.none)`
- 商品IDを変えたい時は `makeQR("KH-008")` の文字を変えるだけ

## 次にやること（後で）
- 読み取り（カメラ）は Apple公式の **Vision**（`VNDetectBarcodesRequest`）。カメラの許可が要る（`5_Xcodeでプロジェクト作成.md` 参照）
- 商品ID文字を画像の下に併記して、印刷して商品に貼る（`開発/4_最小構成やること.md`）
