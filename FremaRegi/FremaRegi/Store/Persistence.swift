import Foundation

// ════════════════════════════════════════════════════════════
// データの永続化（A-3 状態の保持／A-16・C-6 #2/#3/#4）
// すべてのテーブルを JSON ファイルとして端末内に保存する。
// アプリ切替・終了・再起動・スリープ復帰後に直前の状態を復元する。
// （仕様の A-7「現在庫の正」は products.stock。ログとの自己点検もここで行う・A-19-1）
// ════════════════════════════════════════════════════════════

/// レジが保持する全データ（端末内DB相当）
struct RegistryData: Codable, Equatable {
    var groups: [ProductGroup] = []
    var types: [ProductType] = []
    var inventory: [Product] = []
    var sales: [Sale] = []
    var items: [SaleItem] = []
    var movements: [StockMovement] = []
    var syncLog: [SyncLogEntry] = []
    var ids: IdSequencer = IdSequencer()
}

/// スナップショットの保存先。`FremaRegiStore` は更新のたびに保存する（A-3）。
final class Persistence {
    let directory: URL
    private(set) var lastSavedAt: Date?

    init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FremaRegi", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    private func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

    // ── マスタ・記録（バックアップ・復元可能・A-8）──

    func saveRegistry(_ data: RegistryData) throws {
        let enc = jsonEncoder
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(data).write(to: file("registry.json"), options: .atomic)
        lastSavedAt = Date()
    }

    /// 起動時に呼ぶ。「無い」は nil、「壊れている」は throw（黙って捨てない）
    func loadRegistry() throws -> RegistryData? {
        let url = file("registry.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try jsonDecoder.decode(RegistryData.self, from: Data(contentsOf: url))
    }

    // ── 会計コンテキスト（SaleContextStore は StateMachine.swift に定義済み・base/6 §8）──

    var saleContextStore: SaleContextStore { SaleContextStore() }

    // ── エクスポート（保存ダイアログ／共有シートへ渡すファイル・N-4）──

    func exportedURL(suggestedName: String, contents: String) throws -> URL {
        let dir = directory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(suggestedName)
        try contents.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}
