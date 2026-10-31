import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// ════════════════════════════════════════════════════════════
// 実行時に登録した商品写真（編集画面の「写真を追加」）
//
// カメラ撮影・写真ライブラリ・ファイル選択のどれも同じ経路で保存する。
// - アプリ内コピー: Application Support/Craftill/Images/<商品ID>.jpg
//   外部フォルダが未設定でもレジに表示するためのコピー。
// - 外部フォルダ: ProductImageFolder で選んだ originals/ など。
//   ウェブサイトの画像ビルド（scripts/build_images.py）が読む。
// ════════════════════════════════════════════════════════════

enum ProductImageError: LocalizedError {
    case emptyName
    case externalFolderUnavailable
    case externalWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "画像のファイル名が空です"
        case .externalFolderUnavailable:
            return "選択した画像フォルダが見つかりません。設定を確認してください。"
        case .externalWriteFailed(let detail):
            return "端末内には保存しましたが、選択したフォルダに書き出せませんでした: \(detail)"
        }
    }
}

enum ProductImageStore {
    /// アプリ内の表示用コピーの保存先。
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

    /// 表示に使う URL。外部フォルダを優先し、無ければアプリ内コピー。
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

    /// アプリ内コピーまたは外部フォルダに実体があるか（同梱画像は含めない）。
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

    /// アプリ内コピーだけを読む（外部フォルダへの書き出し用）。
    static func loadLocalData(fileName: String) -> Data? {
        guard !fileName.isEmpty else { return nil }
        return try? Data(contentsOf: localURL(fileName: fileName))
    }

    /// アプリ内コピーと外部フォルダの両方へ保存する。
    /// 外部フォルダへの書き出しに失敗しても、アプリ内コピーは残る。
    static func save(_ data: Data, fileName: String) throws {
        guard !fileName.isEmpty else { throw ProductImageError.emptyName }

        // 1. レジ表示用のコピー
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        try data.write(to: localURL(fileName: fileName), options: .atomic)

        // 2. ウェブサイトの画像ビルド用コピー
        if let external = externalURL(fileName: fileName) {
            let folder = external.deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: folder.path) else {
                throw ProductImageError.externalFolderUnavailable
            }
            do {
                try data.write(to: external, options: .atomic)
            } catch {
                throw ProductImageError.externalWriteFailed(error.localizedDescription)
            }
        }
    }

    /// アプリ内コピーと外部フォルダの両方から削除する。
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
