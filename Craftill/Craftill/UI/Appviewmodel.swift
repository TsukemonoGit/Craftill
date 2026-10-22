import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - 画面・ダイアログ・補助型

enum Screen: Hashable {
    case initialLaunch, register, menu, edit, csvImport, report
    case salesHistory, stockAdjust, priceList, sync
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

    // マスタ
    @Published var groups: [ProductGroup] = MockData.groups
    @Published var types: [ProductType] = MockData.types
    @Published var inventory: [Product] = MockData.products
    @Published var selectedTypeId: String = MockData.types.first?.typeId ?? ""

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
        pin = a
        message = "PINを設定しました"
        screen = .register
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
            recordConfirmedSuspend()
            resetSale()
            message = "sats確認済みの会計を中断しました（記録あり）"
            closeDialog()
        case .satsConfirm:
            closeDialog()
            approveSats()
        case .voidSale(let id):
            guard verifyPin(dialogPin) else { message = "PINが違います"; return }
            voidSale(id)
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
    }

    private func makeItems(saleId: String, method: PaymentMethod) -> [SaleItem] {
        cart.enumerated().map { (n, line) in
            let paidIn: PaidIn = (method == .cash || line.unitPriceSats == nil) ? .jpy : .sats
            return SaleItem(id: self.ids.itemID(saleId: saleId, n: n + 1), saleId: saleId,
                            itemType: line.itemType, typeId: line.typeId, groupId: line.groupId,
                            productId: line.isAdhoc ? nil : line.id, qty: line.qty,
                            unitPriceJpy: line.unitPriceJpy, unitPriceSats: line.unitPriceSats,
                            paidIn: paidIn, nameSnapshot: line.name)
        }
    }

    private func complete(method: PaymentMethod) {
        let now = Date()
        let sid = ids.nextSaleID(at: now)
        let t = totals
        let isCash = method == .cash
        let cashPart: Int? = isCash ? t.cash : (method == .mixed ? t.cashForSats : nil)
        let received: Int? = cashPart == nil ? nil : cashReceived
        let changeValue: Int? = cashPart == nil ? nil : change
        let sale = Sale(id: sid, status: .completed, method: method,
                        totalJpy: cashPart, totalSats: isCash ? nil : t.sats,
                        receivedJpy: received, changeJpy: changeValue,
                        confirmedAt: isCash ? nil : satsConfirmedAt, refunded: false, completedAt: now)
        sales.append(sale)
        saleItems += makeItems(saleId: sid, method: method)
        for line in cart where !line.isAdhoc {
            guard let mode = stockMode(of: line, in: types), mode != StockMode.none,
                  let idx = inventory.firstIndex(where: { $0.id == line.id }) else { continue }
            inventory[idx].stock = (inventory[idx].stock ?? 0) - line.qty
            movements.append(StockMovement(id: ids.nextMovementID(), productId: line.id,
                                           delta: -line.qty, reason: .sale, saleId: sid, at: now))
        }
        done = DoneInfo(saleId: sid, method: method, totalSats: sale.totalSats,
                        cashPart: cashPart, received: received, change: changeValue)
        saleState = .done
    }

    private func recordConfirmedSuspend() {
        let sid = ids.nextSaleID(at: Date())
        let t = totals
        let sale = Sale(id: sid, status: .voided, method: .mixed,
                        totalJpy: t.cashForSats, totalSats: t.sats,
                        receivedJpy: nil, changeJpy: nil,
                        confirmedAt: satsConfirmedAt, refunded: false, completedAt: nil)
        sales.append(sale)
        saleItems += makeItems(saleId: sid, method: .mixed)
    }

    // MARK: 販売取消・返金・在庫調整

    func voidSale(_ id: String) {
        guard let i = sales.firstIndex(where: { $0.id == id }), sales[i].status == .completed else { return }
        sales[i].status = .voided
        for item in saleItems where item.saleId == id && item.itemType == .registered {
            guard let pid = item.productId,
                  let ti = types.firstIndex(where: { $0.typeId == item.typeId }),
                  types[ti].stockMode != StockMode.none,
                  let pi = inventory.firstIndex(where: { $0.id == pid }) else { continue }
            inventory[pi].stock = (inventory[pi].stock ?? 0) + item.qty
            movements.append(StockMovement(id: ids.nextMovementID(), productId: pid,
                                           delta: item.qty, reason: .void, saleId: id, at: Date()))
        }
        message = "販売取消: \(id)"
    }

    func toggleRefunded(_ id: String) {
        guard let i = sales.firstIndex(where: { $0.id == id }) else { return }
        sales[i].refunded.toggle()
    }

    func adjustStock(productId: String, newStock: Int, reason: String) -> String? {
        guard let i = inventory.firstIndex(where: { $0.id == productId }) else { return "商品がありません" }
        guard !reason.trimmingCharacters(in: .whitespaces).isEmpty else { return "理由は必須です" }
        let mode = inventory[i].stockMode(in: types)
        switch mode {
        case .none: return "在庫管理なし型は対象外です"
        case .unique: if !(0...1).contains(newStock) { return "一点物型は0または1です" }
        case .counted: if newStock < 0 { return "在庫は0以上です" }
        }
        let delta = newStock - (inventory[i].stock ?? 0)
        inventory[i].stock = newStock
        movements.append(StockMovement(id: ids.nextMovementID(), productId: productId,
                                       delta: delta, reason: .adjust, saleId: nil, at: Date()))
        return nil
    }

    // MARK: 編集（グループ・種類・商品）

    func isGroupInUse(_ id: String) -> Bool {
        types.contains { $0.groupId == id } || saleItems.contains { $0.groupId == id }
    }

    func addGroup(id: String, label: String) -> String? {
        guard id.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil else { return "グループIDは半角英数字とアンダースコアのみ" }
        guard !groups.contains(where: { $0.groupId == id }) else { return "グループIDが重複しています" }
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return "ラベルは必須です" }
        groups.append(ProductGroup(groupId: id, label: label))
        return nil
    }

    func renameGroup(id: String, label: String) -> String? {
        guard !label.trimmingCharacters(in: .whitespaces).isEmpty else { return "ラベルは必須です" }
        guard let i = groups.firstIndex(where: { $0.groupId == id }) else { return "グループがありません" }
        groups[i].label = label
        return nil
    }

    func deleteGroup(_ id: String) {
        guard !isGroupInUse(id) else { message = "使用中のグループは削除できません"; return }
        groups.removeAll { $0.groupId == id }
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
        types.append(ProductType(typeId: typeId, name: name, idPrefix: prefix, idDigits: digits, stockMode: mode,
                                 attrLabel1: labels[0].isEmpty ? nil : labels[0],
                                 attrLabel2: labels[1].isEmpty ? nil : labels[1],
                                 attrLabel3: labels[2].isEmpty ? nil : labels[2],
                                 groupId: groupId.isEmpty ? nil : groupId, nextNo: nextNo))
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
        inventory.append(Product(id: newId, typeId: typeId, name: name, priceJpy: priceJpy, priceSats: priceSats,
                                 stock: initial, attr1: attrs[0], attr2: attrs[1], attr3: attrs[2],
                                 imageRef: nil, isPublic: isPublic, updatedAt: Date()))
        types[ti].nextNo += 1
        if let s = initial, s > 0 {
            movements.append(StockMovement(id: ids.nextMovementID(), productId: newId,
                                           delta: s, reason: .initial, saleId: nil, at: Date()))
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
        return nil
    }

    var productsWithoutImage: [Product] { inventory.filter { $0.imageRef == nil } }

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

    // MARK: 公開サイト送信（仮）

    func sendSnapshot() {
        let ok = isOnline
        syncLog.insert(SyncLogEntry(id: ids.nextLogID(), at: Date(),
                                    result: ok ? .success : .failed,
                                    detail: ok ? "" : "通信エラー"), at: 0)
        if ok { lastSyncAt = Date() }
    }
}