import Foundation

// ════════════════════════════════════════════════════════════
// 0. グループ（product_groups）— 販売元別の精算単位（A-1、A-8）
// ════════════════════════════════════════════════════════════

/// グループ。集計の第1軸（A-8）。
/// `groupId` は変更不可、`label` は変更可（A-1）。
struct ProductGroup: Codable, Equatable, Identifiable {
    let groupId: String        // 例: "mono"。半角英数字とアンダースコア。不変
    var label: String          // 表示名（例: "もの製品"）。変更可

    var id: String { groupId }
}

// ════════════════════════════════════════════════════════════
// 1. 種類（product_types）
// ════════════════════════════════════════════════════════════

/// 在庫の扱い（A-1）。仮置き（Q20）。
enum StockMode: String, Codable, CaseIterable {
    case counted = "counted"   // 数量管理型：在庫を数える。0以上
    case unique  = "unique"    // 一点物型：0 か 1
    case none    = "none"      // 在庫管理なし型：在庫を持たない
}

/// 商品の種類。**在庫の扱い・ID形式・カート挙動・属性を定める**（A-1）。
struct ProductType: Codable, Equatable, Identifiable {
    let typeId: String         // 例: "sticker"
    var name: String           // 表示名（例: "ステッカー"）
    var idPrefix: String       // ID 接頭辞（例: "ST"）。種類間で一意
    var idDigits: Int          // ID 番号の桁数（例: 3）
    var stockMode: StockMode   // 在庫の扱い ← **商品ではなく種類が持つ**（A-19-9）

    var attrLabel1: String? = nil    // 属性ラベル（最大3・左から詰める。仮置き Q20）
    var attrLabel2: String? = nil
    var attrLabel3: String? = nil
    var groupId: String? = nil       // 所属グループ。nil = グループなし（A-1、A-13）
    var nextNo: Int = 1              // 次に採番する番号。高水位。減らさない（A-1、A-13）
    var updatedAt: Date? = nil       // 更新ルールが無いので Optional（A-19-9）

    var id: String { typeId }
}

// ════════════════════════════════════════════════════════════
// 2. 商品（products）— **在庫表そのもの**。現在庫の正（A-7）。
// ════════════════════════════════════════════════════════════

struct Product: Codable, Equatable, Identifiable {
    let id: String             // 商品ID（例: "KH-008"）
    var typeId: String         // 属する種類（product_types へ）
    var name: String
    var priceJpy: Int          // 円価格（1以上）
    var priceSats: Int?        // nil = sats単価なし。sats払いでも現金で受け取る（A-6-1）
    var stock: Int?            // nil = 在庫管理なし型。counted/unique なら必ず値を持つ

    // ---- ここから先は「使いたいときだけ書く」 ----
    // CSV取り込み・画像・公開状態で必要なときだけ書く（A-1、A-13）
    var attr1: String? = nil
    var attr2: String? = nil
    var attr3: String? = nil
    var imageRef: String? = nil      // 保存先フォルダの画像ファイル名。**B へは送らない**（A-14）
    var isPublic: Bool = false       // 公開状態（CSV では 1/0）
    var updatedAt: Date? = nil

    /// 在庫を持たない型かどうか（種類を引いて判定する）
    func managesStock(in types: [ProductType]) -> Bool {
        stockMode(in: types) != .none
    }

    /// この商品の種類（A-1）
    func stockMode(in types: [ProductType]) -> StockMode {
        types.first { $0.typeId == typeId }?.stockMode ?? .none
    }

    /// 属性の値（`attr1`〜`attr3`）を、**種類のラベルと同じ順**で並べる。
    /// **`compactMap` しない。** 空（nil）を詰めると位置がずれる（A-14 と同じ理由）。
    var attrs: [String?] { [attr1, attr2, attr3] }

    /// 属性の表示文字列（A-1「画像がない商品は、商品名・属性の文字表示で代替する」）。
    ///
    /// - ラベルと値がそろっている → `"色:赤 模様:○"`
    /// - **ラベルが無いのに値がある** → `nil`（CSV の取り込みで弾く違反。A-1）
    /// - 値が無い属性は**出さない**
    ///
    /// **ラベルは左から詰める**（A-1）ので、`[attr1, attr2, attr3]` と
    /// `[attrLabel1, attrLabel2, attrLabel3]` を同じ添字で見れば足りる。
    func attrText(in types: [ProductType]) -> String? {
        guard let t = types.first(where: { $0.typeId == typeId }) else { return nil }
        let labels = [t.attrLabel1, t.attrLabel2, t.attrLabel3]
        var parts: [String] = []
        for i in 0..<3 {
            switch (labels[i], attrs[i]) {
            case let (.some(label), .some(value)):
                parts.append("\(label):\(value)")
            case (.none, .some):
                return nil          // ラベルのない属性に値がある = 取り込みエラー
            default:
                continue            // どちらも無い（値だけ無い場合も含む）
            }
        }
        return parts.joined(separator: " ")
    }

    /// 画像のファイル名。`image_ref` が無い商品は、商品IDから導出する（A-17）。
    /// 保存先フォルダには `<商品ID>.jpg` で保存するため、
    /// 商品追加・CSV取り込みで `image_ref` が空でも画像を表示できる。
    var bundledImageName: String {
        if let imageRef, !imageRef.isEmpty { return imageRef }
        return "\(id).jpg"
    }

    /// レジ画面に表示できる画像があるか。
    /// 保存先フォルダの `<商品ID>.jpg` を探す（旧版が同梱した画像もフォールバックで探す）。
    var hasDisplayImage: Bool {
        bundledImageURL(named: bundledImageName) != nil
    }
}

/// 表示用の画像 URL。保存先フォルダの写真を優先し、
/// 無ければ旧版が Xcode に同梱した画像を探す。
func bundledImageURL(named name: String) -> URL? {
    guard !name.isEmpty else { return nil }
    if let runtime = ProductImageStore.displayURL(fileName: name) {
        return runtime
    }
    return bundledOnlyImageURL(named: name)
}

/// 旧版が Xcode に同梱した画像だけを探す（互換用。新規の画像は保存先フォルダに置く）。
/// Xcode がリソースを直下に置く場合と、`Images/` サブディレクトリを保つ場合の両方に対応する。
func bundledOnlyImageURL(named name: String) -> URL? {
    guard !name.isEmpty else { return nil }
    let bundle = Bundle.main
    return bundle.url(forResource: name, withExtension: nil)
        ?? bundle.url(forResource: name, withExtension: nil, subdirectory: "Images")
}

// ════════════════════════════════════════════════════════════
// 3. カート行（sale_items の未保存版）
// ════════════════════════════════════════════════════════════

/// 登録商品か野良か（A-13 の item_type）
enum ItemType: String, Codable {
    case registered            // 商品マスタに登録された商品
    case adhoc                 // 野良商品（商品マスタに無い）
}

/// カートの1行。**在庫を持たない**（A-7）。
/// 現在の在庫は必ず在庫表（`[Product]`）を見ます。
struct CartLine: Codable, Equatable, Identifiable {
    let id: String             // 登録商品は商品ID。野良は "ADHOC-1" など
    var typeId: String?        // 登録商品は種類ID。野良は nil
    var name: String           // カートに入れた時点の商品名（= name_snapshot）
    var unitPriceJpy: Int      // カートに入れた時点の円単価（= unit_price_jpy）
    var unitPriceSats: Int?    // カートに入れた時点のsats単価。nil = この行は現金で受け取る
    var qty: Int
    var groupId: String?       // カートに入れた時点のグループID。登録商品は種類の groupId を複写、野良は入力値。nil = グループなし（A-1、A-13）
    let isAdhoc: Bool          // 野良かどうか

    var itemType: ItemType { isAdhoc ? .adhoc : .registered }
    /// 小計（円）= 単価 × 数量
    var subtotalJpy: Int { unitPriceJpy * qty }
}

// ════════════════════════════════════════════════════════════
// 4. 販売記録（sales / sale_items）— 完了したときだけ作る
// ════════════════════════════════════════════════════════════

enum SaleStatus: String, Codable {
    case completed             // 完了
    case voided                // 販売取消、または sats確認済みの中断
}

/// 会計全体の受け取る方法（A-13 の method）
enum PaymentMethod: String, Codable {
    case cash                  // 全額現金
    case lightning             // sats払い（現金分なし）
    case mixed                 // sats払い（現金分あり）
}

/// この行の受取方法（A-13 の paid_in）
enum PaidIn: String, Codable {
    case jpy                   // 円で受け取る
    case sats                  // satsで受け取る
}

struct Sale: Codable, Equatable, Identifiable {
    let id: String             // 販売ID
    var status: SaleStatus
    var method: PaymentMethod
    var totalJpy: Int?         // 現金で受け取る請求額。lightning は nil
    var totalSats: Int?        // 請求sats額。cash は nil
    var receivedJpy: Int?      // 受取額（cash・mixed）
    var changeJpy: Int?        // お釣り（cash・mixed）
    var confirmedAt: Date?     // sats入金の確認時刻
    var refunded: Bool         // 返金済みフラグ（sats分）
    var completedAt: Date?     // 完了日時。sats確認済みで中断した会計は nil（A-4）
    /// **A-13 の列名**に合わせる。Swift では `id` だけど列は `sale_id`。
    /// `keyEncodingStrategy = .convertToSnakeCase` だけだと `id` になってしまいます。
    enum CodingKeys: String, CodingKey {
        case id = "sale_id"
        case status, method, totalJpy, totalSats, receivedJpy, changeJpy
        case confirmedAt, refunded, completedAt
    }
}

struct SaleItem: Codable, Equatable, Identifiable {
    let id: String             // 明細ID
    let saleId: String
    var itemType: ItemType
    var typeId: String?        // registered のみ
    var groupId: String?       // 販売時点のグループID。registered は種類の groupId を複写、adhoc は入力値。nil = グループなし（A-13）
    var productId: String?     // registered のみ
    var qty: Int
    var unitPriceJpy: Int      // 販売時点の円単価
    var unitPriceSats: Int?    // 販売時点のsats単価。nil = この行は現金で受け取る
    var paidIn: PaidIn
    var nameSnapshot: String   // 販売時点の商品名
    /// **A-13 の列名**に合わせる。`id` → `item_id`。
    enum CodingKeys: String, CodingKey {
        case id = "item_id"
        case saleId, itemType, typeId, groupId, productId, qty
        case unitPriceJpy, unitPriceSats, paidIn, nameSnapshot
    }
}

// ════════════════════════════════════════════════════════════
// 5. 在庫変動（stock_movements）— **追記のみ**（A-7）
// ════════════════════════════════════════════════════════════

enum MovementReason: String, Codable {
    case initial = "initial"   // 初期登録（CSV取り込みで新規登録）
    case sale    = "sale"      // 販売（減る）
    case void    = "void"      // 販売取消（戻る）
    case adjust  = "adjust"    // 手動調整（棚卸し）
}

struct StockMovement: Codable, Equatable, Identifiable {
    let id: String
    let productId: String
    let delta: Int             // 増減数（- / +）
    let reason: MovementReason
    let saleId: String?        // 販売に関係するときのみ
    let at: Date
}

// ════════════════════════════════════════════════════════════
// 6. 会計状態（A-4 の状態機械・8状態）
// ════════════════════════════════════════════════════════════

enum SaleState: String, Codable, CaseIterable {
    case idle                  // 待機中
    case scanning              // スキャン中
    case choosingPayment       // 支払方法選択
    case cashInput             // 現金入力中
    case satsWaiting           // sats待ち
    case mixedCashInput        // 併用現金入力中（sats確認済み）
    case suspended             // 中断（P2: 記録に残るのは sats確認済みのときだけ）
    case done                  // 完了
}

// ════════════════════════════════════════════════════════════
// 7. 合計（画面表示用。DB には無い）
// ════════════════════════════════════════════════════════════

/// 円とsatsは合算しません（A-3、A-6-1）
struct Totals {
    var sats: Int = 0          // sats単価のある行の「単価×数量」の合計
    var cashForSats: Int = 0   // sats単価のない行の「単価×数量」の合計（= 現金分）
    var cash: Int = 0          // 全行の「単価×数量」の合計
}

// ════════════════════════════════════════════════════════════
// 8. B へ送るスナップショット（A-14）— **Product とは別型**
// ════════════════════════════════════════════════════════════
// グループは送信しない（A-14）。groupId・nextNo はこのセクションに含めない。

struct SnapshotType: Codable, Equatable {
    let typeId: String
    let name: String
    let stockMode: StockMode
    let attrLabels: [String]   // 空を含めない
}

struct SnapshotProduct: Codable, Equatable {
    let productId: String
    let typeId: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?        // 空の場合あり
    let attrs: [String?]       // 項目の並びは attrLabels に合わせる
    let stock: Int?            // 在庫管理なし型は nil
    let hasImage: Bool         // 保持項目ではない。保存先フォルダの実ファイル（旧版は同梱画像）から導出する（A-14）
}

struct Snapshot: Codable, Equatable {
    let createdAt: Date        // スナップショット作成時刻
    let types: [SnapshotType]
    let products: [SnapshotProduct]
}

// ════════════════════════════════════════════════════════════
// 9. 送信ログ（sync_log）
// ════════════════════════════════════════════════════════════

enum SyncResult: String, Codable {
    case success
    case failed
}

struct SyncLogEntry: Codable, Equatable, Identifiable {
    let id: String
    let at: Date
    let result: SyncResult
    let detail: String
}

// ════════════════════════════════════════════════════════════
// 10. ID の採番（A-19-4）と日付（A-19-5）
// ════════════════════════════════════════════════════════════

/// 端末のローカル日付で「YYYYMMDD」を作る。
/// **日次集計の境界は UTC ではなくローカル日付**（A-19-5）。
///
/// **「日」は保存しない。** `Date`（タイムゾーン付きの時点）から**その場で導出する**。
/// A-13 の `sales` に日付を写す列は無い（A-19-5）。
/// だからエクスポートを受けた端末は、自分のタイムゾーンで集計し直せる。
enum DayKey {
    static func string(from date: Date) -> String {
        let c = Calendar.current        // 端末設定のタイムゾーン（A-19-5）
        return String(format: "%04d%02d%02d",
                      c.component(.year, from: date),
                      c.component(.month, from: date),
                      c.component(.day, from: date))
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        string(from: a) == string(from: b)
    }
}

/// ID を振ります。**販売系のIDは販売の途中で生まれるもの**なので、
/// **生まれた瞬間に**採番します（記録しない中断では採番しない。A-19-4）。
///
/// | ID | 形式 | 例 | 採番する瞬間 |
/// | --- | --- | --- | --- |
/// | `sales.sale_id` | `S-YYYYMMDD-NNN` | `S-20261013-001` | 販売を確定した時 |
/// | `sale_items.item_id` | `{sale_id}-{n:02}` | `S-20261013-001-01` | 明細を作るとき |
/// | `stock_movements.id` | `M-{連番:06}` | `M-000001` | 在庫を動かすとき |
/// | `sync_log.id` | `L-{連番:06}` | `L-000001` | 送信するとき |
/// | 野良のカート行 | `ADHOC-{連番:02}` | `ADHOC-01` | **カートに追加した瞬間**（A-19-10） |
///
/// **`products.product_id` は上の原則の例外。** 商品ID は販売前に確定している
/// （**印刷済みQRラベル・原本画像のファイル名**）ため、販売確定時には採番しない。
/// 採番はアプリ内で行う（A-1）。種類の `nextNo` から作り、
/// 採番・商品のINSERT・`nextNo` の更新を同一トランザクションで行う。
/// `nextNo` は減らさない（高水位）。欠番は再利用しない。
/// CSV取り込みの検証は、編集画面と共有する（A-1、A-16）。
struct IdSequencer {
    private var saleCounters: [String: Int] = [:]   // "20261013" → その日の次番
    private var movementSeq = 0
    private var logSeq = 0
    private var adhocSeq = 0

    /// 起動時に既存データから続きを採番するための初期化。
    /// これをしないと再起動後に `M-000001` などが再利用され、主キーが衝突する。
    init(saleCounters: [String: Int] = [:], movementSeq: Int = 0,
         logSeq: Int = 0, adhocSeq: Int = 0) {
        self.saleCounters = saleCounters
        self.movementSeq = movementSeq
        self.logSeq = logSeq
        self.adhocSeq = adhocSeq
    }

    /// 販売ID。日付ごとに 001 から数え直す。
    mutating func nextSaleID(at date: Date) -> String {
        let day = DayKey.string(from: date)
        let n = (saleCounters[day] ?? 0) + 1
        saleCounters[day] = n
        return "S-\(day)-\(pad(n, 3))"
    }

    /// 明細ID（1販売の中の連番。n は 1 始まり）
    func itemID(saleId: String, n: Int) -> String {
        "\(saleId)-\(pad(n, 2))"
    }

    /// 在庫変動ID（全販売をまたいで連番）
    mutating func nextMovementID() -> String {
        movementSeq += 1
        return "M-" + pad(movementSeq, 6)
    }

    /// 送信ログID
    mutating func nextLogID() -> String {
        logSeq += 1
        return "L-" + pad(logSeq, 6)
    }

    /// 野良のカート行ID（A-19-10）。**野良をカートに追加した瞬間に**採番する。
    /// 販売ID（A-19-4）と異なり、会計の完了前に存在するため。
    mutating func nextAdhocID() -> String {
        adhocSeq += 1
        return "ADHOC-" + pad(adhocSeq, 2)
    }

    /// 野良IDの高水位。再起動後も再利用しないために保存する（A-1）。
    var adhocHighWater: Int { adhocSeq }

    /// 商品IDを作る（A-1）。`nextNo` が `idDigits` の桁数を超える場合は nil（追加しない）。
    /// **この関数は状態を変えない。** 呼び出し側が、成功時に `nextNo += 1` を
    /// 商品のINSERTと同じトランザクションで行う。
    func makeProductID(for type: ProductType) -> String? {
        guard type.nextNo >= 1 else { return nil }
        let digits = String(type.nextNo)
        guard digits.count <= type.idDigits else { return nil }
        return "\(type.idPrefix)-" + pad(type.nextNo, type.idDigits)
    }

    /// 取り消しても番号は戻らない。再利用しない（A-19-4）
    private func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }
}

// ════════════════════════════════════════════════════════════
// 補助（カートの行を作る／合計を引く）
// ════════════════════════════════════════════════════════════

/// 登録商品からカートの行を作る。商品名・価格・グループを「その時点」で写す（A-13 の snapshot）。
/// グループは種類（`ProductType.groupId`）から複写する（A-13）。
extension CartLine {
    init(product p: Product, qty: Int, in types: [ProductType]) {
        let gid = types.first { $0.typeId == p.typeId }?.groupId
        self.init(id: p.id, typeId: p.typeId, name: p.name,
                  unitPriceJpy: p.priceJpy, unitPriceSats: p.priceSats,
                  qty: qty, groupId: gid, isAdhoc: false)
    }
}

/// 野良商品の行を作る（A-1）。種類を持たない。グループは入力値（nil = グループなし）。
extension CartLine {
    static func adhoc(id: String, name: String, priceJpy: Int, priceSats: Int?,
                      groupId: String?, qty: Int) -> CartLine {
        CartLine(id: id, typeId: nil, name: name,
                 unitPriceJpy: priceJpy, unitPriceSats: priceSats,
                 qty: qty, groupId: groupId, isAdhoc: true)
    }
}

/// カートの合計（A-3、A-6-1）
extension Array where Element == CartLine {
    /// **sats払いが選べるか**（A-6-1）。
    /// `move(_:in:)` の `.chooseSats` の guard もこれを見る（`base/6` §4）。
    /// 画面が「sats払いが選べるか」を判定するときも、**ここだけ**を見る。
    func canPayBySats() -> Bool {
        contains { $0.unitPriceSats != nil }
    }

    func totals() -> Totals {
        var t = Totals()
        for line in self {
            if let s = line.unitPriceSats { t.sats += s * line.qty }
            else { t.cashForSats += line.unitPriceJpy * line.qty }
            t.cash += line.unitPriceJpy * line.qty
        }
        return t
    }
}
