import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// ════════════════════════════════════════════════════════════
// 実行時に登録した商品写真（編集画面の「写真を追加」）
// ビルド時に同梱する画像（A-17）より優先して表示する。
// 保存先は Application Support/Craftill/Images/<商品ID>.jpg。
// ════════════════════════════════════════════════════════════

enum ProductImageError: LocalizedError {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName: return "画像のファイル名が空です"
        }
    }
}

enum ProductImageStore {
    static var directory: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true))
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("Craftill", isDirectory: true)
                   .appendingPathComponent("Images", isDirectory: true)
    }

    static func url(fileName: String) -> URL {
        // `image_ref` にディレクトリ成分が入っていても、保存先の外へは書き出さない。
        directory.appendingPathComponent((fileName as NSString).lastPathComponent)
    }

    static func exists(fileName: String) -> Bool {
        guard !fileName.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: url(fileName: fileName).path)
    }

    static func loadData(fileName: String) -> Data? {
        guard !fileName.isEmpty else { return nil }
        return try? Data(contentsOf: url(fileName: fileName))
    }

    static func save(_ data: Data, fileName: String) throws {
        guard !fileName.isEmpty else { throw ProductImageError.emptyName }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(fileName: fileName), options: .atomic)
    }

    static func delete(fileName: String) throws {
        guard !fileName.isEmpty else { return }
        let target = url(fileName: fileName)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
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
}
