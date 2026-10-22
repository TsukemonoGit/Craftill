import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - 画面・ダイアログ・補助型

enum Screen: Hashable {
    case initialLaunch, register, menu, edit, csvImport, report
    case salesHistory, stockAdjust, priceList, qrLabels, sync
}

enum Dialog: Identifiable {
    case deleteLine(CartDelete)
    case zeroQty(CartDelete)
    case suspend
    case suspendSatsConfirmed
    case satsConfirm
    case voidSale(String)
    case message(String)

    var id: String {
        switch self {
        case .deleteLine: return "deleteLine"
        case .zeroQty: return "zeroQty"
        case .suspend: return "suspend"
        case .suspendSatsConfirmed: return "suspendSatsConfirmed"
        case .satsConfirm: return "satsConfirm"
        case .voidSale: return "voidSale"
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
    @Published var isOnline = true
    @Published var pin: String? = nil
    @Published var isUnlocked = false

    // マスタ
    @Published var groups: [ProductGroup] = []
    @Published var types: [ProductType] = []
    @Published var inventory: [Product] = []
    @Published var selectedTypeId: String = ""

    // 会計
    @Published var saleState: SaleState = .idle
    @Published var cart: [CartLine] = []
    @Published var cashReceived = 0
    @Published var satsStartedAt = Date()
    @Published var satsConfirmedAt: Date? = nil
    @Published var done: DoneInfo? = nil

    // 記録
    @Published var sales: [Sale] = []
    @Published var saleItems: [SaleItem] = []
    @Published var movements: [StockMovement] = []
    @Published var syncLog: [SyncLogEntry] = []
    @Published var lastSyncAt: Date? = nil

    private var ids = IdSequencer()
    private let db = Database.shared
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    private static let activeSaleKey = "craftill.activeSale"

    init() {
        pin = PinStore.load()
        isUnlocked = pin == nil
        loadMaster()
        restoreActiveSale()
        ids = Self.makeSequencer(sales: sales, movements: movements,
                                 syncLog: syncLog, cart: cart)

        if pin != nil { screen = .register }

        // 会計状態は更新のたびに保存する（A-3）。willChange の直後に読む。
        objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async { self.saveActiveSale() }
            }
            .store(in: &cancellables)
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
        let adhocSeq = cart.filter { $0.isAdhoc }
            .compactMap { Int($0.id.replacingOccurrences(of: "ADHOC-", with: "")) }
            .max() ?? 0
        return IdSequencer(saleCounters: counters, movementSeq: movementSeq,
                           logSeq: logSeq, adhocSeq: adhocSeq)
    }

    // MARK: 会計状態の保存・復元

    private func saveActiveSale() {
        switch saleState {
        case .idle, .done, .suspended:
            clearActiveSale()
        default:
            let ctx = SaleContext(state: saleState, cart: cart,
                                  satsConfirmedAt: satsConfirmedAt,
                                  confirmedSats: satsConfirmedAt == nil ? nil : totals.sats)
            let active = ActiveSale(context: ctx, cashReceived: cashReceived,
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
        switch ctx.state {
        case .idle, .done, .suspended:
            clearActiveSale()
        default:
            saleState = ctx.state
            cart = ctx.cart
            satsConfirmedAt = ctx.satsConfirmedAt
            cashReceived = active.cashReceived
            satsStartedAt = active.satsStartedAt ?? Date()
            screen = .register
        }
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

    // MARK: 画面遷移

    func go(_ s: Screen) { screen = s }

    func openMenu() {
        guard saleState == .idle else { return }
        screen = .menu
    }

    func exitAdmin() {
        screen = pin == nil ? .initialLaunch : .menu
    }

    func setPin(_ a: String, confirm b: String) {
        guard a.count >= 4 else { message = "PINは4文字以上で入力してください"; return }
        guard a == b else { message = "PINが一致しません"; return }
        let saved = PinStore.save(a)
        pin = a
        isUnlocked = true
        message = saved ? "PINを設定しました" : "PINを保存できませんでした（この起動中のみ有効）"
        screen = .register
    }

    /// 起動時のロック解除
    @discardableResult
    func unlock(_ entered: String) -> Bool {
        guard let pin else {
            isUnlocked = true
            return true
        }
        guard entered == pin else {
            message = "PINが違います"
            return false
        }
        isUnlocked = true
        message = ""
        return true
    }

    func lock() {
        guard pin != nil else { return }
        isUnlocked = false
        pinPrompt = nil
        dialog = nil
    }

    func requirePin(_ title: String, _ action: @escaping () -> Void) {
        pinPrompt = PinPrompt(title: title, onSuccess: action)
    }

    func submitPin(_ s: String) {
        if verifyPin(s) {
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

    // MARK: ダイアログ

    func closeDialog() {
        dialog = nil
        dialogPin = ""
    }

    func confirmDialog(_ d: Dialog) {
        switch d {
        case .deleteLine(let x), .zeroQty(let x):
            confirmDelete(x)
            closeDialog()
        case .suspend:
            resetSale()
            message = "会計を中断しました"
            closeDialog()
        case .suspendSatsConfirmed:
            guard verifyPin(dialogPin) else { message = "PINが違います"; return }
            recordConfirmedSuspend(pin: dialogPin)
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
        case .message:
            closeDialog()
        }
    }

    // MARK: カート

    func addToCart(_ p: Product) {
        guard saleState == .idle || saleState == .scanning else {
            message = "この状態では商品を追加できません"
            return
        }
        let result = add(product: p, qty: 1, cart: &cart, inventory: inventory, types: types)
        applyEdit(result, zero: false)
    }

    func normalizeID(_ raw: String) -> String {
        let half = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        let s = half.uppercased().filter { !$0.isWhitespace }
        if s.contains("-") { return s }
        for t in types.sorted(by: { $0.idPrefix.count > $1.idPrefix.count }) where s.hasPrefix(t.idPrefix) {
            let rest = String(s.dropFirst(t.idPrefix.count))
            if let n = Int(rest) {
                let num = String(n)
                return "\(t.idPrefix)-" + String(repeating: "0", count: max(0, t.idDigits - num.count)) + num
            }
        }
        return s
    }

    func addByID(_ raw: String) {
        let id = normalizeID(raw)
        guard let p = inventory.first(where: { $0.id == id }) else {
            message = "存在しないID: \(raw)"
            return
        }
        addToCart(p)
    }

    func increaseQty(_ i: Int) {
        guard saleState == .scanning else { return }
        applyEdit(increase(at: i, cart: &cart, inventory: inventory, types: types), zero: false)
    }

    func decreaseQty(_ i: Int) {
        guard saleState == .scanning else { return }
        applyEdit(decrease(at: i, cart: &cart, inventory: inventory, types: types), zero: true)
    }

    func removeLine(_ i: Int) {
        guard saleState == .scanning else { return }
        applyEdit(remove(at: i, cart: cart), zero: false)
    }

    private func applyEdit(_ e: CartEdit, zero: Bool) {
        switch e {
        case .applied(let m):
            message = m
            if saleState == .idle && !cart.isEmpty { saleState = .scanning }
        case .needsConfirm(let d):
            dialog = zero ? .zeroQty(d) : .deleteLine(d)
        case .rejected(let m):
            message = m
        }
    }

    private func confirmDelete(_ d: CartDelete) {
        message = performDelete(d, cart: &cart)
        if cart.isEmpty { saleState = .idle }
    }

    func addAdhoc(priceJpy: Int, priceSats: Int?, name: String, groupId: String?, qty: Int) {
        guard saleState == .idle || saleState == .scanning else { return }
        let line = CartLine.adhoc(id: ids.nextAdhocID(),
                                  name: name.isEmpty ? "野良" : name,
                                  priceJpy: priceJpy, priceSats: priceSats,
                                  groupId: groupId, qty: qty)
        cart.append(line)
        if saleState == .idle { saleState = .scanning }
        message = "\(line.name) を追加しました"
    }

    // MARK: 会計の遷移（仮）

    func proceedToPayment() {
        guard saleState == .scanning, !cart.isEmpty else { return }
        saleState = .choosingPayment
    }

    func backToScan() {
        guard saleState == .choosingPayment else { return }
        saleState = .scanning
    }

    func chooseCash() {
        guard saleState == .choosingPayment else { return }
        cashReceived = 0
        saleState = .cashInput
    }

    func chooseSats() {
        guard saleState == .choosingPayment, canPayBySats else { return }
        satsStartedAt = Date()
        satsConfirmedAt = nil
        saleState = .satsWaiting
    }

    func reselectMethod() {
        guard saleState == .satsWaiting else { return }
        saleState = .choosingPayment
    }

    func pressKey(_ k: String) {
        switch k {
        case "C": cashReceived = 0
        case "00": cashReceived = min(cashReceived * 100, 9_999_999)
        default:
            if let d = Int(k) { cashReceived = min(cashReceived * 10 + d, 9_999_999) }
        }
    }

    func addCash(_ n: Int) { cashReceived = min(cashReceived + n, 9_999_999) }

    func confirmCash() {
        guard canConfirmCash else { return }
        if saleState == .cashInput { complete(method: .cash) }
        else if saleState == .mixedCashInput { complete(method: .mixed) }
    }

    func askSatsConfirm() { dialog = .satsConfirm }

    private func approveSats() {
        guard saleState == .satsWaiting else { return }
        satsConfirmedAt = Date()
        if totals.cashForSats > 0 {
            cashReceived = 0
            saleState = .mixedCashInput
        } else {
            complete(method: .lightning)
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
        switch saleState {
        case .mixedCashInput:
            dialogPin = ""
            dialog = .suspendSatsConfirmed
        case .scanning, .choosingPayment, .cashInput, .satsWaiting:
            dialog = .suspend
        default:
            break
        }
    }

    func nextSale() {
        resetSale()
        done = nil
    }

    private func resetSale() {
        cart = []
        cashReceived = 0
        satsConfirmedAt = nil
        saleState = .idle
        clearActiveSale()
    }

    private func complete(method: PaymentMethod) {
        let before = movements.count
        let chooseSats = method != .cash
        let received: Int? = (method == .cash || method == .mixed) ? cashReceived : nil
        let confirmed: Date? = method == .cash ? nil : satsConfirmedAt

        let result = commitSale(cart: cart,
                                inventory: &inventory,
                                movements: &movements,
                                sales: &sales,
                                items: &saleItems,
                                ids: &ids,
                                types: types,
                                chooseSats: chooseSats,
                                receivedJpy: received,
                                confirmedAt: confirmed,
                                now: Date())

        switch result {
        case .failure(let problems):
            message = problems.joined(separator: "\n")
        case .success(let sale, let items, _):
            let newMovements = Array(movements[before...])
            if let db {
                do {
                    try db.persistCommit(sale: sale, items: items,
                                         inventory: inventory, movements: newMovements)
                } catch {
                    message = "販売は記録しましたが保存に失敗しました: \(error.localizedDescription)"
                }
            }
            done = DoneInfo(saleId: sale.id, method: sale.method,
                            totalSats: sale.totalSats, cashPart: sale.totalJpy,
                            received: sale.receivedJpy, change: sale.changeJpy)
            saleState = .done
            clearActiveSale()
        }
    }

    private func recordConfirmedSuspend(pin entered: String) {
        let result = suspendSale(cart: cart,
                                 ids: &ids,
                                 correctPIN: pin ?? "",
                                 pin: entered,
                                 sales: &sales,
                                 items: &saleItems,
                                 chooseSats: true,
                                 confirmedAt: satsConfirmedAt,
                                 now: Date())
        switch result {
        case .failure(let m):
            message = m
        case .success(let sale, let items):
            guard let sale else { return }
            if let db {
                do {
                    try db.persistCommit(sale: sale, items: items,
                                         inventory: inventory, movements: [])
                } catch {
                    message = "中断は記録しましたが保存に失敗しました: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: 販売取消・返金・在庫調整

    private func performVoidSale(_ id: String, pin entered: String) {
        let before = movements.count
        let result = voidSale(saleId: id,
                              correctPIN: pin ?? "",
                              pin: entered,
                              sales: &sales,
                              items: saleItems,
                              inventory: &inventory,
                              movements: &movements,
                              ids: &ids,
                              types: types,
                              at: Date())
        switch result {
        case .failure(let m):
            message = m
        case .success(let memo):
            if let sale = sales.first(where: { $0.id == id }), let db {
                do {
                    try db.persistVoid(sale: sale, inventory: inventory,
                                       movements: Array(movements[before...]))
                } catch {
                    message = "取り消しましたが保存に失敗しました: \(error.localizedDescription)"
                }
            }
            message = memo.isEmpty ? "販売取消: \(id)" : "販売取消: \(id)\n" + memo.joined(separator: "\n")
        }
    }

    func toggleRefunded(_ id: String) {
        guard let i = sales.firstIndex(where: { $0.id == id }) else { return }
        sales[i].refunded.toggle()
        try? db?.persistSale(sales[i])
    }

    func performStockAdjustment(productId: String, newStock: Int, reason: String) -> String? {
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else { return "理由は必須です" }
        let before = movements.count
        let currentPIN = pin ?? ""
        let result = adjustStock(productId: productId, newStock: newStock, reason: reason,
                                 correctPIN: currentPIN, pin: currentPIN,
                                 inventory: &inventory, movements: &movements,
                                 ids: &ids, types: types, at: Date())
        switch result {
        case .failure(let m):
            return m
        case .success(let memo):
            try? db?.persistAdjust(inventory: inventory,
                                   movements: Array(movements[before...]))
            return memo == "変化なし" ? nil : nil
        }
    }

    // MARK: 編集（グループ・種類・商品）

    func isGroupInUse(_ id: String) -> Bool {
        types.contains { $0.groupId == id } || saleItems.contains { $0.groupId == id }
    }

    func addGroup(id: String, label: String) -> String? {
        guard id.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil else { return "グループIDは半角英数字とアンダースコアのみ" }
        guard !groups.contains(where: { $0.groupId == id }) else { return "グループIDが重複しています" }
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return "ラベルは必須です" }
        let group = ProductGroup(groupId: id, label: label)
        groups.append(group)
        try? db?.save(group: group)
        return nil
    }

    func renameGroup(id: String, label: String) -> String? {
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return "ラベルは必須です" }
        guard let i = groups.firstIndex(where: { $0.groupId == id }) else { return "グループがありません" }
        groups[i].label = label
        try? db?.save(group: groups[i])
        return nil
    }

    func deleteGroup(_ id: String) {
        guard !isGroupInUse(id) else { message = "使用中のグループは削除できません"; return }
        groups.removeAll { $0.groupId == id }
        try? db?.deleteGroup(id: id)
    }

    func isTypeLocked(_ typeId: String) -> Bool {
        inventory.contains { $0.typeId == typeId } || saleItems.contains { $0.typeId == typeId }
    }

    func addType(typeId: String, name: String, prefix: String, digits: Int, mode: StockMode,
                 labels: [String], groupId: String, nextNo: Int) -> String? {
        guard typeId.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil else { return "種類IDは半角英数字とアンダースコアのみ" }
        guard !types.contains(where: { $0.typeId == typeId }) else { return "種類IDが重複しています" }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "表示名は必須です" }
        guard prefix.range(of: "^[A-Z0-9]+$", options: .regularExpression) != nil else { return "接頭辞は半角英大文字・数字のみ" }
        guard !types.contains(where: { $0.idPrefix == prefix }) else { return "接頭辞が重複しています" }
        guard digits >= 1 else { return "桁数は1以上" }
        guard nextNo >= 1 else { return "開始番号は1以上" }
        guard labelsPacked(labels) else { return "属性ラベルは左から詰めてください" }
        let type = ProductType(typeId: typeId, name: name, idPrefix: prefix, idDigits: digits, stockMode: mode,
                               attrLabel1: labels[0].isEmpty ? nil : labels[0],
                               attrLabel2: labels[1].isEmpty ? nil : labels[1],
                               attrLabel3: labels[2].isEmpty ? nil : labels[2],
                               groupId: groupId.isEmpty ? nil : groupId, nextNo: nextNo,
                               updatedAt: Date())
        types.append(type)
        try? db?.save(type: type)
        return nil
    }

    func updateType(typeId: String, name: String, labels: [String], groupId: String) -> String? {
        guard let i = types.firstIndex(where: { $0.typeId == typeId }) else { return "種類がありません" }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "表示名は必須です" }
        guard labelsPacked(labels) else { return "属性ラベルは左から詰めてください" }
        types[i].name = name
        types[i].attrLabel1 = labels[0].isEmpty ? nil : labels[0]
        types[i].attrLabel2 = labels[1].isEmpty ? nil : labels[1]
        types[i].attrLabel3 = labels[2].isEmpty ? nil : labels[2]
        types[i].groupId = groupId.isEmpty ? nil : groupId
        types[i].updatedAt = Date()
        try? db?.save(type: types[i])
        return nil
    }

    private func labelsPacked(_ l: [String]) -> Bool {
        guard l.count == 3 else { return false }
        if l[1].isEmpty && !l[2].isEmpty { return false }
        if l[0].isEmpty && !l[1].isEmpty { return false }
        return true
    }

    func addProduct(typeId: String, name: String, priceJpy: Int, priceSats: Int?,
                    attrs: [String?], stock: Int?, isPublic: Bool) -> String? {
        guard let ti = types.firstIndex(where: { $0.typeId == typeId }) else { return "種類がありません" }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "商品名は必須です" }
        guard priceJpy >= 1 else { return "円価格は1以上" }
        if let s = priceSats, s < 1 { return "sats価格は1以上" }
        let t = types[ti]
        let labels = [t.attrLabel1, t.attrLabel2, t.attrLabel3]
        for k in 0..<3 where labels[k] == nil && attrs[k] != nil { return "ラベルのない属性に値があります" }
        var initial: Int? = nil
        switch t.stockMode {
        case .none: initial = nil
        case .unique:
            guard let s = stock, (0...1).contains(s) else { return "一点物型の初期在庫は0または1" }
            initial = s
        case .counted:
            guard let s = stock, s >= 0 else { return "初期在庫は0以上" }
            initial = s
        }
        guard let newId = ids.makeProductID(for: t) else { return "番号が桁数を超えています" }
        let product = Product(id: newId, typeId: typeId, name: name, priceJpy: priceJpy, priceSats: priceSats,
                              stock: initial, attr1: attrs[0], attr2: attrs[1], attr3: attrs[2],
                              imageRef: nil, isPublic: isPublic, updatedAt: Date())
        inventory.append(product)
        types[ti].nextNo += 1
        types[ti].updatedAt = Date()
        try? db?.save(type: types[ti])
        try? db?.save(product: product)
        if let s = initial, s > 0 {
            let m = StockMovement(id: ids.nextMovementID(), productId: newId,
                                  delta: s, reason: .initial, saleId: nil, at: Date())
            movements.append(m)
            try? db?.save(movement: m)
        }
        return nil
    }

    func updateProduct(id: String, name: String, priceJpy: Int, priceSats: Int?,
                       attrs: [String?], isPublic: Bool) -> String? {
        guard let i = inventory.firstIndex(where: { $0.id == id }) else { return "商品がありません" }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "商品名は必須です" }
        guard priceJpy >= 1 else { return "円価格は1以上" }
        if let s = priceSats, s < 1 { return "sats価格は1以上" }
        inventory[i].name = name
        inventory[i].priceJpy = priceJpy
        inventory[i].priceSats = priceSats
        inventory[i].attr1 = attrs[0]
        inventory[i].attr2 = attrs[1]
        inventory[i].attr3 = attrs[2]
        inventory[i].isPublic = isPublic
        inventory[i].updatedAt = Date()
        try? db?.save(product: inventory[i])
        return nil
    }

    var productsWithoutImage: [Product] { inventory.filter { $0.imageRef == nil } }

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

    func completedSales(from: Date, to: Date) -> [Sale] {
        let a = DayKey.string(from: min(from, to)), b = DayKey.string(from: max(from, to))
        return sales.filter {
            guard $0.status == .completed, let at = $0.completedAt else { return false }
            let d = DayKey.string(from: at)
            return d >= a && d <= b
        }
    }

    func voidedSales(from: Date, to: Date, confirmedOnly: Bool) -> [Sale] {
        let a = DayKey.string(from: min(from, to)), b = DayKey.string(from: max(from, to))
        return sales.filter {
            guard $0.status == .voided else { return false }
            let isConfirmedAbort = $0.completedAt == nil
            guard isConfirmedAbort == confirmedOnly else { return false }
            guard let at = $0.completedAt ?? $0.confirmedAt else { return false }
            let d = DayKey.string(from: at)
            return d >= a && d <= b
        }
    }

    /// sats照合CSVの対象。完了したsats会計と、sats確認済みで中断した会計（A-8）。
    func satsReconciliationSales(from: Date, to: Date) -> [Sale] {
        (completedSales(from: from, to: to)
            + voidedSales(from: from, to: to, confirmedOnly: true))
            .filter { $0.totalSats != nil }
            .sorted {
                ($0.completedAt ?? $0.confirmedAt ?? .distantPast)
                    < ($1.completedAt ?? $1.confirmedAt ?? .distantPast)
            }
    }

    func reportRows(from: Date, to: Date) -> [ReportRow] {
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

    // MARK: エクスポート

    private func exportFolderName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "craftill-export-" + f.string(from: Date())
    }

    @MainActor
    func exportAll() {
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
        let csv = CSVExport.settlementCSV(reportRows(from: from, to: to))
        if let url = CSVExportPanel.save(csv, suggestedName: "settlement.csv") {
            message = CSVExportPanel.usesShareSheet
                ? "共有シートを開きました"
                : "保存しました: \(url.lastPathComponent)"
        }
    }

    @MainActor
    func exportSatsReconciliation(from: Date, to: Date) {
        let csv = CSVExport.satsReconciliationCSV(satsReconciliationSales(from: from, to: to))
        if let url = CSVExportPanel.save(csv, suggestedName: "sats_reconciliation.csv") {
            message = CSVExportPanel.usesShareSheet
                ? "共有シートを開きました"
                : "保存しました: \(url.lastPathComponent)"
        }
    }

    // MARK: 公開サイト送信（仮）

    func sendSnapshot() {
        let ok = isOnline
        let entry = SyncLogEntry(id: ids.nextLogID(), at: Date(),
                                 result: ok ? .success : .failed,
                                 detail: ok ? "" : "通信エラー")
        syncLog.insert(entry, at: 0)
        try? db?.save(sync: entry)
        if ok { lastSyncAt = Date() }
    }
}