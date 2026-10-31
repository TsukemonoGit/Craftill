import Foundation

// ════════════════════════════════════════════════════════════
// 商品写真の外部保存先（リポジトリの originals/ など）
//
// カメラ撮影・ファイル選択のどちらも、ここで選んだフォルダへ
// 「商品ID.jpg」で保存する。フォルダはセキュリティスコープ付き
// ブックマークとして UserDefaults に保存し、次回起動時も使う。
// ════════════════════════════════════════════════════════════

enum ProductImageFolder {
    private static let bookmarkKey = "craftill.productImageFolderBookmark"

    /// 現在の外部フォルダ。`activate()` または `set(url:)` で解決する。
    /// UI からのみ触る想定（メインスレッド）。
    private(set) static var url: URL?

    private static var isAccessing = false

    /// 外部フォルダが設定されているか（解決に失敗した場合も true）。
    static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// 起動時に呼ぶ。保存済みブックマークを解決してアクセスを開始する。
    static func activate() {
        guard url == nil, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        resolve(data)
    }

    /// ユーザーが選んだフォルダを保存する。
    static func set(url newURL: URL) throws {
        stopAccess()
        let started = newURL.startAccessingSecurityScopedResource()
        defer { if started { newURL.stopAccessingSecurityScopedResource() } }

        let bookmark = try makeBookmark(for: newURL)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        resolve(bookmark)
    }

    /// 外部フォルダの設定を解除し、アプリ内保存に戻す。
    static func clear() {
        stopAccess()
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        url = nil
    }

    private static func resolve(_ data: Data) {
        var stale = false
        do {
            let resolved: URL
            #if os(macOS)
            resolved = try URL(resolvingBookmarkData: data,
                               options: [.withSecurityScope, .withoutUI],
                               relativeTo: nil,
                               bookmarkDataIsStale: &stale)
            #else
            resolved = try URL(resolvingBookmarkData: data,
                               options: [.withoutUI],
                               relativeTo: nil,
                               bookmarkDataIsStale: &stale)
            #endif

            url = resolved
            isAccessing = resolved.startAccessingSecurityScopedResource()

            // フォルダが移動・改名されても、解決できた URL でブックマークを作り直す。
            if stale, let refreshed = try? makeBookmark(for: resolved) {
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
            }
        } catch {
            url = nil
            isAccessing = false
        }
    }

    private static func makeBookmark(for url: URL) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(options: .withSecurityScope,
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil)
        #else
        return try url.bookmarkData(options: .minimalBookmark,
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil)
        #endif
    }

    private static func stopAccess() {
        if isAccessing, let url {
            url.stopAccessingSecurityScopedResource()
        }
        isAccessing = false
    }
}
