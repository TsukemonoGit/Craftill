import SwiftUI
import Combine
import Network
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - 画面・ダイアログ・補助型

enum Screen: Hashable {
    case initialLaunch, register, menu, edit, csvImport, report
    case salesHistory, stockAdjust, priceList, qrLabels, sync, dataManagement, imageFolder
}

enum Dialog: Identifiable {
    case deleteLine(CartDelete)
    case zeroQty(CartDelete)
    case suspend
    case suspendSatsConfirmed
    case satsConfirm
    case voidSale(String)
    case resetData(reseed: Bool)
    case resetAccounting(restoreStock: Bool)
    case resetStock
    case clearSyncLog
    case message(String)

    var id: String {
        switch self {
        case .deleteLine: return "deleteLine"
        case .zeroQty: return "zeroQty"
        case .suspend: return "suspend"
        case .suspendSatsConfirmed: return "suspendSatsConfirmed"
        case .satsConfirm: return "satsConfirm"
        case .voidSale: return "voidSale"
        case .resetData(let reseed): return reseed ? "resetDataSeed" : "resetData"
        case .resetAccounting(let restoreStock):
            return restoreStock ? "resetAccountingStock" : "resetAccounting"
        case .resetStock: return "resetStock"
        case .clearSyncLog: return "clearSyncLog"
        case .message: return "message"
        }
    }
}

struct PinPrompt: Identifiable {
    let id = UUID()
    let title: String
    let onSuccess: () -> Void
}

struct DoneInfo {
    let saleId: String
    let method: PaymentMethod
    let totalSats: Int?
    let cashPart: Int?
    let received: Int?
    let change: Int?
}

/// 会計状態の自動保存（UserDefaults に JSON。A-3 / docs/開発/1_決定事項）。
private struct ActiveSale: Codable {
    var context: SaleContext
    var cashReceived: Int
    var satsStartedAt: Date?
}

struct ReportRow: Identifiable {
    let id: String
    let groupLabel: String
    let kind: String
    let typeName: String
    let paidIn: PaidIn
    var lines: Int
    var qty: Int
    var amount: Int
}

struct LabelPrintItem: Identifiable, Equatable {
    let productId: String
    var copies: Int

    var id: String { productId }
}

extension StockMode {
    var label: String {
        switch self {
        case .counted: return "数量管理型"
        case .unique: return "一点物型"
        case .none: return "在庫管理なし型"
        }
    }
}

extension PaymentMethod {
    var label: String {
        switch self {
        case .cash: return "現金"
        case .lightning: return "sats払い"
        case .mixed: return "sats払い＋現金分"
        }
    }
}

extension SaleState {
    var label: String {
        switch self {
        case .idle: return "待機中"
        case .scanning: return "スキャン中"
        case .choosingPayment: return "支払方法選択"
        case .cashInput: return "現金入力中"
        case .satsWaiting: return "sats待ち"
        case .mixedCashInput: return "併用現金入力中（sats確認済み）"
        case .suspended: return "中断"
        case .done: return "完了"
        }
    }
}

// MARK: - 仮ViewModel
// 画面確認用。ロジック実装時は、この中の各メソッドの本体を差し替える。

final class AppViewModel: ObservableObject {
    // 画面
    @Published var screen: Screen = .initialLaunch
    @Published var message: String = ""
    @Published var dialog: Dialog? = nil
    @Published var dialogPin: String = ""
    @Published var pinPrompt: PinPrompt? = nil
    @Published var showAdhoc = false
    /// OS の接続状態（A-10）。`NWPathMonitor` が更新する。画面からは書き換えない。
    @Published private(set) var isOnline = true
    @Published var pin: String? = nil
    @Published var isUnlocked = false

    // マスタ
    @Published var groups: [ProductGroup] = []
    @Published var types: [ProductType] = []
    @Published var inventory: [Product] = []
    @Published var selectedTypeId: String = ""

    // 会計。状態・カート・sats確認は `SaleContext` が唯一の正（A-4）。
    @Published private(set) var context = SaleContext()
    @Published var cashReceived = 0
    @Published var satsStartedAt = Date()
    @Published var done: DoneInfo? = nil

    /// 画面はこの読み取り専用の値だけを見る。UI から直接代入しない。
    var saleState: SaleState { context.state }
    var cart: [CartLine] { context.cart }
    var satsConfirmedAt: Date? { context.satsConfirmedAt }

    // 記録
    @Published var sales: [Sale] = []
    @Published var saleItems: [SaleItem] = []
    @Published var movements: [StockMovement] = []
    @Published var syncLog: [SyncLogEntry] = []
    @Published var lastSyncAt: Date? = nil
    @Published var syncEndpoint = SyncSettings.endpoint
    @Published var syncToken = SyncSettings.token
    /// QRラベル画面で、直前に登録した商品だけを表示するためのID。
    /// 商品登録直後の「QRを印刷」導線で使う。他の画面へ移ると解除する。
    @Published var qrFocusProductId: String? = nil
    /// QRラベル作成キュー（同一商品は1行に集約し、copiesで枚数を管理する）。
    @Published var qrQueue: [LabelPrintItem] = []
    /// QRラベル作成の商品一覧フィルタ（空文字 = すべて）。
    @Published var qrListFilterTypeId: String = ""
    /// QRラベル作成の商品一覧検索（商品ID/商品名）。
    @Published var qrListSearchText: String = ""
    /// QRラベル作成で、一覧から追加するときの既定枚数。
    @Published var qrPendingCopies: Int = 1

    private var ids = IdSequencer()
    private let db = Database.shared
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private static let activeSaleKey = "craftill.activeSale"
    private static let adhocSeqKey = "craftill.adhocSeq"
    /// `requirePinWithValue` で、検証済みの PIN を操作へ渡すために保持する。
    private var verifiedPin = ""
    /// 確認ダイアログ／PIN ダイアログを経て適用する遷移（A-4）。
    private var pendingMove: Move?
    /// sats の「済」確認を経て適用する遷移。
    private var pendingSatsMove: Move?
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "dev.craftill.network-monitor")

    init() {
        pin = PinStore.load()
        isUnlocked = pin == nil
        loadMaster()
        restoreActiveSale()
        ids = Self.makeSequencer(sales: sales, movements: movements,
                                 syncLog: syncLog, cart: context.cart)

        if pin != nil { screen = .register }

        // A-10: OS の接続状態を購読する。手動トグルは廃止。
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async { self?.isOnline = online }
        }
        pathMonitor.start(queue: pathQueue)

        // 会計状態は更新のたびに保存する（A-3）。willChange の直後に読む。
        objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async { self.saveActiveSale() }
            }
            .store(in: &cancellables)
    }

    deinit {
        pathMonitor.cancel()
    }

    private func loadMaster() {
        guard let db else {
            message = "データベースを開けませんでした"
            return
        }
        do {
            groups = try db.loadGroups()
            types = try db.loadTypes()
            inventory = try db.loadProducts()
            sales = try db.loadSales()
            saleItems = try db.loadSaleItems()
            movements = try db.loadMovements()
            syncLog = try db.loadSyncLog()
            lastSyncAt = syncLog.last?.at
            selectedTypeId = types.first?.typeId ?? ""
        } catch {
            message = "データの読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    private static func makeSequencer(sales: [Sale], movements: [StockMovement],
                                      syncLog: [SyncLogEntry], cart: [CartLine]) -> IdSequencer {
        var counters: [String: Int] = [:]
        for sale in sales {
            let parts = sale.id.split(separator: "-")
            guard parts.count == 3, parts[0] == "S", let n = Int(parts[2]) else { continue }
            let day = String(parts[1])
            counters[day] = max(counters[day] ?? 0, n)
        }
        let movementSeq = movements.compactMap { Int($0.id.dropFirst(2)) }.max() ?? 0
        let logSeq = syncLog.compactMap { Int($0.id.dropFirst(2)) }.max() ?? 0
        let cartAdhocSeq = cart.filter { $0.isAdhoc }
            .compactMap { Int($0.id.replacingOccurrences(of: "ADHOC-", with: "")) }
            .max() ?? 0
        // 野良行を削除して再起動しても、採番済みの番号を再利用しない（A-1）。
        let storedAdhocSeq = UserDefaults.standard.integer(forKey: adhocSeqKey)
        let adhocSeq = max(cartAdhocSeq, storedAdhocSeq)
        return IdSequencer(saleCounters: counters, movementSeq: movementSeq,
                           logSeq: logSeq, adhocSeq: adhocSeq)
    }

    // MARK: 会計状態の保存・復元

    private func saveActiveSale() {
        switch saleState {
        case .idle, .done, .suspended:
            clearActiveSale()
        default:
            let active = ActiveSale(context: context, cashReceived: cashReceived,
                                    satsStartedAt: satsStartedAt)
            if let data = try? JSONEncoder().encode(active) {
                defaults.set(data, forKey: Self.activeSaleKey)
            }
        }
    }

    private func restoreActiveSale() {
        guard let data = defaults.data(forKey: Self.activeSaleKey),
              let active = try? JSONDecoder().decode(ActiveSale.self, from: data) else { return }
        let ctx = active.context
        // 壊れた保存内容で不正な状態に復元しない（A-3、A-4）。
        let valid: Bool
        switch ctx.state {
        case .idle, .done, .suspended:
            valid = false
        case .scanning:
            valid = !ctx.cart.isEmpty && ctx.satsConfirmedAt == nil
        case .choosingPayment:
            valid = !ctx.cart.isEmpty && ctx.satsConfirmedAt == nil
        case .satsWaiting:
            valid = !ctx.cart.isEmpty
        case .mixedCashInput:
            // sats 確認済みの状態なので、確認時刻が無い保存内容は復元しない（A-4）。
            valid = !ctx.cart.isEmpty && ctx.satsConfirmedAt != nil
        case .cashInput:
            valid = !ctx.cart.isEmpty && ctx.satsConfirmedAt == nil
        }
        guard valid else {
            clearActiveSale()
            return
        }
        context = ctx
        cashReceived = active.cashReceived
        satsStartedAt = active.satsStartedAt ?? Date()
        screen = .register
    }

    private func clearActiveSale() {
        defaults.removeObject(forKey: Self.activeSaleKey)
    }


    // MARK: 表示用の算出値

    var totals: Totals { cart.totals() }
    var canPayBySats: Bool { cart.canPayBySats() && isOnline }

    var satsLine: String {
        let t = totals
        if cart.isEmpty { return "sats払い　―" }
        if !cart.canPayBySats() { return "sats払い　選択不可（sats単価のある商品がありません）" }
        if t.cashForSats == 0 { return "sats払い　\(Fmt.sats(t.sats))" }
        return "sats払い　\(Fmt.sats(t.sats)) ＋ \(Fmt.yen(t.cashForSats))"
    }

    var cashLine: String { "現金　　　\(Fmt.yen(totals.cash))" }

    var satsDisabledReason: String? {
        if !cart.canPayBySats() { return "sats単価のある商品がありません" }
        if !isOnline { return "通信なし: sats払いを無効化（現金のみ受付）" }
        return nil
    }

    var cashDue: Int { saleState == .mixedCashInput ? totals.cashForSats : totals.cash }
    var canConfirmCash: Bool { cashReceived >= cashDue }
    var change: Int { max(0, cashReceived - cashDue) }

    func groupLabel(_ id: String?) -> String {
        guard let id else { return "グループなし" }
        return groups.first { $0.groupId == id }?.label ?? id
    }

    func typeName(_ id: String?) -> String {
        guard let id else { return "―" }
        return types.first { $0.typeId == id }?.name ?? id
    }

    func tabLabel(_ t: ProductType) -> String {
        t.groupId == nil ? t.name : "\(groupLabel(t.groupId))｜\(t.name)"
    }

    func products(ofType id: String) -> [Product] {
        inventory.filter { $0.typeId == id }
    }

    func isUniqueInCart(_ p: Product) -> Bool {
        p.stockMode(in: types) == .unique && cart.contains { $0.id == p.id && !$0.isAdhoc }
    }

    func managesStock(_ p: Product) -> Bool { p.managesStock(in: types) }

    // MARK: QRラベル作成

    var qrTotalLabels: Int { qrQueue.reduce(0) { $0 + $1.copies } }

    var qrExpandedProducts: [Product] {
        let map = Dictionary(uniqueKeysWithValues: inventory.map { ($0.id, $0) })
        var result: [Product] = []
        for item in qrQueue {
            guard let product = map[item.productId], item.copies > 0 else { continue }
            result.append(contentsOf: Array(repeating: product, count: item.copies))
        }
        return result
    }

    func addToQRQueue(productId: String, copies: Int) {
        guard inventory.contains(where: { $0.id == productId }) else { return }
        let add = min(max(1, copies), 999)
        if let idx = qrQueue.firstIndex(where: { $0.productId == productId }) {
            qrQueue[idx].copies = min(999, qrQueue[idx].copies + add)
        } else {
            qrQueue.append(LabelPrintItem(productId: productId, copies: add))
        }
    }

    func addManyToQRQueue(productIds: [String], copies: Int) {
        guard !productIds.isEmpty else { return }
        for id in productIds {
            addToQRQueue(productId: id, copies: copies)
        }
    }

    func setQRQueueCopies(productId: String, copies: Int) {
        let normalized = min(max(1, copies), 999)
        guard let idx = qrQueue.firstIndex(where: { $0.productId == productId }) else { return }
        qrQueue[idx].copies = normalized
    }

    func removeFromQRQueue(productId: String) {
        qrQueue.removeAll { $0.productId == productId }
    }

    func clearQRQueue() {
        qrQueue.removeAll()
    }

    func normalizeQRQueue() {
        let valid = Set(inventory.map(\.id))
        qrQueue = qrQueue
            .filter { valid.contains($0.productId) }
            .map { LabelPrintItem(productId: $0.productId, copies: min(max(1, $0.copies), 999)) }
    }

    // MARK: 画面遷移

    func go(_ s: Screen) {
        // 登録直後のQRフォーカスは、QR画面を離れたら解除する。
        if s != .qrLabels { qrFocusProductId = nil }
        screen = s
    }

    func openMenu() {
        guard saleState == .idle else { return }
        qrFocusProductId = nil
        screen = .menu
    }

    func exitAdmin() {
        qrFocusProductId = nil
        screen = pin == nil ? .initialLaunch : .menu
    }

    func setPin(_ a: String, confirm b: String) {
        guard a.count >= 4 else { message = "PINは4文字以上で入力してください"; return }
        guard a == b else { message = "PINが一致しません"; return }
        let saved = PinStore.save(a)
        pin = a
        isUnlocked = true
        verifiedPin = a
        message = saved ? "PINを設定しました" : "PINを保存できませんでした（この起動中のみ有効）"
        screen = .register
    }

    /// 起動時のロック解除
    @discardableResult
    func unlock(_ entered: String) -> Bool {
        guard let pin else {
            isUnlocked = true
            verifiedPin = ""
            return true
        }
        guard entered == pin else {
            message = "PINが違います"
            return false
        }
        isUnlocked = true
        // 起動時の解除も「このセッションで PIN を検証済み」として扱う。
        // これがないと、解除後に編集画面で保存するたび PIN を要求してしまう（A-11）。
        verifiedPin = entered
        message = ""
        return true
    }

    func lock() {
        guard pin != nil else { return }
        isUnlocked = false
        verifiedPin = ""
        pinPrompt = nil
        dialog = nil
    }

    func requirePin(_ title: String, _ action: @escaping () -> Void) {
        pinPrompt = PinPrompt(title: title, onSuccess: action)
    }

    /// PIN 入力後に、検証済みの PIN を渡して実行する。
    /// VM 側でも PIN を再検証する操作（返金済み設定・在庫調整）に使う（A-11）。
    func requirePinWithValue(_ title: String, _ action: @escaping (String) -> Void) {
        pinPrompt = PinPrompt(title: title) { [weak self] in
            action(self?.verifiedPin ?? "")
        }
    }

    func submitPin(_ s: String) {
        if verifyPin(s) {
            verifiedPin = s
            let action = pinPrompt?.onSuccess
            pinPrompt = nil
            action?()
        } else {
            message = "PINが違います"
        }
    }

    func verifyPin(_ s: String) -> Bool {
        guard let pin else { return false }
        return s == pin
    }

    /// VM 内での PIN 再検証（A-11）。画面を迂回した呼び出しでも、
    /// このセッションで PIN を検証していなければ操作できない。
    /// PIN 未設定（初期投入）だけは許可する。
    private func adminPINError(_ entered: String? = nil) -> String? {
        guard let pin else { return nil }
        let candidate = entered ?? verifiedPin
        return candidate == pin ? nil : "PINが違います"
    }

    /// エクスポートなど戻り値を持たない操作向け。失敗時は message に出す。
    @discardableResult
    private func requireAdmin(_ title: String) -> Bool {
        if let e = adminPINError() {
            message = "\(title): \(e)"
            return false
        }
        return true
    }

    // MARK: ダイアログ

    func closeDialog() {
        dialog = nil
        dialogPin = ""
        pendingMove = nil
    }

    func confirmDialog(_ d: Dialog) {
        switch d {
        case .deleteLine(let x), .zeroQty(let x):
            confirmDelete(x)
            closeDialog()
        case .suspend:
            if let m = pendingMove { apply(m, to: &context) }
            pendingMove = nil
            resetSale()
            message = "会計を中断しました"
            closeDialog()
        case .suspendSatsConfirmed:
            guard verifyPin(dialogPin) else { message = "PINが違います"; return }
            guard recordConfirmedSuspend(pin: dialogPin) else { return }
            if let m = pendingMove { apply(m, to: &context) }
            pendingMove = nil
            resetSale()
            message = "sats確認済みの会計を中断しました（記録あり）"
            closeDialog()
        case .satsConfirm:
            closeDialog()
            approveSats()
        case .voidSale(let id):
            guard verifyPin(dialogPin) else { message = "PINが違います"; return }
            performVoidSale(id, pin: dialogPin)
            closeDialog()
        case .resetData(let reseed):
            guard verifyPin(dialogPin) else { message = "PINが違います"; return }
            performResetData(reseed: reseed)
            closeDialog()
        case .resetAccounting(let restoreStock):
            guard verifyPin(dialogPin) else { message = "PINが違います"; return }
            performResetAccounting(restoreStock: restoreStock)
            closeDialog()
        case .resetStock:
            guard verifyPin(dialogPin) else { message = "PINが違います"; return }
            performResetStockToInitial()
            closeDialog()
        case .clearSyncLog:
            guard verifyPin(dialogPin) else { message = "PINが違います"; return }
            performClearSyncLog()
            closeDialog()
        case .message:
            closeDialog()
        }
    }

    // MARK: カート

    @discardableResult
    func addToCart(_ p: Product) -> Bool {
        guard saleState == .idle || saleState == .scanning else {
            message = "この状態では商品を追加できません"
            return false
        }
        let event: SaleEvent = saleState == .idle ? .addFirstItem : .addItem
        let result = add(product: p, qty: 1, cart: &context.cart, inventory: inventory, types: types)
        applyEdit(result, zero: false, event: event)
        return true
    }

    func normalizeID(_ raw: String) -> String {
        let half = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        let s = half.uppercased().filter { !$0.isWhitespace }

        // 「接頭辞-番号」は、ハイフンの有無にかかわらず同じ規則でゼロ埋めする（A-2）。
        // 例: `mk-8` → `MK-008`。以前はハイフン付き入力をそのまま返していた。
        let parts = s.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 2, let n = Int(parts[parts.count - 1]) {
            let prefix = parts.dropLast().joined(separator: "-")
            if let t = types.first(where: { $0.idPrefix.uppercased() == prefix }) {
                let num = String(n)
                return "\(t.idPrefix)-" + String(repeating: "0", count: max(0, t.idDigits - num.count)) + num
            }
            return s
        }

        for t in types.sorted(by: { $0.idPrefix.count > $1.idPrefix.count }) where s.hasPrefix(t.idPrefix) {
            let rest = String(s.dropFirst(t.idPrefix.count))
            if let n = Int(rest) {
                let num = String(n)
                return "\(t.idPrefix)-" + String(repeating: "0", count: max(0, t.idDigits - num.count)) + num
            }
        }
        return s
    }

    @discardableResult
    func addByID(_ raw: String) -> Bool {
        let id = normalizeID(raw)
        guard let p = inventory.first(where: { $0.id == id }) else {
            message = "存在しないID: \(raw)"
            return false
        }
        return addToCart(p)
    }

    func increaseQty(_ i: Int) {
        guard saleState == .scanning else { return }
        applyEdit(increase(at: i, cart: &context.cart, inventory: inventory, types: types), zero: false)
    }

    func decreaseQty(_ i: Int) {
        guard saleState == .scanning else { return }
        // 数量が 1 以上残る減算では状態を変えない。行が 0 になる場合は確認後に
        // `confirmDelete()` が `.removeItem` を適用する（A-4）。
        applyEdit(decrease(at: i, cart: &context.cart, inventory: inventory, types: types),
                  zero: true)
    }

    func removeLine(_ i: Int) {
        guard saleState == .scanning else { return }
        applyEdit(remove(at: i, cart: context.cart), zero: false, event: .removeItem)
    }

    /// カート編集の結果を表示し、成功時だけ状態機械の遷移を適用する（A-4）。
    private func applyEdit(_ e: CartEdit, zero: Bool, event: SaleEvent? = nil) {
        switch e {
        case .applied(let m):
            message = m
            if let event { applyMove(event) }
        case .needsConfirm(let d):
            dialog = zero ? .zeroQty(d) : .deleteLine(d)
        case .rejected(let m):
            message = m
        }
    }

    private func confirmDelete(_ d: CartDelete) {
        guard context.cart.indices.contains(d.index) else {
            message = "対象が消えていました"
            return
        }
        message = performDelete(d, cart: &context.cart)
        applyMove(.removeItem)
    }

    func addAdhoc(priceJpy: Int, priceSats: Int?, name: String, groupId: String?, qty: Int) {
        guard saleState == .idle || saleState == .scanning else { return }
        let event: SaleEvent = saleState == .idle ? .addFirstItem : .addItem
        let line = CartLine.adhoc(id: ids.nextAdhocID(),
                                  name: name.isEmpty ? "野良" : name,
                                  priceJpy: priceJpy, priceSats: priceSats,
                                  groupId: groupId, qty: max(1, qty))
        defaults.set(ids.adhocHighWater, forKey: Self.adhocSeqKey)
        context.cart.append(line)
        applyMove(event)
        message = "\(line.name) を追加しました"
    }

    // MARK: 会計の遷移

    /// 遷移は `move()` の返り値だけを見て適用する（A-4）。
    /// UI はこの関数を呼ぶだけで、`SaleState` を直接代入しない。
    @discardableResult
    private func applyMove(_ event: SaleEvent) -> Move {
        let m = move(event, in: context)
        switch m {
        case .allowed:
            apply(m, to: &context)
        case .rejected(let reason):
            message = reason
        case .needsConfirm, .needsPIN:
            // 確認・PIN が必要な遷移は、この関数では適用しない。
            // 呼び出し側がダイアログを出し、確認後に `apply()` する（A-4）。
            break
        }
        return m
    }

    func proceedToPayment() {
        guard !cart.isEmpty else { return }
        applyMove(.toPaymentSelection)
    }

    func backToScan() {
        applyMove(.backToScan)
    }

    func chooseCash() {
        let m = applyMove(.chooseCash)
        if m.nextState == .cashInput { cashReceived = 0 }
    }

    func chooseSats() {
        guard canPayBySats else {
            message = satsDisabledReason ?? "sats払いを選択できません"
            return
        }
        let m = applyMove(.chooseSats)
        if m.nextState == .satsWaiting {
            satsStartedAt = Date()
            context.satsConfirmedAt = nil
            context.confirmedSats = nil
        }
    }

    func reselectMethod() {
        applyMove(.changeMethod)
    }

    func pressKey(_ k: String) {
        switch k {
        case "C": cashReceived = 0
        case "00": cashReceived *= 100
        default:
            if let d = Int(k) { cashReceived = cashReceived * 10 + d }
        }
    }

    func addCash(_ n: Int) { cashReceived += n }

    func confirmCash() {
        guard canConfirmCash else { return }
        let method: PaymentMethod = saleState == .cashInput ? .cash : .mixed
        let event: SaleEvent = saleState == .cashInput
            ? .confirmCash(cashReceived)
            : .confirmMixedCash(cashReceived)
        let m = move(event, in: context)
        guard m.nextState == .done else {
            if case .rejected(let reason) = m { message = reason }
            return
        }
        complete(method: method, finalMove: m)
    }

    func askSatsConfirm() {
        guard saleState == .satsWaiting else { return }
        pendingSatsMove = move(.tapDone, in: context)
        dialog = .satsConfirm
    }

    private func approveSats() {
        guard saleState == .satsWaiting, let m = pendingSatsMove,
              let next = m.nextState else { return }
        pendingSatsMove = nil
        markSatsConfirmed(&context, at: Date())
        if next == .done {
            complete(method: .lightning, finalMove: m)
        } else {
            apply(m, to: &context)
            if next == .mixedCashInput { cashReceived = 0 }
        }
    }

    func copySatsAmount() {
        let s = String(totals.sats)
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = s
        #endif
        message = "請求sats額 \(s) をコピーしました"
    }

    func requestSuspend() {
        let m = move(.suspend, in: context)
        switch m {
        case .needsPIN:
            pendingMove = m
            dialogPin = ""
            dialog = .suspendSatsConfirmed
        case .needsConfirm:
            pendingMove = m
            dialog = .suspend
        case .rejected(let reason):
            message = reason
        case .allowed:
            pendingMove = m
            dialog = .suspend
        }
    }

    func nextSale() {
        resetSale()
        done = nil
    }

    /// 会計データを空に戻す。状態は必ず `move(.backToIdle)` を経てから消す（A-4）。
    private func resetSale() {
        if saleState == .done || saleState == .suspended {
            applyMove(.backToIdle)
        }
        context = SaleContext()
        cashReceived = 0
        pendingMove = nil
        pendingSatsMove = nil
        clearActiveSale()
    }

    // MARK: 初期化・リセット

    /// 会計・在庫・マスタ・送信ログを削除し、メモリ上の状態も空に戻す。
    /// 商品・販売を作り直して最初から試したいとき用。PIN は変更しない。
    private func performResetData(reseed: Bool) {
        guard let db else {
            message = "データベースを開けないため、初期化できません"
            return
        }
        do {
            try db.resetAllData()
            #if DEBUG
            if reseed { try db.seedTestData() }
            #endif
        } catch {
            message = "初期化に失敗しました: \(error.localizedDescription)"
            return
        }

        // 保存済みの会計・採番も消す。DB を消しただけだと再起動時に
        // 古いカートや連番が復元されてしまう（A-1、A-3）。
        clearActiveSale()
        defaults.removeObject(forKey: Self.adhocSeqKey)
        pendingMove = nil
        pendingSatsMove = nil
        context = SaleContext()
        cashReceived = 0
        satsStartedAt = Date()
        done = nil
        screen = .menu
        loadMaster()
        ids = Self.makeSequencer(sales: sales, movements: movements,
                                 syncLog: syncLog, cart: [])
        #if DEBUG
        message = reseed ? "初期化し、テスト商品を再投入しました" : "全データを初期化しました"
        #else
        message = "全データを初期化しました"
        #endif
    }

    /// 会計（販売・明細・販売に伴う在庫変動）を削除する。
    /// `restoreStock` が true なら、在庫も初期登録時の数量へ戻す。
    /// 商品マスタ・手動調整・送信ログは残す。
    private func performResetAccounting(restoreStock: Bool) {
        guard saleState == .idle else {
            message = "会計中は実行できません。待機中（カートが空）にしてください"
            return
        }
        guard let db else {
            message = "データベースを開けないため、会計を初期化できません"
            return
        }
        do {
            try db.resetSalesKeepingMaster()
            inventory = try db.loadProducts()
            movements = try db.loadMovements()
        } catch {
            message = "会計の初期化に失敗しました: \(error.localizedDescription)"
            return
        }

        sales = []
        saleItems = []
        clearActiveSale()
        defaults.removeObject(forKey: Self.adhocSeqKey)
        pendingMove = nil
        pendingSatsMove = nil
        context = SaleContext()
        cashReceived = 0
        satsStartedAt = Date()
        done = nil

        var parts = ["会計を初期化しました（販売・明細・販売に伴う在庫変動を削除）"]
        if restoreStock {
            let result = applyInitialStockReset()
            if let note = result.note {
                parts.append(note)
            } else if result.changed > 0 {
                parts.append("在庫 \(result.changed)件を初期データへ戻しました")
            } else {
                parts.append("在庫を初期データへ戻しました（変更なし）")
            }
        } else {
            parts.append("在庫は販売前に戻しました（手動調整は残ります）")
        }
        ids = Self.makeSequencer(sales: sales, movements: movements,
                                 syncLog: syncLog, cart: [])
        message = parts.joined(separator: "\n")
    }

    /// 在庫だけを初期登録時の数量へ戻す。販売履歴は残す。
    private func performResetStockToInitial() {
        guard saleState == .idle else {
            message = "会計中は実行できません。待機中（カートが空）にしてください"
            return
        }
        let result = applyInitialStockReset()
        if let note = result.note {
            message = note
        } else if result.changed == 0 {
            message = "在庫はすでに初期データです"
        } else {
            message = "在庫 \(result.changed)件を初期データへ戻しました"
        }
    }

    /// 商品ごとの初期在庫（`reason = initial` の合計）へ現在庫を戻す。
    /// 在庫ログとの整合を保つため、差分は `adjust` として記録する。
    private func applyInitialStockReset() -> (changed: Int, note: String?) {
        guard let db else { return (0, "データベースを開けないため、在庫を戻せません") }
        let initial: [String: Int]
        do {
            initial = try db.loadInitialStockTotals()
        } catch {
            return (0, "初期在庫を読み込めませんでした: \(error.localizedDescription)")
        }
        guard !initial.isEmpty else {
            return (0, "初期在庫の記録がありません。テスト商品を再投入してください")
        }

        var inv = inventory
        var mov = movements
        var seq = ids
        var added: [StockMovement] = []
        let now = Date()
        for i in inv.indices {
            guard inv[i].stock != nil, let target = initial[inv[i].id] else { continue }
            let current = inv[i].stock ?? 0
            let diff = target - current
            guard diff != 0 else { continue }
            inv[i].stock = target
            let movement = StockMovement(id: seq.nextMovementID(),
                                         productId: inv[i].id, delta: diff,
                                         reason: .adjust, saleId: nil, at: now)
            mov.append(movement)
            added.append(movement)
        }
        guard !added.isEmpty else { return (0, nil) }

        do {
            try db.persistAdjust(inventory: inv, movements: added)
        } catch {
            return (0, "在庫を戻せませんでした: \(error.localizedDescription)")
        }
        inventory = inv
        movements = mov
        ids = seq
        return (added.count, nil)
    }

    private func performClearSyncLog() {
        guard let db else {
            message = "データベースを開けないため、送信ログを削除できません"
            return
        }
        let count = syncLog.count
        do {
            try db.clearSyncLog()
        } catch {
            message = "送信ログを削除できませんでした: \(error.localizedDescription)"
            return
        }
        syncLog = []
        lastSyncAt = nil
        message = "送信ログを \(count)件削除しました"
    }

    /// レポート・集計の画面確認用に、在庫のある商品からテスト会計を作る。
    /// 通常の会計と同じ `commitSale` を通すので、売上・在庫・在庫変動に反映される。
    func addTestSales(count: Int = 1) {
        guard saleState == .idle else {
            message = "会計中はテスト会計を追加できません"
            return
        }
        guard let db else {
            message = "データベースを開けないため、テスト会計を追加できません"
            return
        }

        var inv = inventory
        var mov = movements
        var allSales = sales
        var allItems = saleItems
        var seq = ids
        var added = 0
        var failure: String? = nil

        for _ in 0..<max(1, min(count, 20)) {
            let candidates = inv.filter {
                $0.managesStock(in: types) && ($0.stock ?? 0) > 0
            }
            guard !candidates.isEmpty else { break }
            let product = candidates[min(added, candidates.count - 1)]
            let cart = [CartLine(product: product, qty: 1, in: types)]
            let beforeMovements = mov.count
            let result = commitSale(cart: cart,
                                    inventory: &inv,
                                    movements: &mov,
                                    sales: &allSales,
                                    items: &allItems,
                                    ids: &seq,
                                    types: types,
                                    chooseSats: false,
                                    receivedJpy: product.priceJpy,
                                    confirmedAt: nil,
                                    now: Date())
            switch result {
            case .failure(let problems):
                failure = problems.joined(separator: " / ")
            case .success(let sale, let items, _):
                do {
                    try db.persistCommit(sale: sale, items: items,
                                         inventory: inv,
                                         movements: Array(mov[beforeMovements...]))
                } catch {
                    message = "テスト会計を保存できませんでした: \(error.localizedDescription)"
                    return
                }
                added += 1
            }
            if failure != nil { break }
        }

        inventory = inv
        movements = mov
        sales = allSales
        saleItems = allItems
        ids = seq

        if let failure, added == 0 {
            message = "テスト会計を作れませんでした: \(failure)"
        } else if added == 0 {
            message = "在庫のある商品がないため、テスト会計を追加できませんでした"
        } else {
            message = "テスト会計を \(added)件追加しました（売上・在庫に反映済み）"
        }
    }

    /// 会計確定。**DB へ保存できたときだけ**メモリへ反映する（P-02、A-4）。
    private func complete(method: PaymentMethod, finalMove: Move) {
        guard let db else {
            message = "データベースを開けないため、会計を完了できません"
            return
        }
        let chooseSats = method != .cash
        let received: Int? = (method == .cash || method == .mixed) ? cashReceived : nil
        let confirmed: Date? = method == .cash ? nil : context.satsConfirmedAt

        // まずコピー上で検証・採番・在庫減算を行う。失敗したら何も反映しない。
        var inv = inventory
        var mov = movements
        var allSales = sales
        var allItems = saleItems
        var seq = ids
        let before = mov.count
        let result = commitSale(cart: context.cart,
                                inventory: &inv,
                                movements: &mov,
                                sales: &allSales,
                                items: &allItems,
                                ids: &seq,
                                types: types,
                                chooseSats: chooseSats,
                                receivedJpy: received,
                                confirmedAt: confirmed,
                                now: Date())

        switch result {
        case .failure(let problems):
            message = problems.joined(separator: "\n")
        case .success(let sale, let newItems, _):
            let newMovements = Array(mov[before...])
            do {
                try db.persistCommit(sale: sale, items: newItems,
                                     inventory: inv, movements: newMovements)
            } catch {
                message = "販売を保存できなかったため、会計は完了していません: \(error.localizedDescription)"
                return
            }
            inventory = inv
            movements = mov
            sales = allSales
            saleItems = allItems
            ids = seq
            apply(finalMove, to: &context)
            done = DoneInfo(saleId: sale.id, method: sale.method,
                            totalSats: sale.totalSats, cashPart: sale.totalJpy,
                            received: sale.receivedJpy, change: sale.changeJpy)
            clearActiveSale()
        }
    }

    @discardableResult
    private func recordConfirmedSuspend(pin entered: String) -> Bool {
        guard let db else {
            message = "データベースを開けないため、中断を記録できません"
            return false
        }
        var allSales = sales
        var allItems = saleItems
        var seq = ids
        let result = suspendSale(cart: context.cart,
                                 ids: &seq,
                                 correctPIN: pin ?? "",
                                 pin: entered,
                                 sales: &allSales,
                                 items: &allItems,
                                 chooseSats: true,
                                 confirmedAt: context.satsConfirmedAt,
                                 now: Date())
        switch result {
        case .failure(let m):
            message = m
            return false
        case .success(let sale, let items):
            guard let sale else { return true }
            do {
                try db.persistCommit(sale: sale, items: items,
                                     inventory: inventory, movements: [])
            } catch {
                message = "中断を保存できなかったため、記録していません: \(error.localizedDescription)"
                return false
            }
            sales = allSales
            saleItems = allItems
            ids = seq
            return true
        }
    }

    // MARK: 販売取消・返金・在庫調整

    private func performVoidSale(_ id: String, pin entered: String) {
        guard let db else {
            message = "データベースを開けないため、販売取消できません"
            return
        }
        // コピー上で取消を作り、保存できたときだけメモリへ反映する（P-02）。
        var inv = inventory
        var mov = movements
        var allSales = sales
        var seq = ids
        let before = mov.count
        let result = voidSale(saleId: id,
                              correctPIN: pin ?? "",
                              pin: entered,
                              sales: &allSales,
                              items: saleItems,
                              inventory: &inv,
                              movements: &mov,
                              ids: &seq,
                              types: types,
                              at: Date())
        switch result {
        case .failure(let m):
            message = m
        case .success(let memo):
            guard let sale = allSales.first(where: { $0.id == id }) else { return }
            do {
                try db.persistVoid(sale: sale, inventory: inv,
                                   movements: Array(mov[before...]))
            } catch {
                message = "販売取消を保存できなかったため、取り消していません: \(error.localizedDescription)"
                return
            }
            inventory = inv
            movements = mov
            sales = allSales
            ids = seq
            message = memo.isEmpty ? "販売取消: \(id)" : "販売取消: \(id)\n" + memo.joined(separator: "\n")
        }
    }

    func toggleRefunded(_ id: String, pin entered: String) {
        guard let db else {
            message = "データベースを開けないため、返金済みフラグを保存できません"
            return
        }
        guard let i = sales.firstIndex(where: { $0.id == id }) else { return }
        var updated = sales
        let result = setRefunded(saleId: id, value: !sales[i].refunded,
                                 correctPIN: pin ?? "", pin: entered, sales: &updated)
        switch result {
        case .failure(let m):
            message = m
        case .success(let m):
            do {
                try db.persistSale(updated[i])
            } catch {
                message = "返金済みフラグを保存できませんでした: \(error.localizedDescription)"
                return
            }
            sales = updated
            message = m
        }
    }

    func performStockAdjustment(productId: String, newStock: Int, reason: String,
                                pin entered: String) -> String? {
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else { return "理由は必須です" }
        guard let db else { return "データベースを開けないため、在庫調整できません" }
        var inv = inventory
        var mov = movements
        var seq = ids
        let before = mov.count
        let result = adjustStock(productId: productId, newStock: newStock, reason: reason,
                                 correctPIN: pin ?? "", pin: entered,
                                 inventory: &inv, movements: &mov,
                                 ids: &seq, types: types, at: Date())
        switch result {
        case .failure(let m):
            return m
        case .success:
            do {
                try db.persistAdjust(inventory: inv, movements: Array(mov[before...]))
            } catch {
                return "在庫調整を保存できませんでした: \(error.localizedDescription)"
            }
            inventory = inv
            movements = mov
            ids = seq
            return nil
        }
    }

    // MARK: 編集（グループ・種類・商品）

    func isGroupInUse(_ id: String) -> Bool {
        types.contains { $0.groupId == id } || saleItems.contains { $0.groupId == id }
    }

    func addGroup(id: String, label: String) -> String? {
        if let e = adminPINError() { return e }
        guard id.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil else { return "グループIDは半角英数字とアンダースコアのみ" }
        guard !groups.contains(where: { $0.groupId == id }) else { return "グループIDが重複しています" }
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return "ラベルは必須です" }
        guard let db else { return "データベースを開けません" }
        let group = ProductGroup(groupId: id, label: label)
        do {
            try db.save(group: group)
        } catch {
            return "グループを保存できませんでした: \(error.localizedDescription)"
        }
        groups.append(group)
        return nil
    }

    func renameGroup(id: String, label: String) -> String? {
        if let e = adminPINError() { return e }
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return "ラベルは必須です" }
        guard let i = groups.firstIndex(where: { $0.groupId == id }) else { return "グループがありません" }
        guard let db else { return "データベースを開けません" }
        var updated = groups[i]
        updated.label = label
        do {
            try db.save(group: updated)
        } catch {
            return "グループを保存できませんでした: \(error.localizedDescription)"
        }
        groups[i] = updated
        return nil
    }

    func deleteGroup(_ id: String) {
        guard adminPINError() == nil else { message = "PINが違います"; return }
        guard !isGroupInUse(id) else { message = "使用中のグループは削除できません"; return }
        guard let db else { message = "データベースを開けません"; return }
        do {
            try db.deleteGroup(id: id)
        } catch {
            message = "グループを削除できませんでした: \(error.localizedDescription)"
            return
        }
        groups.removeAll { $0.groupId == id }
    }

    func isTypeLocked(_ typeId: String) -> Bool {
        inventory.contains { $0.typeId == typeId } || saleItems.contains { $0.typeId == typeId }
    }

    func createType(typeId: String, name: String, prefix: String, digits: Int, mode: StockMode,
                 labels: [String], groupId: String, nextNo: Int) -> String? {
        if let e = adminPINError() { return e }
        guard let db else { return "データベースを開けません" }
        var updated = types
        let result = addType(typeId: typeId, name: name, idPrefix: prefix, idDigits: digits,
                                      stockMode: mode,
                                      labels: labels.map { $0.isEmpty ? nil : $0 },
                                      groupId: groupId.isEmpty ? nil : groupId,
                                      startNo: nextNo,
                                      correctPIN: pin ?? "", pin: verifiedPin,
                                      types: &updated, groups: groups)
        switch result {
        case .failure(let m):
            return m
        case .success:
            guard let type = updated.last else { return "種類を追加できませんでした" }
            do {
                try db.save(type: type)
            } catch {
                return "種類を保存できませんでした: \(error.localizedDescription)"
            }
            types = updated
            return nil
        }
    }

    func updateType(typeId: String, name: String, prefix: String, digits: Int, mode: StockMode,
                    labels: [String], groupId: String) -> String? {
        if let e = adminPINError() { return e }
        guard let i = types.firstIndex(where: { $0.typeId == typeId }) else { return "種類がありません" }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "表示名は必須です" }
        guard prefix.range(of: "^[A-Z0-9]+$", options: .regularExpression) != nil else { return "接頭辞は半角英大文字・数字のみ" }
        guard digits >= 1 else { return "桁数は1以上" }
        guard labelsPacked(labels) else { return "属性ラベルは左から詰めてください" }
        if !groupId.isEmpty, !groups.contains(where: { $0.groupId == groupId }) {
            return "グループがありません"
        }
        // 値のある商品がある属性ラベルは空にできない（`basic.swift` の editType と同じ）。
        for k in 0..<3 where labels[k].isEmpty
            && inventory.contains(where: { $0.typeId == typeId && $0.attrs[k] != nil }) {
            return "値のある商品があるため、属性ラベル\(k + 1)を空にできません"
        }

        // 接頭辞・桁数・在庫モードは、商品または販売記録がある種類では変更できない（A-1）。
        if isTypeLocked(typeId) {
            guard prefix == types[i].idPrefix,
                  digits == types[i].idDigits,
                  mode == types[i].stockMode else {
                return "商品または販売記録がある種類は、接頭辞・桁数・在庫の扱いを変更できません"
            }
        } else {
            guard digits >= String(types[i].nextNo).count else {
                return "桁数が next_no より小さいため変更できません"
            }
            guard !types.contains(where: { $0.typeId != typeId && $0.idPrefix == prefix }) else {
                return "接頭辞が重複しています"
            }
        }

        var updated = types[i]
        updated.name = name
        updated.idPrefix = prefix
        updated.idDigits = digits
        updated.stockMode = mode
        updated.attrLabel1 = labels[0].isEmpty ? nil : labels[0]
        updated.attrLabel2 = labels[1].isEmpty ? nil : labels[1]
        updated.attrLabel3 = labels[2].isEmpty ? nil : labels[2]
        updated.groupId = groupId.isEmpty ? nil : groupId
        updated.updatedAt = Date()
        guard let db else { return "データベースを開けません" }
        do {
            try db.save(type: updated)
        } catch {
            return "種類を保存できませんでした: \(error.localizedDescription)"
        }
        types[i] = updated
        return nil
    }

    private func labelsPacked(_ l: [String]) -> Bool {
        guard l.count == 3 else { return false }
        if l[1].isEmpty && !l[2].isEmpty { return false }
        if l[0].isEmpty && !l[1].isEmpty { return false }
        return true
    }

    /// 商品追加。検証・採番・`next_no`・初期在庫ログを 1 トランザクションで保存する（P-03）。
    func createProduct(typeId: String, name: String, priceJpy: Int, priceSats: Int?,
                    attrs: [String?], stock: Int?, isPublic: Bool) -> String? {
        if let e = adminPINError() { return e }
        guard let db else { return "データベースを開けません" }
        var inv = inventory
        var allTypes = types
        var mov = movements
        var seq = ids
        let input = NewProductInput(typeId: typeId, name: name, priceJpy: priceJpy,
                                    priceSats: priceSats,
                                    attr1: attrs[0], attr2: attrs[1], attr3: attrs[2],
                                    initialStock: stock, isPublic: isPublic)
        let result = addProduct(input,
                                         correctPIN: pin ?? "", pin: verifiedPin,
                                         inventory: &inv, types: &allTypes,
                                         movements: &mov, ids: &seq, at: Date())
        switch result {
        case .failure(let problems):
            return problems.joined(separator: "\n")
        case .success(let product):
            guard let type = allTypes.first(where: { $0.typeId == typeId }) else {
                return "種類がありません"
            }
            let movement = mov.last.flatMap { $0.productId == product.id ? $0 : nil }
            do {
                try db.persistProductAdd(product: product, type: type, movement: movement)
            } catch {
                return "商品を保存できませんでした: \(error.localizedDescription)"
            }
            inventory = inv
            types = allTypes
            movements = mov
            ids = seq
            return nil
        }
    }

    func updateProduct(id: String, name: String, priceJpy: Int, priceSats: Int?,
                       attrs: [String?], isPublic: Bool) -> String? {
        if let e = adminPINError() { return e }
        guard let db else { return "データベースを開けません" }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "商品名は必須です" }
        // 検証は編集画面と CSV 取り込みで共有する（A-1、`basic.swift` の editProduct）。
        var updated = inventory
        let result = editProduct(productId: id, name: name, priceJpy: priceJpy,
                                 priceSats: priceSats, attrs: attrs, isPublic: isPublic,
                                 correctPIN: pin ?? "", pin: verifiedPin,
                                 inventory: &updated, types: types)
        switch result {
        case .failure(let m):
            return m
        case .success:
            guard let i = updated.firstIndex(where: { $0.id == id }) else {
                return "商品がありません"
            }
            updated[i].updatedAt = Date()
            do {
                try db.save(product: updated[i])
            } catch {
                return "商品を保存できませんでした: \(error.localizedDescription)"
            }
            inventory = updated
            return nil
        }
    }

    /// 画像ファイルが同梱されていない登録商品（A-1）。
    /// `image_ref` の有無ではなく、バンドル内に実ファイルがあるかで判定する。
    var productsWithoutImage: [Product] { inventory.filter { !$0.hasBundledImage } }

    // MARK: CSV取り込み（A-1 / P4）

    /// 画面で検証・差分表示するための計画。この時点ではDBもメモリも変更しない。
    func makeCSVImportPlan(groupCSV: CSVTable?, typeCSV: CSVTable?,
                            productCSV: CSVTable?, overwriteStock: Bool) -> CSVImportOutcome {
        CSVImportPlanner.plan(groupCSV: groupCSV,
                              typeCSV: typeCSV,
                              productCSV: productCSV,
                              existingGroups: groups,
                              existingTypes: types,
                              existingProducts: inventory,
                              existingItems: saleItems,
                              overwriteStock: overwriteStock)
    }

    /// 検証済みの計画を、1トランザクションでDBへ反映する。
    func applyCSVImport(_ plan: CSVImportPlan) -> [CSVError] {
        if let e = adminPINError() {
            return [CSVError(row: 0, column: "PIN", reason: e)]
        }
        guard plan.hasChanges else {
            message = "CSVの内容に変更はありません"
            return []
        }
        guard let db else {
            return [CSVError(row: 0, column: "DB", reason: "データベースを開けません")]
        }

        let sequencerBefore = ids
        let newMovements = plan.movements.map {
            StockMovement(id: ids.nextMovementID(), productId: $0.productId,
                          delta: $0.delta, reason: $0.reason, saleId: nil, at: plan.at)
        }
        do {
            try db.persistImport(groups: plan.changedGroups,
                                 types: plan.changedTypes,
                                 products: plan.changedProducts,
                                 movements: newMovements)
        } catch {
            // 失敗時は採番を巻き戻し、在庫変動IDに欠番を作らない。
            ids = sequencerBefore
            return [CSVError(row: 0, column: "DB",
                             reason: "取り込みを保存できませんでした: \(error.localizedDescription)")]
        }

        groups = plan.groups
        types = plan.types
        inventory = plan.products
        movements.append(contentsOf: newMovements)
        if !types.contains(where: { $0.typeId == selectedTypeId }) {
            selectedTypeId = types.first?.typeId ?? ""
        }

        var parts = ["CSVを取り込みました"]
        if plan.newGroupCount + plan.updatedGroupCount > 0 {
            parts.append("グループ 新規\(plan.newGroupCount)・更新\(plan.updatedGroupCount)")
        }
        if plan.newTypeCount + plan.updatedTypeCount > 0 {
            parts.append("種類 新規\(plan.newTypeCount)・更新\(plan.updatedTypeCount)")
        }
        if plan.newProductCount + plan.updatedProductCount > 0 {
            parts.append("商品 新規\(plan.newProductCount)・更新\(plan.updatedProductCount)")
        }
        if !plan.stockDiffs.isEmpty {
            parts.append("在庫上書き \(plan.stockDiffs.count)件")
        }
        message = parts.joined(separator: " / ")
        return []
    }

    // MARK: 集計

    func completedSales(from: Date?, to: Date?) -> [Sale] {
        salesIn(from: from, to: to, in: sales)
            .filter { $0.status == .completed && $0.completedAt != nil }
    }

    func voidedSales(from: Date?, to: Date?, confirmedOnly: Bool) -> [Sale] {
        salesIn(from: from, to: to, in: sales).filter {
            guard $0.status == .voided else { return false }
            let isConfirmedAbort = $0.completedAt == nil
            return isConfirmedAbort == confirmedOnly
        }
    }

    /// sats照合CSVの対象。完了したsats会計、sats確認済みで中断した会計、
    /// 完了後に取り消したsats会計（返金確認用）を含める（A-8、A-9）。
    func satsReconciliationSales(from: Date, to: Date) -> [Sale] {
        (completedSales(from: from, to: to)
            + voidedSales(from: from, to: to, confirmedOnly: true)
            + voidedSales(from: from, to: to, confirmedOnly: false))
            .filter { $0.totalSats != nil }
            .sorted {
                ($0.completedAt ?? $0.confirmedAt ?? .distantPast)
                    < ($1.completedAt ?? $1.confirmedAt ?? .distantPast)
            }
    }

    func reportRows(from: Date?, to: Date?) -> [ReportRow] {
        let ids = Set(completedSales(from: from, to: to).map { $0.id })
        var dict: [String: ReportRow] = [:]
        for item in saleItems where ids.contains(item.saleId) {
            let key = [item.groupId ?? "", item.itemType.rawValue, item.typeId ?? "", item.paidIn.rawValue].joined(separator: "|")
            let amount = item.paidIn == .sats ? (item.unitPriceSats ?? 0) * item.qty : item.unitPriceJpy * item.qty
            var r = dict[key] ?? ReportRow(id: key,
                                           groupLabel: item.groupId == nil ? "グループなし（精算先不明）" : groupLabel(item.groupId),
                                           kind: item.itemType == .registered ? "登録" : "野良",
                                           typeName: typeName(item.typeId), paidIn: item.paidIn,
                                           lines: 0, qty: 0, amount: 0)
            r.lines += 1
            r.qty += item.qty
            r.amount += amount
            dict[key] = r
        }
        return dict.values.sorted { $0.id < $1.id }
    }

    /// 期間全体＋日ごとの小計（A-8）。nil は上限・下限なし（全期間）。
    func periodSummary(from: Date?, to: Date?) -> PeriodSummary {
        summarizeRange(sales, items: saleItems, from: from, to: to)
    }

    /// 日ごとの現金照合（A-8）。期間全体では行わない。
    func cashReconciliation(day: Date, float: Int, actual: Int) -> CashReconciliation {
        reconcileCash(day: day, float: float, actual: actual,
                               sales: sales, items: saleItems)
    }

    // MARK: エクスポート

    private func exportFolderName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "craftill-export-" + f.string(from: Date())
    }

    @MainActor
    func exportAll() {
        guard requireAdmin("エクスポート") else { return }
        guard let dir = CSVExportPanel.chooseDirectory() else { return }
        let folder = dir.appendingPathComponent(exportFolderName(), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let files: [(String, String)] = [
                ("product_groups.csv", CSVExport.groupsCSV(groups)),
                ("product_types.csv", CSVExport.typesCSV(types)),
                ("products.csv", CSVExport.productsCSV(inventory)),
                ("sales.csv", CSVExport.salesCSV(sales)),
                ("sale_items.csv", CSVExport.saleItemsCSV(saleItems)),
                ("stock_movements.csv", CSVExport.movementsCSV(movements)),
                ("sync_log.csv", CSVExport.syncLogCSV(syncLog))
            ]
            for (name, csv) in files {
                try Data(csv.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            // A-13 の列名（snake_case）に合わせる。`sale_id` などの明示キーはそのまま。
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let jsonGroups = try encoder.encode(groups)
            let jsonTypes = try encoder.encode(types)
            let jsonProducts = try encoder.encode(inventory)
            let jsonSales = try encoder.encode(sales)
            let jsonItems = try encoder.encode(saleItems)
            let jsonMovements = try encoder.encode(movements)
            let jsonSync = try encoder.encode(syncLog)
            let jsonFiles: [(String, Data)] = [
                ("product_groups.json", jsonGroups),
                ("product_types.json", jsonTypes),
                ("products.json", jsonProducts),
                ("sales.json", jsonSales),
                ("sale_items.json", jsonItems),
                ("stock_movements.json", jsonMovements),
                ("sync_log.json", jsonSync)
            ]
            for (name, data) in jsonFiles {
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            }
            CSVExportPanel.finish(folder: folder)
            if CSVExportPanel.usesShareSheet {
                message = "共有シートを開きました（\(files.count + jsonFiles.count)ファイル）"
            } else {
                message = "書き出しました: \(folder.lastPathComponent)（\(files.count + jsonFiles.count)ファイル）"
            }
        } catch {
            message = "書き出しに失敗しました: \(error.localizedDescription)"
        }
    }

    @MainActor
    func exportPriceList() {
        guard requireAdmin("価格一覧CSV") else { return }
        let csv = CSVExport.priceListCSV(inventory)
        if let url = CSVExportPanel.save(csv, suggestedName: "price_list.csv") {
            message = CSVExportPanel.usesShareSheet
                ? "共有シートを開きました"
                : "保存しました: \(url.lastPathComponent)"
        } else {
            message = "保存をキャンセルしました"
        }
    }

    @MainActor
    func exportMaster() {
        guard requireAdmin("マスタ書き出し") else { return }
        guard let dir = CSVExportPanel.chooseDirectory() else { return }
        let folder = dir.appendingPathComponent(exportFolderName(), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let files: [(String, String)] = [
                ("product_groups.csv", CSVExport.groupsCSV(groups)),
                ("product_types.csv", CSVExport.typesCSV(types)),
                ("products.csv", CSVExport.productsCSV(inventory))
            ]
            for (name, csv) in files {
                try Data(csv.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            // A-13 の列名（snake_case）に合わせる。`sale_id` などの明示キーはそのまま。
            encoder.keyEncodingStrategy = .convertToSnakeCase
            try encoder.encode(groups).write(to: folder.appendingPathComponent("product_groups.json"), options: .atomic)
            try encoder.encode(types).write(to: folder.appendingPathComponent("product_types.json"), options: .atomic)
            try encoder.encode(inventory).write(to: folder.appendingPathComponent("products.json"), options: .atomic)
            CSVExportPanel.finish(folder: folder)
            if CSVExportPanel.usesShareSheet {
                message = "共有シートを開きました"
            } else {
                message = "マスタを書き出しました: \(folder.lastPathComponent)"
            }
        } catch {
            message = "書き出しに失敗しました: \(error.localizedDescription)"
        }
    }

    /// 取り込み用の空CSV雛形（A-18）。ヘッダだけの3ファイルを書き出す。
    @MainActor
    func exportCSVTemplates() {
        guard requireAdmin("CSV雛形") else { return }
        guard let dir = CSVExportPanel.chooseDirectory() else { return }
        let folder = dir.appendingPathComponent("craftill-csv-template", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let files: [(String, String)] = [
                ("product_groups.csv", CSVExport.groupsCSV([])),
                ("product_types.csv", CSVExport.typesCSV([])),
                ("products.csv", CSVExport.productsCSV([]))
            ]
            for (name, csv) in files {
                try Data(csv.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
            }
            CSVExportPanel.finish(folder: folder)
            message = CSVExportPanel.usesShareSheet
                ? "CSV雛形を共有しました"
                : "CSV雛形を書き出しました: \(folder.lastPathComponent)"
        } catch {
            message = "CSV雛形の書き出しに失敗しました: \(error.localizedDescription)"
        }
    }

    @MainActor
    func exportSettlement(from: Date, to: Date) {
        guard requireAdmin("グループ別精算CSV") else { return }
        let csv = CSVExport.settlementCSV(reportRows(from: from, to: to), from: from, to: to)
        if let url = CSVExportPanel.save(csv, suggestedName: "settlement.csv") {
            message = CSVExportPanel.usesShareSheet
                ? "共有シートを開きました"
                : "保存しました: \(url.lastPathComponent)"
        }
    }

    @MainActor
    func exportSatsReconciliation(from: Date, to: Date) {
        guard requireAdmin("sats照合CSV") else { return }
        let csv = CSVExport.satsReconciliationCSV(satsReconciliationSales(from: from, to: to))
        if let url = CSVExportPanel.save(csv, suggestedName: "sats_reconciliation.csv") {
            message = CSVExportPanel.usesShareSheet
                ? "共有シートを開きました"
                : "保存しました: \(url.lastPathComponent)"
        }
    }

    // MARK: 公開サイト送信（A-14）

    func saveSyncSettings() {
        let endpoint = syncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = syncToken.trimmingCharacters(in: .whitespacesAndNewlines)
        SyncSettings.endpoint = endpoint
        let tokenSaved = SyncSettings.saveToken(token)
        syncEndpoint = endpoint
        syncToken = token
        message = tokenSaved
            ? "送信先を保存しました"
            : "送信先は保存しましたが、トークンを Keychain に保存できませんでした"
    }

    /// 実際にスナップショットを送信する。成功ログは HTTP 2xx のときだけ残す。
    /// 失敗しても会計・在庫には影響させない（A-14）。
    func sendSnapshot() {
        let snapshot = makeSnapshot(types: types, inventory: inventory, now: Date())

        let endpoint = syncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else {
            recordSyncResult(snapshot: snapshot, error: "送信先が未設定です（送信先URLを保存してください）")
            return
        }
        guard let url = URL(string: endpoint), url.scheme != nil else {
            recordSyncResult(snapshot: snapshot, error: "送信先URLが不正です")
            return
        }
        guard isOnline else {
            recordSyncResult(snapshot: snapshot, error: "通信エラー（オフライン）")
            return
        }

        message = "送信中…"
        let sender = SnapshotSender(endpoint: url, token: syncToken)
        sender.send(snapshot) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.recordSyncResult(snapshot: snapshot, error: nil)
                    self.message = "公開サイトへ送信しました（商品 \(snapshot.products.count)件）"
                case .failure(let error):
                    self.recordSyncResult(snapshot: snapshot, error: error.localizedDescription)
                    self.message = "送信に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    private func recordSyncResult(snapshot: Snapshot, error: String?) {
        let entry = recordSync(&syncLog, ids: &ids, snapshot: snapshot, error: error, at: Date())
        do {
            try db?.save(sync: entry)
        } catch {
            message = "送信ログを保存できませんでした: \(error.localizedDescription)"
        }
        if error == nil { lastSyncAt = entry.at }
    }
}