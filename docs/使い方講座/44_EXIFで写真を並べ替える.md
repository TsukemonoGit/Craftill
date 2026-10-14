# EXIFで写真を並べ替える

元: `../siyou.md` A-18

写真に商品IDを採番するとき、**どの順に番号を振るか**を決める練習。
順序は `../siyou.md` A-18 の採番規則そのもの:

1. **撮影日時（EXIF）の昇順**
2. EXIFがなければ**ファイルの更新日時**
3. それも同じなら**ファイル名の昇順**

> このレッスンは**純ロジック**なので、iPadの **ブック（Book）** にそのまま貼って動く。
> EXIFの読み取りは `ImageIO`（Mac/iOSのフレームワーク）を使うが、ファイルが読めない環境向けに
> **手入力したデータでの例を主**にする。

---

## 前提データ

```swift
import Foundation

/// 採番の対象になる写真1枚
struct PhotoFile {
    let fileName: String      // ファイル名 例: "IMG_1234.HEIC"
    let exifDate: Date?       // EXIFの撮影日時（無ければ nil）
    let modifiedDate: Date?   // ファイルの更新日時（無ければ nil）
}

/// "2026-10-13 12:00:00" のような文字列を Date にする小道具
func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.date(from: s)!   // 練習用のデータは必ず正しい形なので!
}
```

`Date?` の `?` は「あるかも / 空っぽかも」（`1_初心者メモ.md` のオプショナル）。

---

## 手入力のデータで試す

EXIFがある写真、更新日時だけの写真、日時がまったく無い写真を混ぜてある。

```swift
let photos: [PhotoFile] = [
    PhotoFile(fileName: "b.jpg", exifDate: date("2026-10-13 12:00:00"), modifiedDate: date("2026-10-13 20:00:00")),
    PhotoFile(fileName: "a.jpg", exifDate: nil,                            modifiedDate: date("2026-10-13 10:00:00")),
    PhotoFile(fileName: "d.jpg", exifDate: date("2026-10-13 12:00:00"), modifiedDate: nil),
    PhotoFile(fileName: "e.jpg", exifDate: date("2026-10-13 09:00:00"), modifiedDate: date("2026-10-13 08:00:00")),
    PhotoFile(fileName: "c.jpg", exifDate: nil,                            modifiedDate: nil),
]
```

---

## 並べ替えのキー（基準になる日時）を決める

```swift
/// 採番に使う日時を1つ決める。
/// EXIFがあればそれを、無ければ更新日時を使う。
/// どちらも無いときは「最後尾」に来るよう、いちばん未来の日時（distantFuture）にする。
func sortDate(_ photo: PhotoFile) -> Date {
    return photo.exifDate ?? photo.modifiedDate ?? .distantFuture
}
```

- `photo.exifDate ?? photo.modifiedDate` … `??` は「左が空っぽなら右を使う」（`1_初心者メモ.md`）。
- `.distantFuture` … Dateの「果てしなく先」。日時が無い写真を最後に置くための目印。

---

## 並べ替えの関数

```swift
/// 採番順に並べ替える。
/// 1. 基準の日時の昇順  2. 同じ日時ならファイル名の昇順
func sortedForNumbering(_ photos: [PhotoFile]) -> [PhotoFile] {
    return photos.sorted { a, b in
        let da = sortDate(a)
        let db = sortDate(b)
        if da != db {
            return da < db              // 日時が違う → 早い方が先
        }
        return a.fileName < b.fileName  // 日時が同じ → ファイル名の昇順
    }
}
```

- `.sorted { a, b in ... }` … 配列を並べ替える。`a` と `b` を比べて、`a` が先なら `true`。
- **同じ日時のときだけ**ファイル名で決める（`b.jpg` と `d.jpg` の例）。

---

## 表示して確認する

```swift
let ordered = sortedForNumbering(photos)

var number = 1
for photo in ordered {
    // どの基準で並んだかを添える
    let reason: String
    if photo.exifDate != nil {
        reason = "EXIF"
    } else if photo.modifiedDate != nil {
        reason = "更新日時"
    } else {
        reason = "日時なし"
    }
    let id = String(format: "KH-%03d", number)
    number += 1
    print("\(id)  \(photo.fileName)  (\(reason))")
}
```

**できた合図**:
```
KH-001  e.jpg  (EXIF)
KH-002  a.jpg  (更新日時)
KH-003  b.jpg  (EXIF)
KH-004  d.jpg  (EXIF)
KH-005  c.jpg  (日時なし)
```
- `e`(09:00) → `a`(更新日時10:00) → `b`(12:00) → `d`(12:00) の順。
- `b` と `d` は同じ12:00なので**ファイル名順**（b → d）。
- `c` は日時が無いので最後。

---

## EXIFを実際に読む場合（ImageIO）

写真ファイルからEXIFの撮影日時を取るには `ImageIO` を使う。
`CGImageSourceCopyPropertiesAtIndex` でプロパティを取り、`Exif` の中の `DateTimeOriginal` を読む。

```swift
#if canImport(ImageIO)
import ImageIO

/// 画像ファイルのEXIF撮影日時を読む。読めなければ nil。
func exifDate(of url: URL) -> Date? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
          let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else {
        return nil
    }
    // EXIFの日時は "2026:10:13 12:00:00" の形（区切りが「:」と「 」）
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return f.date(from: text)
}
#endif
```

- `CGImageSourceCopyPropertiesAtIndex` … 画像の情報（EXIFを含む）を取り出す。
- `kCGImagePropertyExifDateTimeOriginal` … 「撮影日時」のキー。
- EXIFの書式は `yyyy:MM:dd HH:mm:ss`。`date(_:)` の書式と違う点に注意。

```swift
// 使うときは PhotoFile に詰め直す
#if os(macOS)
let photosFromFiles: [PhotoFile] = []   // Mac では url から exifDate(of:) と更新日時を取る
#else
let photosFromFiles: [PhotoFile] = []   // iPad/iOS はアクセスできる範囲が限られる
#endif
```

---

## 覚えておくこと

- 順序は「**EXIF → 更新日時 → ファイル名**」の2段＋最後の決め手（`../siyou.md` A-18）。
- この順序は**新規採番にだけ**効く。採番したIDは後から変えない。
- `??` を使って「基準の日時」を1本にまとめると、`sorted` の比較が短く書ける。
- EXIFの日時書式（`:` 区切り）と、表示用の書式は別物。読み込むときに変換する。
