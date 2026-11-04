import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// ════════════════════════════════════════════════════════════
// 実行時に登録した商品写真（編集画面の「写真を追加」）
//
// カメラ撮影・写真ライブラリ・ファイル選択のどれも同じ経路で保存する。
// 保存先は写真追加の前に必ず選ぶ外部フォルダ（originals/ など）だけ。
// ウェブサイトの画像ビルド（scripts/build_images.py）がそのフォルダを読む。
// 旧版が Application Support に残したコピーは読み取り専用で残し、
// 「画像の保存先」画面から新しいフォルダへまとめて書き出せる。
// ════════════════════════════════════════════════════════════

enum ProductImageError: LocalizedError {
    case emptyName
    case folderNotConfigured
    case externalFolderUnavailable
    case externalWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "画像のファイル名が空です"
        case .folderNotConfigured:
            return "画像の保存先フォルダが未設定です。「画像の保存先」でフォルダを選んでください。"
        case .externalFolderUnavailable:
            return "選択した画像フォルダが見つかりません。「画像の保存先」で選び直してください。"
        case .externalWriteFailed(let detail):
            return "選択したフォルダに書き出せませんでした: \(detail)"
        }
    }
}

enum ProductImageStore {
    /// 旧版が表示用コピーを置いていたアプリ内領域。
    /// 現在は書き込まず、移行前の写真の読み取り・削除にだけ使う。
    static var localDirectory: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("Craftill", isDirectory: true)
                   .appendingPathComponent("Images", isDirectory: true)
    }

    static func localURL(fileName: String) -> URL {
        localDirectory.appendingPathComponent(sanitized(fileName))
    }

    /// 外部フォルダ（originals/ など）の URL。未設定なら nil。
    static func externalURL(fileName: String) -> URL? {
        guard let folder = ProductImageFolder.url else { return nil }
        return folder.appendingPathComponent(sanitized(fileName))
    }

    /// 表示に使う URL。外部フォルダを優先し、無ければ旧版のアプリ内コピー。
    static func displayURL(fileName: String) -> URL? {
        guard !fileName.isEmpty else { return nil }
        if let external = externalURL(fileName: fileName),
           FileManager.default.isReadableFile(atPath: external.path) {
            return external
        }
        let local = localURL(fileName: fileName)
        if FileManager.default.isReadableFile(atPath: local.path) {
            return local
        }
        return nil
    }

    static func exists(fileName: String) -> Bool {
        displayURL(fileName: fileName) != nil
    }

    /// 外部フォルダまたは旧版のアプリ内コピーに実体があるか（同梱画像は含めない）。
    static func hasRuntimeImage(fileName: String) -> Bool {
        guard !fileName.isEmpty else { return false }
        if let external = externalURL(fileName: fileName),
           FileManager.default.fileExists(atPath: external.path) {
            return true
        }
        return FileManager.default.fileExists(atPath: localURL(fileName: fileName).path)
    }

    static func loadData(fileName: String) -> Data? {
        guard !fileName.isEmpty else { return nil }
        if let external = externalURL(fileName: fileName),
           let data = try? Data(contentsOf: external) {
            return data
        }
        return loadLocalData(fileName: fileName)
    }

    /// 旧版が残したアプリ内コピーだけを読む（フォルダへの書き出し用）。
    static func loadLocalData(fileName: String) -> Data? {
        guard !fileName.isEmpty else { return nil }
        return try? Data(contentsOf: localURL(fileName: fileName))
    }

    /// 保存先フォルダへ保存する。フォルダは写真追加の前に必ず選ぶため、
    /// 未設定・到達不能のまま保存しようとした場合はエラーにする。
    static func save(_ data: Data, fileName: String) throws {
        guard !fileName.isEmpty else { throw ProductImageError.emptyName }
        guard let external = externalURL(fileName: fileName) else {
            throw ProductImageError.folderNotConfigured
        }

        let folder = external.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw ProductImageError.externalFolderUnavailable
        }
        do {
            try data.write(to: external, options: .atomic)
        } catch {
            throw ProductImageError.externalWriteFailed(error.localizedDescription)
        }

        // 旧版のアプリ内コピーが古いまま残ると、一括書き出しで古い写真が
        // 新しい写真を上書きする原因になるため、保存に成功した時点で消す。
        let local = localURL(fileName: fileName)
        if FileManager.default.fileExists(atPath: local.path) {
            try? FileManager.default.removeItem(at: local)
        }
    }

    /// 外部フォルダと旧版のアプリ内コピーの両方から削除する。
    static func delete(fileName: String) throws {
        guard !fileName.isEmpty else { return }

        if let external = externalURL(fileName: fileName),
           FileManager.default.fileExists(atPath: external.path) {
            try FileManager.default.removeItem(at: external)
        }

        let local = localURL(fileName: fileName)
        if FileManager.default.fileExists(atPath: local.path) {
            try FileManager.default.removeItem(at: local)
        }
    }

    /// EXIF の向きを反映し、長辺 `maxPixel` に縮小した JPEG を作る。
    /// 写真アプリ・ファイル選択・カメラのどれから来たデータでも同じ形式にそろえる。
    static func normalizedJPEG(from data: Data, maxPixel: CGFloat = 1600) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// EXIF の向きを反映した CGImage を作る（切り取り UI 用）。
    static func decodedCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// CGImage を JPEG 化し、長辺 `maxPixel` にそろえる。
    static func jpegData(from image: CGImage, maxPixel: CGFloat = 1600, quality: CGFloat = 0.85) -> Data? {
        let longEdge = CGFloat(max(image.width, image.height))
        let scale = min(1, maxPixel / max(1, longEdge))
        let targetW = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let targetH = max(1, Int((CGFloat(image.height) * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        guard let scaled = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, scaled,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// プレビュー用に縮小した CGImage を作る。
    static func cgImage(from data: Data, maxPixel: CGFloat = 320) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func sanitized(_ fileName: String) -> String {
        // `image_ref` にディレクトリ成分が入っていても、保存先の外へは書き出さない。
        (fileName as NSString).lastPathComponent
    }
}
