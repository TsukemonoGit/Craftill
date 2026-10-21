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
        var data = try Data(contentsOf: url)
        // UTF-8 BOM 付きの復元ファイル（Windows や他アプリで生成されたバックアップ）にも対応（P1対策）
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            data = data.dropFirst(3)
        }
        return try jsonDecoder.decode(RegistryData.self, from: data)
    }

    // ── 商品画像の同梱解決（A-1・ビルド時バンドル or Documents/originals/ を商品IDで探す）──

    /// 商品IDに対応する同梱画像の実体パスを返す。
    /// 探索順:
    ///   1. メインバンドルの画像リソース（Xcode プロジェクトに同梱した <id>.png / jpg / jpeg）
    ///      — named lookup を使うので、フォルダ参照でも扁平な Resources 配置でも見つかる
    ///   2. Documents/originals/<id>.{png,jpg,jpeg}（運用中に差し替えた原本・A-1）
    ///   3. バンドル内の images/ フォルダ配下（inDirectory 版）
    func resolveImageRef(for productID: String) -> String? {
        let exts = ["png", "jpg", "jpeg"]
        // 1. バンドルの画像リソース名として解決（同梱画像の主な経路）
        for e in exts {
            if let url = Bundle.main.url(forResource: productID, withExtension: e) { return url.path }
        }
        // 2. データディレクトリの originals/（棚卸し時に後から置いた原本）
        let origDir = directory.appendingPathComponent("originals", isDirectory: true)
        for e in exts {
            let candidate = origDir.appendingPathComponent("\(productID).\(e)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate.path }
        }
        // 3. バンドル内の images/ サブディレクトリ（folder reference として同梱した場合）
        for e in exts {
            if let p = Bundle.main.path(forResource: productID, ofType: e, inDirectory: "images") { return p }
        }
        return nil
    }

    /// 未解決の imageRef を持つ商品について、同梱画像を再スキャンして対応付ける（起動時・追加後に呼ぶ）。
    @discardableResult
    func attachMissingImages(to inventory: inout [Product]) -> Int {
        var attached = 0
        for i in inventory.indices where inventory[i].imageRef == nil {
            if let ref = resolveImageRef(for: inventory[i].id) {
                inventory[i].imageRef = ref
                attached += 1
            }
        }
        if attached > 0 { lastSavedAt = Date() }   // 実体変更はないが、呼び出し側で saveAll される前提
        return attached
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
