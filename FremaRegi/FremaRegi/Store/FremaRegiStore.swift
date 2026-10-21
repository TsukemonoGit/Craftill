import Foundation

// ════════════════════════════════════════════════════════════
// アプリ全体ストア（@Observable・iOS 17 / macOS 14 以上）
// Types.swift（型）＋ StandardLogic.swift（標準ロジック）＋
// CartEdit.swift（追加・編集）＋ StateMachine.swift（A-4 の状態機械）を
// つないで、画面が「ボタンが押された」だけを伝えられるようにする。
// 状態の保持・復元は A-3（更新のたびに保存／起動時に復元）。
// ════════════════════════════════════════════════════════════

#if canImport(Observation)
import Observation

@available(iOS 17.0, macOS 14.0, *)
@MainActor
@Observable
final class FremaRegiStore {

    // ── データ（端末内DB相当）──
    var groups: [ProductGroup] = []
    var types: [ProductType] = []
    var inventory: [Product] = []
    var sales: [Sale] = []
    var items: [SaleItem] = []
    var movements: [StockMovement] = []
    var syncLog: [SyncLogEntry] = []
    var ids = IdSequencer()

    // ── 会計（A-4 の状態機械。cart は ctx を見に行く）──
    var ctx = SaleContext()
    var cart: [CartLine] { ctx.cart }
    var state: SaleState { ctx.state }
    /// 待機中のみ編集可（A-1、C-6 #52）
    var isIdle: Bool { ctx.state == .idle }

    // ── PIN（A-11）──
    var pinSet: Bool = false

    // ── 野良の採番は IdSequencer.adhocSeq。IDは追加した瞬間に採番（A-19-10）──

    // ── 通信（A-10：sats可否は通信の有無で決める）──
    var hasConnectivity: Bool = true
    /// sats払いを選べるか = カートにsats単価のある行がある × 通信あり（A-10、C-6 #68）
    var satsAvailable: Bool { cart.canPayBySats() && hasConnectivity }

    // ── 直近の結果メッセージ（画面のトースト用）──
    var lastMessage: String?

    let persistence: Persistence
    private let kv: KVClient

    init(persistence: Persistence = Persistence(),
         kv: KVClient = KVClient(endpoint: AppKVConfig.endpoint)) {
        self.persistence = persistence
        self.kv = kv
        let pin = PinStore()
        pinSet = pin.isSet
        // 起動時の復元（A-3：OS終了・再起動後も直前の状態へ）
        if let data = try? persistence.loadRegistry() {
            groups = data.groups; types = data.types; inventory = data.inventory
            sales = data.sales; items = data.items; movements = data.movements
            syncLog = data.syncLog; ids = data.ids
        }
        // 同梱画像の対応付け（A-1・P2対策）: imageRef が nil の商品を商品IDで再スキャンし、
        // バンドル／originals/ にある画像を実体パスとして紐づける。hasImage の導出も追随する。
        if persistence.attachMissingImages(to: &inventory) > 0 {
            let reg = RegistryData(groups: groups, types: types, inventory: inventory,
                                   sales: sales, items: items, movements: movements,
                                   syncLog: syncLog, ids: ids)
            try? persistence.saveRegistry(reg)   // saveAll() は init 内では呼べないため直接保存
        }
        if let saved = try? persistence.saleContextStore.load() {
            ctx = saved
        }
    }

    // ════════════ 保存（更新のたびに呼ぶ・A-3）════════════

    func saveAll() {
        let reg = RegistryData(groups: groups, types: types, inventory: inventory,
                               sales: sales, items: items, movements: movements,
                               syncLog: syncLog, ids: ids)
        try? persistence.saveRegistry(reg)
        try? persistence.saleContextStore.save(ctx)
    }

    // ════════════ PIN ════════════

    func setPIN(_ pin: String) -> Bool {
        var s = PinStore()
        guard (try? s.set(pin)) != nil else { return false }
        pinSet = true
        return true
    }

    private var correctPIN: String { (try? PinStore().current) ?? "" }

    // ════════════ カートへの追加（3経路共通・A-2）════════════

    /// QR読み取り・商品パネル・手動入力はすべてここを通す（追加経路によらず同一判定・A-1）
    func addRegistered(productId: String, qty: Int = 1) {
        guard let p = inventory.first(where: { $0.id == productId }) else {
            lastMessage = "存在しない商品IDです: \(productId)"
            return
        }
        let result = add(product: p, qty: qty, cart: &ctx.cart, inventory: inventory, types: types)
        switch result {
        case .applied(let m):                 // 追加は確認不要（A-3 の表）
            lastMessage = m
        case .needsConfirm(let d):            // 追加では発生しないが、網羅しておく
            pendingDelete = d
        case .rejected(let e):
            lastMessage = e
            return
        }
        advanceToScanningIfNeeded()
        onCartChanged()
    }

    /// 手動入力（全角補正 → ID解決・A-2）
    func enterID(_ raw: String) {
        guard let pid = IDNormalizer.resolveProductID(raw, types: types) else {
            lastMessage = "商品IDを認識できません: \(raw)"
            return
        }
        addRegistered(productId: pid)
    }

    /// QRスキャナーからの受け口（連続読み取りのクールダウンは ScannerView 側・A-2）
    func scanQR(_ payload: String) {
        let pid = IDNormalizer.fromQR(payload)
        guard inventory.contains(where: { $0.id == pid }) else {
            // 存在しないIDは補正して再試行（A-2 の補正は手動入力だけでなく全経路共通）
            enterID(pid)
            return
        }
        addRegistered(productId: pid)
    }

    /// 野良商品をカートに追加（A-1）。金額の確認表示は AdhocSheet が行う。ここでは最終確定のみ受ける。
    func addAdhoc(name: String, priceJpy: Int, priceSats: Int?, groupId: String?, qty: Int) {
        guard priceJpy >= 1 else {
            lastMessage = "円価格は1以上の整数で入力してください"
            return
        }
        // sats単価は未設定か1以上（0sats受け付け防止・登録商品と同じ検証・A-1）
        guard priceSats == nil || (priceSats ?? 0) >= 1 else {
            lastMessage = "sats単価は空欄か1以上で入力してください"
            return
        }
        let line = CartLine.adhoc(id: ids.nextAdhocID(),           // 追加した瞬間に採番（A-19-10）
                                  name: name.isEmpty ? "野良" : name,
                                  priceJpy: priceJpy, priceSats: priceSats,
                                  groupId: groupId, qty: max(1, qty))
        ctx.cart.append(line)
        advanceToScanningIfNeeded()
        onCartChanged()
    }

    private func advanceToScanningIfNeeded() {
        if ctx.state == .idle {
            apply(.allowed(.scanning), to: &ctx)     // 待機中 → スキャン中（A-4）
        }
    }

    private func onCartChanged() {
        // カートが空になったら待機中へ（A-4）
        if ctx.cart.isEmpty && ctx.state == .scanning {
            apply(.allowed(.idle), to: &ctx)
        }
        saveAll()
    }

    // ════════════ カートの編集（base/5）════════════

    func increase(at i: Int) {
        handle(increase(at: i, cart: &ctx.cart, inventory: inventory, types: types))
    }

    func decrease(at i: Int) {
        handle(decrease(at: i, cart: &ctx.cart, inventory: inventory, types: types))
    }

    func requestDelete(at i: Int) {
        handle(remove(at: i, cart: ctx.cart))
    }

    func confirmDelete(_ d: CartDelete) {
        lastMessage = performDelete(d, cart: &ctx.cart)
        onCartChanged()
    }

    private func handle(_ r: CartEdit) {
        switch r {
        case .applied(let m): lastMessage = m; onCartChanged()
        case .needsConfirm(let d): pendingDelete = d      // 確認ダイアログへ（C-6 #49/#50）
        case .rejected(let e): lastMessage = e
        }
    }

    var pendingDelete: CartDelete?

    // ════════════ 状態機械のイベント（base/6 §3）════════════

    /// UI は `move(_:in:)` の返り値に従うだけ。行き先を UI が決めない（A-4）。
    func send(_ e: SaleEvent) {
        let m = move(e, in: ctx)
        switch m {
        case .rejected(let why):
            lastMessage = why
        case .allowed:
            apply(m, to: &ctx); saveAll()
        case .needsConfirm(_, let next):
            pendingMove = m; pendingNext = next          // ダイアログ表示後に confirmPendingMove()
        case .needsPIN:
            pendingMove = m; pendingNext = m.nextState   // PIN入力ダイアログへ
        }
    }

    var pendingMove: Move?
    var pendingNext: SaleState?

    /// 確認ダイアログでOK（PINが要る場合は pinInput で照合済み）
    func confirmPendingMove(pinInput: String? = nil) {
        guard let m = pendingMove else { return }
        if case .needsPIN(let reason, _) = m {
            guard let pin = pinInput, pin == correctPIN else {
                lastMessage = "PINが違います（\(reason.title)）"
                return
            }
        }
        // 「済」ボタンの承認（C-6 #23・#78）。ここで請求sats額を確定し、そのまま販売確定まで行う
        if case .needsConfirm(let r, _) = m, r.title == tapDoneReason(in: ctx).title {
            pendingMove = nil; pendingNext = nil
            tapSatsDoneConfirmed()
            return
        }
        // sats待ちの「中断」＝キャンセル扱い。記録も破棄もせず、カートはそのまま（A-19-8）
        if case .needsConfirm(let r, _) = m, r.title == cancelReason(in: ctx).title {
            pendingMove = nil; pendingNext = nil
            lastMessage = r.message
            saveAll()
            return
        }
        // 会計中断の実処理（A-4、A-19-2）。sats未確認なら記録なし、sats確認済みならPIN必須で記録を残す
        if case .needsPIN(_, .suspended)? = m {
            let r = suspendSaleLogic(cart: ctx.cart, ids: &ids, correctPIN: correctPIN,
                                     pin: pinInput ?? "", sales: &sales, items: &items,
                                     chooseSats: ctx.method == .lightning || ctx.method == .mixed,
                                     confirmedAt: ctx.satsConfirmedAt, now: Date())
            switch r {
            case .success(let recorded, _):
                lastMessage = recorded == nil ? "中断しました（記録は残りません）" : "中断しました（sats確認済みの記録を残します）"
            case .failure(let e):
                lastMessage = e   // PIN違いでは中断しない（C-6 #67）
            }
            resetAfterSale(clearContext: true)
            return
        }
        apply(m, to: &ctx)
        pendingMove = nil; pendingNext = nil
        saveAll()   // apply は状態を移すだけ。記録・在庫は確定関数の担当（base/6 §6）
    }

    func cancelPendingMove() {
        pendingMove = nil; pendingNext = nil
    }

    // ════════════ 支払方法と確定 ════════════

    /// 現金入力中の確定（A-4①〜④）。受取額が請求額以上なら販売を確定する。
    func confirmCash(received: Int) {
        let m = move(.confirmCash(received), in: ctx)
        guard let next = m.nextState else { lastMessage = m.reason?.message ?? "できません"; return }
        apply(m, to: &ctx)
        // state == .done → commitSale（検証→採番→減算→ログ→記録。A-4 のトランザクション）
        let r = commitSale(cart: ctx.cart, inventory: &inventory, movements: &movements,
                           sales: &sales, items: &items, ids: &ids, types: types,
                           chooseSats: false, receivedJpy: received, confirmedAt: nil, now: Date())
        finalizeCommit(r)
        _ = next
    }

    /// sats待ちの「済」ボタン承認（確認ダイアログを経たあと・C-6 #23）。
    /// 現金分なし → 完了／現金分あり → 併用現金入力中（A-4、C-6 #24/#77）。
    func tapSatsDoneConfirmed() {
        let m = move(.tapDone, in: ctx)
        guard m.nextState != nil else { lastMessage = m.reason?.message ?? "できません"; return }
        markSatsConfirmed(&ctx, at: Date())              // 請求sats額をこのとき確定（C-6 #78）
        if m.nextState == .done {
            apply(m, to: &ctx)
            commitLightning()
        } else {
            apply(m, to: &ctx)                            // mixedCashInput
            saveAll()
        }
        pendingMove = nil
    }

    /// sats待ちのキャンセル＝方法選び直し（A-19-8。2段目を選ぶまでカートはそのまま）
    func changeMethod() {
        let m = move(.changeMethod, in: ctx)
        if let _ = m.nextState { apply(m, to: &ctx); saveAll() } else { lastMessage = m.reason?.message ?? "できません" }
    }

    /// 併用現金入力中の確定（現金分だけ受け取る・C-6 #77）
    func confirmMixedCash(received: Int) {
        let m = move(.confirmMixedCash(received), in: ctx)
        guard m.nextState != nil else { lastMessage = m.reason?.message ?? "できません"; return }
        apply(m, to: &ctx)
        commitLightning(receivedJpy: received)
    }

    /// lightning / mixed の販売確定（sats確認済み）
    private func commitLightning(receivedJpy: Int? = nil) {
        let r = commitSale(cart: ctx.cart, inventory: &inventory, movements: &movements,
                           sales: &sales, items: &items, ids: &ids, types: types,
                           chooseSats: true, receivedJpy: receivedJpy,
                           confirmedAt: ctx.satsConfirmedAt, now: Date())
        finalizeCommit(r)
    }

    private func finalizeCommit(_ r: CommitResult) {
        switch r {
        case .success(let sale, _, let memo):
            lastMessage = "販売完了 \(sale.id)（" + memo.joined(separator: " / ") + "）"
            resetAfterSale(clearContext: true)
        case .failure(let problems):
            // 在庫不足など：何も変わらない（A-4）。「会計中」のまま留まる（C-6 #14）
            lastMessage = problems.joined(separator: "\n")
            // done に進んでいた場合も、書き戻しが無いので中断扱いに戻す
            if ctx.state == .done { apply(.allowed(.cashInput), to: &ctx) }
            saveAll()
        }
    }

    /// 会計中断（A-4、A-19-2）。sats未確認なら記録なし、sats確認済みならPIN必須で記録を残す。
    func suspendSale(pinInput: String?) {
        let m = move(.suspend, in: ctx)
        guard m.nextState != nil else { lastMessage = m.reason?.message ?? "中断できません"; return }
        let r = suspendSaleLogic(cart: ctx.cart, ids: &ids, correctPIN: correctPIN,
                                 pin: pinInput ?? "", sales: &sales, items: &items,
                                 chooseSats: ctx.method == .lightning || ctx.method == .mixed,
                                 confirmedAt: ctx.satsConfirmedAt, now: Date())
        switch r {
        case .success(let recorded, _):
            lastMessage = recorded == nil ? "中断しました（記録は残りません）" : "中断しました（sats確認済みの記録を残します）"
            apply(m, to: &ctx)
            resetAfterSale(clearContext: true)
        case .failure(let e):
            lastMessage = e     // PIN違いでは中断しない（C-6 #67）
        }
    }

    /// 完了・中断のあと待機中へ戻す（A-4）。カートは破棄されている。
    func backToIdle() {
        let m = move(.backToIdle, in: ctx)
        if m.nextState != nil {
            apply(m, to: &ctx)
            resetAfterSale(clearContext: true)
        }
    }

    private func resetAfterSale(clearContext: Bool) {
        if clearContext {
            ctx = SaleContext()
            try? persistence.saleContextStore.clear()   // 完了後は会計状態を残さない（A-3）
        }
        saveAll()
    }

    // ════════════ 編集（A-1。待機中・PIN必須）═════════════

    var canEdit: Bool { ctx.state == .idle }

    func addGroup(groupId: String, label: String, pin: String) -> String {
        guard canEdit else { return "待機中のみ編集できます（A-1）" }
        let r = addGroupLogic(groupId: groupId, label: label, correctPIN: correctPIN, pin: pin, groups: &groups)
        finishEdit(r); return messageOf(r)
    }

    func renameGroup(groupId: String, label: String, pin: String) -> String {
        guard canEdit else { return "待機中のみ編集できます（A-1）" }
        let r = renameGroupLogic(groupId: groupId, label: label, correctPIN: correctPIN, pin: pin, groups: &groups)
        finishEdit(r); return messageOf(r)
    }

    func deleteGroup(groupId: String, pin: String) -> String {
        guard canEdit else { return "待機中のみ編集できます（A-1）" }
        let r = deleteGroupLogic(groupId: groupId, correctPIN: correctPIN, pin: pin,
                                 groups: &groups, types: types, items: items)
        finishEdit(r); return messageOf(r)
    }

    func addType(typeId: String, name: String, idPrefix: String, idDigits: Int,
                 stockMode: StockMode, labels: [String?], groupId: String?,
                 startNo: Int?, pin: String) -> String {
        guard canEdit else { return "待機中のみ編集できます（A-1）" }
        let r = addTypeLogic(typeId: typeId, name: name, idPrefix: idPrefix, idDigits: idDigits,
                             stockMode: stockMode, labels: labels, groupId: groupId, startNo: startNo,
                             correctPIN: correctPIN, pin: pin, types: &types, groups: groups)
        finishEdit(r); return messageOf(r)
    }

    func editType(typeId: String, name: String, labels: [String?], groupId: String?, pin: String) -> String {
        guard canEdit else { return "待機中のみ編集できます（A-1）" }
        let r = editTypeLogic(typeId: typeId, name: name, labels: labels, groupId: groupId,
                              correctPIN: correctPIN, pin: pin, types: &types, groups: groups, inventory: inventory)
        finishEdit(r); return messageOf(r)
    }

    func addProduct(_ input: NewProductInput, pin: String) -> String {
        guard canEdit else { return "待機中のみ編集できます（A-1）" }
        let r = addProductLogic(input, correctPIN: correctPIN, pin: pin,
                                inventory: &inventory, types: &types, movements: &movements,
                                ids: &ids, at: Date())
        switch r {
        case .success(let p):
            // 同梱画像の対応付け（A-1・P2対策）: バンドル or originals/ を商品IDで探し、
            // imageRef に実体パスを記録する。見つからなければ案内どおり原本配置＋再起動で解決される。
            let attached = persistence.attachMissingImages(to: &inventory)
            saveAll()
            if attached > 0 || inventory.first(where: { $0.id == p.id })?.imageRef != nil {
                return "追加: \(p.id)（同梱画像を自動対応付け・A-1）"
            }
            return "追加: \(p.id)（画像なし。原本をバンドル or originals/ に配置して再起動すると自動対応付け・A-1）"
        case .failure(let rs):
            return rs.joined(separator: "\n")
        }
    }

    func editProduct(productId: String, name: String, priceJpy: Int, priceSats: Int?,
                     attrs: [String?], isPublic: Bool, pin: String) -> String {
        guard canEdit else { return "会計中は価格を編集できません（A-1、C-6 #52）" }
        let r = editProductLogic(productId: productId, name: name, priceJpy: priceJpy, priceSats: priceSats,
                                 attrs: attrs, isPublic: isPublic,
                                 correctPIN: correctPIN, pin: pin, inventory: &inventory, types: types)
        finishEdit(r); return messageOf(r)
    }

    /// 公開状態のみ切替（属性ラベルを消さずに・PIN必須）。swipeActions から呼ぶ。
    func togglePublic(productId: String, pin: String) -> String {
        guard canEdit else { return "会計中は公開状態を編集できません（A-1、C-6 #52）" }
        guard pin == correctPIN else { return "PINが違います（商品編集はPIN必須・A-1）" }
        guard let i = inventory.firstIndex(where: { $0.id == productId }) else {
            return "商品が見つかりません: \(productId)"
        }
        inventory[i].isPublic.toggle()
        saveAll()
        return "\(productId) を\(!inventory[i].isPublic ? "非公開" : "公開")にしました"
    }

    func adjustStock(productId: String, newStock: Int, pin: String) -> String {
        let r = adjustStockLogic(productId: productId, newStock: newStock, reason: "棚卸し",
                                 correctPIN: correctPIN, pin: pin,
                                 inventory: &inventory, movements: &movements, ids: &ids,
                                 types: types, at: Date())
        switch r {
        case .success(let m): saveAll(); return m
        case .failure(let e): return e
        }
    }

    private func finishEdit(_ r: EditResult) {
        if case .success = r { saveAll() }
    }

    private func messageOf(_ r: EditResult) -> String {
        switch r {
        case .success(let m): return m
        case .failure(let e): return e
        }
    }

    // ════════════ CSV 取り込み（A-1。グループ→種類→商品の順）═════════════

    struct ImportOutcome {
        var issues: [ValidationIssue] = []
        var summary: String = ""
        var ok: Bool { issues.isEmpty }
    }

    /// 3枚のCSVテキストを受け取り、検証 → 問題があれば0件 → 適用する。
    func importCSV(groupText: String?, typeText: String?, productText: String?,
                   overwriteStock: Bool, pin: String) -> ImportOutcome {
        guard canEdit else {
            var o = ImportOutcome(); o.issues = [ValidationIssue(row: 0, column: "-", reason: "待機中のみ取り込めます（A-1）")]
            return o
        }
        guard pin == correctPIN else {
            var o = ImportOutcome(); o.issues = [ValidationIssue(row: 0, column: "PIN", reason: "PINが違います")]
            return o
        }
        var outcome = ImportOutcome()
        var gParsed: [ProductGroup] = []
        var tParsed: [ParsedType] = []
        var pParsed: [Product] = []

        if let text = groupText, let table = CSVParser.table(from: text) {
            let r = parseGroupCSV(table)
            outcome.issues += r.issues; gParsed = r.groups
        }
        if outcome.ok, let text = typeText, let table = CSVParser.table(from: text) {
            let mergedGroups = applyingPreviewGroups(gParsed)
            let r = parseTypeCSV(table, groups: mergedGroups, existing: types,
                                 inventory: inventory, items: items)
            outcome.issues += r.issues; tParsed = r.types
        }
        if outcome.ok, let text = productText, let table = CSVParser.table(from: text) {
            let previewTypes = applyingPreviewTypes(tParsed)
            let r = parseProductCSV(table, types: previewTypes, inventory: inventory)
            outcome.issues += r.issues; pParsed = r.products
        }
        guard outcome.ok else { return outcome }   // 1行でもエラーなら全体を取り込まない（A-1）

        applyGroups(gParsed, groups: &groups)
        applyTypes(tParsed, types: &types, inventory: inventory)
        applyProductMaster(pParsed, inventory: &inventory, movements: &movements,
                           ids: &ids, types: &types, overwriteStock: overwriteStock, at: Date())
        // 取り込みで imageRef が nil になった商品も、同梱画像を商品IDで自動対応付け（A-1・P2対策）
        persistence.attachMissingImages(to: &inventory)
        outcome.summary = "グループ \(gParsed.count) / 種類 \(tParsed.count) / 商品 \(pParsed.count) を取り込み"
        saveAll()
        return outcome
    }

    private func applyingPreviewGroups(_ parsed: [ProductGroup]) -> [ProductGroup] {
        var g = groups
        applyGroups(parsed, groups: &g)
        return g
    }

    private func applyingPreviewTypes(_ parsed: [ParsedType]) -> [ProductType] {
        var t = types
        applyTypes(parsed, types: &t, inventory: inventory)
        return t
    }

    // ════════════ 販売取消・返金フラグ（A-9。履歴から・PIN必須）═════════════

    func voidSale(saleId: String, pin: String) -> String {
        let r = voidSaleLogic(saleId: saleId, correctPIN: correctPIN, pin: pin,
                              sales: &sales, items: items, inventory: &inventory,
                              movements: &movements, ids: &ids, types: types, at: Date())
        switch r {
        case .success(let memo): saveAll(); return "取消: " + memo.joined(separator: " / ")
        case .failure(let e): return e
        }
    }

    func setRefundedFlag(saleId: String, value: Bool, pin: String) -> String {
        let r = setRefundedLogic(saleId: saleId, value: value, correctPIN: correctPIN, pin: pin, sales: &sales)
        if case .success = r { saveAll() }
        return messageOf(r)
    }

    // ════════════ 集計（A-8）═════════════

    func dailySummary(day: Date) -> Summary {
        summarize(salesOn(day, in: sales), items: items)
    }

    func periodSummary(from: Date?, to: Date?) -> PeriodSummary {
        summarizeRange(sales, items: items, from: from, to: to)
    }

    func settlementCSV(from: Date?, to: Date?, pin: String) -> String {
        guard pin == correctPIN else { return "PINが違います（精算CSVはPIN必須・A-8）" }
        let period = periodSummary(from: from, to: to)
        let ps = period.startDay ?? "-"
        let pe = period.endDay ?? "-"
        switch settlementRows(period, groups: groups, periodStart: ps, periodEnd: pe,
                              correctPIN: correctPIN, pin: pin) {
        case .failure(let e): return e
        case .success(let rows): return settlementCSVLogic(rows)
        }
    }

    func cashReconciliation(day: Date, float: Int, actual: Int) -> CashReconciliation {
        reconcileCash(day: day, float: float, actual: actual, sales: sales, items: items)
    }

    // ════════════ B への送信（A-14）═════════════

    func makeSnapshotNow() -> Snapshot {
        makeSnapshot(types: types, inventory: inventory, now: Date())
    }

    var missingImageIDs: [String] {
        inventory.filter { $0.imageRef == nil }.map { $0.id }
    }

    func sendSnapshot() async -> String {
        let snap = makeSnapshotNow()
        do {
            try await kv.put(snapshot: snap)
            let e = recordSync(&syncLog, ids: &ids, snapshot: snap, error: nil, at: Date())
            saveAll()
            return e.detail
        } catch {
            let e = recordSync(&syncLog, ids: &ids, snapshot: snap,
                               error: error.localizedDescription, at: Date())
            saveAll()   // 失敗しても会計・在庫には影響させない（C-6 #72）
            return "送信失敗: \(e.detail)"
        }
    }

    // ════════════ エクスポート（A-8、N-4）═════════════

    func exportFile(kind: ExportKind) -> URL? {
        try? persistence.exportedURL(suggestedName: kind.fileName, contents: kind.text(store: self))
    }

    enum ExportKind: String, CaseIterable, Identifiable {
        case groups, types, products, priceList, stockList, sales, saleItems, movements, settlement, satsRecon, snapshotJSON
        var id: String { rawValue }

        var fileName: String {
            let d = DayKey.string(from: Date())
            switch self {
            case .groups: return "groups_\(d).csv"
            case .types: return "types_\(d).csv"
            case .products: return "product_master_\(d).csv"
            case .priceList: return "price_list_\(d).csv"
            case .stockList: return "stock_list_\(d).csv"
            case .sales: return "sales_\(d).csv"
            case .saleItems: return "sale_items_\(d).csv"
            case .movements: return "stock_movements_\(d).csv"
            case .settlement: return "settlement_\(d).csv"
            case .satsRecon: return "sats_reconciliation_\(d).csv"
            case .snapshotJSON: return "snapshot_\(d).json"
            }
        }

        func text(store: FremaRegiStore) -> String {
            switch self {
            case .groups: return CSVExport.groups(store.groups)
            case .types: return CSVExport.types(store.types)
            case .products: return CSVExport.products(store.inventory)
            case .priceList: return CSVExport.priceList(store.inventory)
            case .stockList: return CSVExport.stockList(store.inventory, types: store.types)
            case .sales: return CSVExport.sales(store.sales)
            case .saleItems: return CSVExport.saleItems(store.items)
            case .movements: return CSVExport.movements(store.movements)
            case .settlement: return store.settlementCSV(from: nil, to: nil, pin: (try? PinStore().current) ?? "")
            case .satsRecon: return CSVExport.satsReconciliationCSV(store.sales)
            case .snapshotJSON:
                let enc = jsonEncoder
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                return String(data: (try? enc.encode(store.makeSnapshotNow())) ?? Data(), encoding: .utf8) ?? "{}"
            }
        }
    }

    /// 在庫の自己点検（A-19-1）: products.stock と stock_movements の合計が一致するか
    func stockSelfCheck() -> [(String, Int, Int, Bool)] {
        inventory.map { p in
            let stock = p.stock ?? 0
            let logged = movements.filter { $0.productId == p.id }.reduce(0) { $0 + $1.delta }
            return (p.id, stock, logged, stock == logged)
        }
    }
}

// ════════════════════════════════════════════════════════════
// 標準ロジックの同名関数とのラッパー（SwiftUI の View メソッド名と衝突するため
// store 側のメソッドは xxxLogic を呼ぶ薄い皮にする）
// ════════════════════════════════════════════════════════════

private func addGroupLogic(groupId: String, label: String, correctPIN: String, pin: String,
                           groups: inout [ProductGroup]) -> EditResult {
    addGroup(groupId: groupId, label: label, correctPIN: correctPIN, pin: pin, groups: &groups)
}
private func renameGroupLogic(groupId: String, label: String, correctPIN: String, pin: String,
                              groups: inout [ProductGroup]) -> EditResult {
    renameGroup(groupId: groupId, label: label, correctPIN: correctPIN, pin: pin, groups: &groups)
}
private func deleteGroupLogic(groupId: String, correctPIN: String, pin: String,
                              groups: inout [ProductGroup], types: [ProductType],
                              items: [SaleItem]) -> EditResult {
    deleteGroup(groupId: groupId, correctPIN: correctPIN, pin: pin, groups: &groups, types: types, items: items)
}
private func addTypeLogic(typeId: String, name: String, idPrefix: String, idDigits: Int,
                          stockMode: StockMode, labels: [String?], groupId: String?,
                          startNo: Int?, correctPIN: String, pin: String,
                          types: inout [ProductType], groups: [ProductGroup]) -> EditResult {
    addType(typeId: typeId, name: name, idPrefix: idPrefix, idDigits: idDigits,
            stockMode: stockMode, labels: labels, groupId: groupId, startNo: startNo,
            correctPIN: correctPIN, pin: pin, types: &types, groups: groups)
}
private func editTypeLogic(typeId: String, name: String, labels: [String?], groupId: String?,
                           correctPIN: String, pin: String, types: inout [ProductType],
                           groups: [ProductGroup], inventory: [Product]) -> EditResult {
    editType(typeId: typeId, name: name, labels: labels, groupId: groupId,
             correctPIN: correctPIN, pin: pin, types: &types, groups: groups, inventory: inventory)
}
private func addProductLogic(_ input: NewProductInput, correctPIN: String, pin: String,
                             inventory: inout [Product], types: inout [ProductType],
                             movements: inout [StockMovement], ids: inout IdSequencer,
                             at: Date) -> AddProductResult {
    addProduct(input, correctPIN: correctPIN, pin: pin, inventory: &inventory, types: &types,
               movements: &movements, ids: &ids, at: at)
}
private func editProductLogic(productId: String, name: String, priceJpy: Int, priceSats: Int?,
                              attrs: [String?], isPublic: Bool, correctPIN: String, pin: String,
                              inventory: inout [Product], types: [ProductType]) -> EditResult {
    editProduct(productId: productId, name: name, priceJpy: priceJpy, priceSats: priceSats,
                attrs: attrs, isPublic: isPublic, correctPIN: correctPIN, pin: pin,
                inventory: &inventory, types: types)
}
private func adjustStockLogic(productId: String, newStock: Int, reason: String,
                              correctPIN: String, pin: String, inventory: inout [Product],
                              movements: inout [StockMovement], ids: inout IdSequencer,
                              types: [ProductType], at: Date) -> AdjustResult {
    adjustStock(productId: productId, newStock: newStock, reason: reason,
                correctPIN: correctPIN, pin: pin, inventory: &inventory,
                movements: &movements, ids: &ids, types: types, at: at)
}
private func suspendSaleLogic(cart: [CartLine], ids: inout IdSequencer, correctPIN: String, pin: String,
                              sales: inout [Sale], items: inout [SaleItem], chooseSats: Bool,
                              confirmedAt: Date?, now: Date) -> SuspendResult {
    suspendSale(cart: cart, ids: &ids, correctPIN: correctPIN, pin: pin, sales: &sales, items: &items,
                chooseSats: chooseSats, confirmedAt: confirmedAt, now: now)
}
private func voidSaleLogic(saleId: String, correctPIN: String, pin: String, sales: inout [Sale],
                           items: [SaleItem], inventory: inout [Product],
                           movements: inout [StockMovement], ids: inout IdSequencer,
                           types: [ProductType], at: Date) -> VoidResult {
    voidSale(saleId: saleId, correctPIN: correctPIN, pin: pin, sales: &sales, items: items,
             inventory: &inventory, movements: &movements, ids: &ids, types: types, at: at)
}
private func setRefundedLogic(saleId: String, value: Bool, correctPIN: String, pin: String,
                              sales: inout [Sale]) -> EditResult {
    setRefunded(saleId: saleId, value: value, correctPIN: correctPIN, pin: pin, sales: &sales)
}
private func settlementCSVLogic(_ rows: [SettlementRow]) -> String {
    settlementCSV(rows)
}
#endif
