import Foundation

// @section: totals
/// 合計の表示2行（A-3）
func totalLines(_ cart: [CartLine]) -> (satsLine: String, cashLine: String) {
    let t = cart.totals()
    let hasSats = cart.contains { $0.unitPriceSats != nil }

    let satsLine: String
    if !hasSats {
        satsLine = "sats払い　選択不可（sats単価のある商品がありません）"
    } else if t.cashForSats == 0 {
        satsLine = "sats払い　\(t.sats)sats"
    } else {
        satsLine = "sats払い　\(t.sats)sats ＋ \(t.cashForSats)円"
    }
    return (satsLine, "現金　　　\(t.cash)円")
}


// @section: helpers
/// 検証で見つかった問題1件（項目名と理由）
struct FieldIssue: Equatable {
    let column: String
    let reason: String
}

enum EditResult {
    case success(String)
    case failure(String)
}

/// 半角数字のみ（空・符号・全角は不可）。CSV の数値規則（A-1）
func isAsciiDigits(_ s: String) -> Bool {
    !s.isEmpty && s.allSatisfy { $0 >= "0" && $0 <= "9" }
}

func parseInt(_ s: String) -> Int? {
    isAsciiDigits(s) ? Int(s) : nil
}

/// 半角英数字とアンダースコア（group_id・type_id）
func isIdToken(_ s: String) -> Bool {
    !s.isEmpty && s.allSatisfy { c in
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "_"
    }
}

/// 半角英大文字・数字。ハイフンを含まない（id_prefix）
func isPrefixToken(_ s: String) -> Bool {
    !s.isEmpty && s.allSatisfy { c in (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") }
}

func typeLabels(_ t: ProductType) -> [String?] {
    [t.attrLabel1, t.attrLabel2, t.attrLabel3]
}

/// 商品IDから番号を取り出す。形式（接頭辞・桁数・半角数字）が種類と一致しなければ nil（A-1）
func productNumber(of productId: String, in type: ProductType) -> Int? {
    let head = type.idPrefix + "-"
    guard productId.hasPrefix(head) else { return nil }
    let rest = String(productId.dropFirst(head.count))
    guard rest.count == type.idDigits, isAsciiDigits(rest) else { return nil }
    return Int(rest)
}

/// その種類の現存商品の最大番号（なければ 0）
func maxProductNumber(of type: ProductType, in inventory: [Product]) -> Int {
    inventory.filter { $0.typeId == type.typeId }
        .compactMap { productNumber(of: $0.id, in: type) }
        .max() ?? 0
}



// @section: method
/// 会計の受取方法を決める（A-13 の method）
///
/// - Note: sats払いの前提は「sats単価のある行が1行以上」（A-4）。
///   前提を満たさない `chooseSats` は `cash` に落とす。
///   **`total_sats` が 0 の `lightning` / `mixed` を作らない**（A-19-9 #10）。
func resolveMethod(chooseSats: Bool, cart: [CartLine]) -> PaymentMethod {
    guard chooseSats, cart.canPayBySats() else { return .cash }
    return cart.totals().cashForSats == 0 ? .lightning : .mixed
}

/// この行の受取方法（A-13 の paid_in）
func paidIn(of line: CartLine, method: PaymentMethod) -> PaidIn {
    if method == .cash { return .jpy }
    return line.unitPriceSats != nil ? .sats : .jpy
}

/// 販売記録（sales 1行 + sale_items）を作る。
/// - Note: 販売ID・明細IDは `IdSequencer` が採番する（A-19-4）。完了時以外から呼ばないこと。
/// - Note: `group_id` は**カート行が持つ値**を写す（登録商品は種類の複写、野良は入力値。A-13）。
func buildSale(cart: [CartLine],
               ids: inout IdSequencer,
               chooseSats: Bool,
               receivedJpy: Int?,     // 現金を受け取ったときだけ
               confirmedAt: Date?,    // sats確認済みなら
               now: Date) -> (sale: Sale, items: [SaleItem]) {

    let saleId = ids.nextSaleID(at: now)          // ← 採番は完了時（A-19-4）
    let method = resolveMethod(chooseSats: chooseSats, cart: cart)
    let t = cart.totals()

    var sale = Sale(id: saleId, status: .completed, method: method,
                    totalJpy: nil, totalSats: nil,
                    receivedJpy: nil, changeJpy: nil,
                    confirmedAt: nil, refunded: false, completedAt: now)

    var items: [SaleItem] = []
    for (n, line) in cart.enumerated() {
        items.append(SaleItem(
            id: ids.itemID(saleId: saleId, n: n + 1),   // S-YYYYMMDD-NNN-01
            saleId: saleId,
            itemType: line.itemType,
            typeId: line.typeId,
            groupId: line.groupId,                       // ← A-13：販売時点のグループID
            productId: line.isAdhoc ? nil : line.id,
            qty: line.qty,
            unitPriceJpy: line.unitPriceJpy,
            unitPriceSats: line.unitPriceSats,
            paidIn: paidIn(of: line, method: method),
            nameSnapshot: line.name))
    }

    switch method {
    case .cash:      sale.totalJpy = t.cash
    case .lightning: sale.totalSats = t.sats; sale.confirmedAt = confirmedAt
    case .mixed:     sale.totalSats = t.sats; sale.totalJpy = t.cashForSats
                     sale.confirmedAt = confirmedAt
    }

    if method == .cash || method == .mixed {
        sale.receivedJpy = receivedJpy
        if let r = receivedJpy, let req = sale.totalJpy { sale.changeJpy = r - req }
    }
    return (sale, items)
}



// @section: stock
/// 在庫減算の対象。在庫表の位置と、減算前の現在庫を持つ。
struct StockTarget {
    let index: Int        // 在庫表（products）の位置
    let productId: String
    let line: CartLine
    let current: Int      // ★ 減算前の現在庫
}

/// 減算の対象を、在庫表の位置と現在値つきで取り出す。
/// **対象かどうかは、ここで1か所だけ決める**（検証と減算で二重に書かない）。
func stockTargets(_ cart: [CartLine],
                  in inventory: [Product],
                  types: [ProductType]) -> [StockTarget] {
    var targets: [StockTarget] = []
    for line in cart {
        guard !line.isAdhoc,                                     // ① 野良は対象外（A-1）
              let i = inventory.firstIndex(where: { $0.id == line.id }),  // ② 在庫表に居る
              inventory[i].managesStock(in: types),              // ③ 在庫管理あり（A-7）
              let current = inventory[i].stock                   // ④ 現在値を取り出す
        else { continue }
        targets.append(StockTarget(index: i, productId: line.id, line: line, current: current))
    }
    return targets
}

/// CSV 取り込みで**新規商品**を登録し、初期在庫を `initial` で記録する（A-1、A-19-1）。
/// - 既存の商品IDは触らない（A-1「既存の商品ID：在庫は変更しない」）
/// - **在庫管理なし型は記録しない**（A-1）。**在庫 0 も記録しない**（A-1、A-7）
/// - 追加した商品の番号に合わせて、種類の `nextNo` を `max(現在値, 番号+1)` に更新する（A-1）
/// - これを呼ばないと `products.stock` とログの合計が合わなくなります（不変条件 I9）
func registerInitialStock(_ newProducts: [Product],
                          inventory: inout [Product],
                          movements: inout [StockMovement],
                          ids: inout IdSequencer,
                          types: inout [ProductType],
                          at: Date) {
    for p in newProducts {
        guard !inventory.contains(where: { $0.id == p.id }) else { continue }
        inventory.append(p)
        if let ti = types.firstIndex(where: { $0.typeId == p.typeId }),
           let n = productNumber(of: p.id, in: types[ti]) {
            types[ti].nextNo = max(types[ti].nextNo, n + 1)     // 高水位。減らさない
            types[ti].updatedAt = at
        }
        guard p.managesStock(in: types), let stock = p.stock, stock > 0 else { continue }
        movements.append(StockMovement(
            id: ids.nextMovementID(), productId: p.id,
            delta: stock, reason: .initial, saleId: nil, at: at))
    }
}

/// 在庫不足の理由を**全件**返す。**在庫は触らない**。問題なければ空配列。
func checkStock(_ cart: [CartLine], inventory: [Product], types: [ProductType]) -> [String] {
    var problems: [String] = []
    for t in stockTargets(cart, in: inventory, types: types) where t.line.qty > t.current {
        problems.append("在庫不足: \(t.line.name)（在庫 \(t.current)、必要 \(t.line.qty)）")
    }
    return problems
}

enum CompleteResult {
    case success(lines: [String])   // 成功（在庫がどう変わったか）
    case failure([String])          // 失敗（理由の全件）
}

/// 会計を完了する。**検証 → 在庫減算 → 在庫変動ログ**を1つのまとまりで行う。
/// - Note: 検証で1件でも不足なら、**何も変えずに** `.failure`（A-4 のトランザクション）
/// - Note: 在庫は `products.stock` を直接更新する（正・A-19-1）。同じ差分をログにも残す。
func completeSale(saleId: String,
                  cart: [CartLine],
                  inventory: inout [Product],
                  movements: inout [StockMovement],
                  ids: inout IdSequencer,
                  types: [ProductType],
                  at: Date) -> CompleteResult {

    let problems = checkStock(cart, inventory: inventory, types: types)
    if !problems.isEmpty { return .failure(problems) }     // ← 1行も書き換える前

    var memo: [String] = []
    for t in stockTargets(cart, in: inventory, types: types) {
        let after = t.current - t.line.qty
        inventory[t.index].stock = after                                  // 在庫減算
        memo.append("\(t.line.name): 在庫 \(t.current) → \(after)")
        movements.append(StockMovement(                                    // 在庫変動ログ
            id: ids.nextMovementID(), productId: t.productId,
            delta: -t.line.qty, reason: .sale, saleId: saleId, at: at))
    }
    return .success(lines: memo)
}



// @section: commit
enum CommitResult {
    case success(sale: Sale, items: [SaleItem], stockMemo: [String])
    case failure([String])
}

func commitSale(cart: [CartLine],
                inventory: inout [Product],
                movements: inout [StockMovement],
                sales: inout [Sale],
                items: inout [SaleItem],
                ids: inout IdSequencer,
                types: [ProductType],
                chooseSats: Bool,
                receivedJpy: Int?,
                confirmedAt: Date?,
                now: Date) -> CommitResult {

    // ① 在庫検証。1件でも失敗したら、以降の手順を全部飛ばす
    let problems = checkStock(cart, inventory: inventory, types: types)
    guard problems.isEmpty else { return .failure(problems) }

    // ② 販売記録。**検証が通ってから採番する**（失敗した会計で番号を消費しない・A-19-4）
    let built = buildSale(cart: cart, ids: &ids, chooseSats: chooseSats,
                          receivedJpy: receivedJpy, confirmedAt: confirmedAt, now: now)

    // ③ 在庫減算 ＋ ④ 在庫変動ログ
    switch completeSale(saleId: built.sale.id, cart: cart, inventory: &inventory,
                        movements: &movements, ids: &ids, types: types, at: now) {
    case .failure(let rs):
        return .failure(rs)      // 検証済みなのでここには来ない。ただし「失敗時は何も保存しない」を守る
    case .success(let memo):
        sales.append(built.sale)
        items.append(contentsOf: built.items)
        return .success(sale: built.sale, items: built.items, stockMemo: memo)
    }
}



// @section: suspend
enum SuspendResult {
    case success(recorded: Sale?, items: [SaleItem])   // sats確認済みなら記録あり
    case failure(String)
}

/// 会計を中断する（A-4）。
/// - sats未確認（`confirmedAt == nil`）: 確認ダイアログだけ。**記録も在庫変動も作らない**（A-19-2）
/// - sats確認済み: **PIN必須**。`status = voided`（`completed_at` は空）の記録だけ残す（A-19-2）
/// - **在庫は両方とも触らない**（減算前なので、戻しもしない・A-19-3）
func suspendSale(cart: [CartLine],
                 ids: inout IdSequencer,
                 correctPIN: String, pin: String,
                 sales: inout [Sale],
                 items: inout [SaleItem],
                 chooseSats: Bool,
                 confirmedAt: Date?,
                 now: Date) -> SuspendResult {

    guard confirmedAt != nil else {
        // sats未確認：確認ダイアログを通っただけ。何も記録しない
        return .success(recorded: nil, items: [])
    }

    guard pin == correctPIN else { return .failure("PINが違います") }

    // sats確認済み：記録を残す。ただし「完了していない」ので completedAt は nil のまま
    let built = buildSale(cart: cart, ids: &ids, chooseSats: chooseSats,
                          receivedJpy: nil, confirmedAt: confirmedAt, now: now)
    var suspended = built.sale
    suspended.status = .voided        // voided だが…
    suspended.completedAt = nil       // ★ …completedAt は nil。**これがないと販売取消と区別できない**（A-19-3）
    sales.append(suspended)
    items.append(contentsOf: built.items)
    return .success(recorded: suspended, items: built.items)
}



// @section: void
enum VoidResult {
    case success([String])
    case failure(String)
}

/// 完了した販売を取り消す（A-9）。
/// - **在庫を戻すのは `completedAt` がある `voided` だけ**（A-19-3）。
///   sats確認済みで中断した会計は `completedAt` が nil なので、ここでは弾かれる。
/// - 在庫管理ありの種類の登録商品だけ戻す。管理なし型・野良は戻さない（A-9）。
func voidSale(saleId: String,
              correctPIN: String, pin: String,
              sales: inout [Sale],
              items: [SaleItem],
              inventory: inout [Product],
              movements: inout [StockMovement],
              ids: inout IdSequencer,
              types: [ProductType],
              at: Date) -> VoidResult {

    guard pin == correctPIN else { return .failure("PINが違います") }
    guard let si = sales.firstIndex(where: { $0.id == saleId }) else {
        return .failure("会計が見つかりません: \(saleId)")
    }
    guard sales[si].status == .completed else {
        return .failure("この会計は販売取消できません（完了していない／すでに取消済み）")
    }
    // 上の guard を通れば completedAt は必ずあるが、A-19-3 の判定基準をコードにも書く
    guard sales[si].completedAt != nil else {
        return .failure("この会計は販売取消できません（sats確認済みで中断した会計）")
    }

    var memo: [String] = []
    for item in items where item.saleId == saleId {
        guard item.itemType == .registered,
              let productId = item.productId,
              let pi = inventory.firstIndex(where: { $0.id == productId }),
              inventory[pi].managesStock(in: types),
              let current = inventory[pi].stock else { continue }

        let restored = current + item.qty
        inventory[pi].stock = restored
        memo.append("\(item.nameSnapshot): 在庫 \(current) → \(restored)")
        movements.append(StockMovement(
            id: ids.nextMovementID(), productId: productId,
            delta: item.qty, reason: .void, saleId: saleId, at: at))
    }
    sales[si].status = .voided
    return .success(memo)
}



// @section: adjust
enum AdjustResult {
    case success(String)
    case failure(String)
}

/// 現在庫を newStock で上書きし、差分を `adjust` として記録する（A-7）。
/// 「上書き」は products.stock を直接書くこと。ログからは計算しない（A-19-1）。
/// - Note: `reason`（理由）は呼び出し側の表示用。A-13 の `stock_movements` に保存先の列がないため、保存しない。
func adjustStock(productId: String, newStock: Int, reason: String,
                 correctPIN: String, pin: String,
                 inventory: inout [Product],
                 movements: inout [StockMovement],
                 ids: inout IdSequencer,
                 types: [ProductType],
                 at: Date) -> AdjustResult {

    guard pin == correctPIN else { return .failure("PINが違います") }
    guard let i = inventory.firstIndex(where: { $0.id == productId }) else {
        return .failure("商品が見つかりません: \(productId)")
    }
    let mode = inventory[i].stockMode(in: types)
    guard mode != .none else { return .failure("在庫管理なし型は調整できません") }
    guard newStock >= 0 else { return .failure("在庫は0以上で入力してください") }
    if mode == .unique && newStock > 1 { return .failure("一点物型の在庫は0か1です") }
    guard let current = inventory[i].stock else { return .failure("現在庫が読めません") }

    let diff = newStock - current
    inventory[i].stock = newStock
    guard diff != 0 else { return .success("変化なし") }

    movements.append(StockMovement(
        id: ids.nextMovementID(), productId: productId,
        delta: diff, reason: .adjust, saleId: nil, at: at))
    return .success("\(inventory[i].name): 在庫 \(current) → \(newStock)（差分 \(diff)）")
}



// @section: edit
// ── 共有する検証（編集画面と CSV で同一） ──

func validateGroupFields(groupId: String, label: String) -> [FieldIssue] {
    var r: [FieldIssue] = []
    if !isIdToken(groupId) {
        r.append(FieldIssue(column: "group_id", reason: "半角英数字とアンダースコアのみ。空は不可"))
    }
    if label.isEmpty { r.append(FieldIssue(column: "label", reason: "空は不可")) }
    return r
}

func validateTypeFields(typeId: String, name: String, idPrefix: String,
                        idDigits: Int, labels: [String?]) -> [FieldIssue] {
    var r: [FieldIssue] = []
    if !isIdToken(typeId) {
        r.append(FieldIssue(column: "type_id", reason: "半角英数字とアンダースコアのみ。空は不可"))
    }
    if name.isEmpty { r.append(FieldIssue(column: "name", reason: "空は不可")) }
    if !isPrefixToken(idPrefix) {
        r.append(FieldIssue(column: "id_prefix", reason: "半角英大文字・数字のみ。ハイフン・空は不可"))
    }
    if idDigits < 1 { r.append(FieldIssue(column: "id_digits", reason: "1以上の整数")) }
    for i in 1..<3 where labels[i] != nil && labels[i - 1] == nil {
        r.append(FieldIssue(column: "attr_label_\(i + 1)", reason: "属性ラベルは左から詰める"))
    }
    return r
}

func validateProductFields(name: String, priceJpy: Int, priceSats: Int?,
                           mode: StockMode, stock: Int?,
                           attrs: [String?], labels: [String?]) -> [FieldIssue] {
    var r: [FieldIssue] = []
    if name.isEmpty { r.append(FieldIssue(column: "name", reason: "空は不可")) }
    if priceJpy < 1 { r.append(FieldIssue(column: "price_jpy", reason: "1以上の整数")) }
    if let s = priceSats, s < 1 {
        r.append(FieldIssue(column: "price_sats", reason: "空、または1以上の整数"))
    }
    switch mode {
    case .counted:
        if stock == nil || stock! < 0 { r.append(FieldIssue(column: "stock", reason: "0以上の整数（数量管理型）")) }
    case .unique:
        if stock != 0 && stock != 1 { r.append(FieldIssue(column: "stock", reason: "0か1（一点物型）")) }
    case .none:
        if stock != nil { r.append(FieldIssue(column: "stock", reason: "在庫管理なし型は空")) }
    }
    for i in 0..<3 where attrs[i] != nil && labels[i] == nil {
        r.append(FieldIssue(column: "attr_\(i + 1)", reason: "対応する属性ラベルがない"))
    }
    return r
}

// ── グループ ──

func addGroup(groupId: String, label: String,
              correctPIN: String, pin: String,
              groups: inout [ProductGroup]) -> EditResult {
    guard pin == correctPIN else { return .failure("PINが違います") }
    let issues = validateGroupFields(groupId: groupId, label: label)
    guard issues.isEmpty else {
        return .failure(issues.map { "\($0.column): \($0.reason)" }.joined(separator: " / "))
    }
    guard !groups.contains(where: { $0.groupId == groupId }) else {
        return .failure("group_id: すでに存在します")
    }
    groups.append(ProductGroup(groupId: groupId, label: label))
    return .success("グループを追加: \(groupId)")
}

/// ラベルだけ変更できる。`groupId` は不変（A-1）。過去の集計にも変更後のラベルが出る（A-1）
func renameGroup(groupId: String, label: String,
                 correctPIN: String, pin: String,
                 groups: inout [ProductGroup]) -> EditResult {
    guard pin == correctPIN else { return .failure("PINが違います") }
    guard !label.isEmpty else { return .failure("label: 空は不可") }
    guard let i = groups.firstIndex(where: { $0.groupId == groupId }) else {
        return .failure("グループが見つかりません: \(groupId)")
    }
    groups[i].label = label
    return .success("ラベルを変更: \(groupId)")
}

/// 種類または販売明細から参照されていれば削除不可（A-1）
func canDeleteGroup(_ groupId: String, types: [ProductType], items: [SaleItem]) -> Bool {
    !types.contains { $0.groupId == groupId } && !items.contains { $0.groupId == groupId }
}

func deleteGroup(groupId: String,
                 correctPIN: String, pin: String,
                 groups: inout [ProductGroup],
                 types: [ProductType], items: [SaleItem]) -> EditResult {
    guard pin == correctPIN else { return .failure("PINが違います") }
    guard let i = groups.firstIndex(where: { $0.groupId == groupId }) else {
        return .failure("グループが見つかりません: \(groupId)")
    }
    guard canDeleteGroup(groupId, types: types, items: items) else {
        return .failure("種類または販売明細から参照されているため削除できません")
    }
    groups.remove(at: i)
    return .success("グループを削除: \(groupId)")
}

// ── 種類 ──

/// 種類の追加（A-1）。`startNo` は開始番号（nil なら 1）
func addType(typeId: String, name: String, idPrefix: String, idDigits: Int,
             stockMode: StockMode, labels: [String?], groupId: String?, startNo: Int?,
             correctPIN: String, pin: String,
             types: inout [ProductType], groups: [ProductGroup]) -> EditResult {
    guard pin == correctPIN else { return .failure("PINが違います") }
    var issues = validateTypeFields(typeId: typeId, name: name, idPrefix: idPrefix,
                                    idDigits: idDigits, labels: labels)
    if types.contains(where: { $0.typeId == typeId }) {
        issues.append(FieldIssue(column: "type_id", reason: "すでに存在します"))
    }
    if types.contains(where: { $0.idPrefix == idPrefix }) {
        issues.append(FieldIssue(column: "id_prefix", reason: "他の種類と重複"))
    }
    if let g = groupId, !groups.contains(where: { $0.groupId == g }) {
        issues.append(FieldIssue(column: "group_id", reason: "グループに存在しません"))
    }
    if let n = startNo, n < 1 { issues.append(FieldIssue(column: "next_no", reason: "1以上の整数")) }
    guard issues.isEmpty else {
        return .failure(issues.map { "\($0.column): \($0.reason)" }.joined(separator: " / "))
    }
    types.append(ProductType(typeId: typeId, name: name, idPrefix: idPrefix, idDigits: idDigits,
                             stockMode: stockMode,
                             attrLabel1: labels[0], attrLabel2: labels[1], attrLabel3: labels[2],
                             groupId: groupId, nextNo: startNo ?? 1, updatedAt: nil))
    return .success("種類を追加: \(typeId)")
}

/// 種類の編集。**変えられるのは表示名・属性ラベル・グループだけ**（A-1）。
/// 接頭辞・桁数・在庫の扱いは、この関数では変えられない。
func editType(typeId: String, name: String, labels: [String?], groupId: String?,
              correctPIN: String, pin: String,
              types: inout [ProductType], groups: [ProductGroup],
              inventory: [Product]) -> EditResult {
    guard pin == correctPIN else { return .failure("PINが違います") }
    guard let i = types.firstIndex(where: { $0.typeId == typeId }) else {
        return .failure("種類が見つかりません: \(typeId)")
    }
    let t = types[i]
    var issues = validateTypeFields(typeId: t.typeId, name: name, idPrefix: t.idPrefix,
                                    idDigits: t.idDigits, labels: labels)
    if let g = groupId, !groups.contains(where: { $0.groupId == g }) {
        issues.append(FieldIssue(column: "group_id", reason: "グループに存在しません"))
    }
    // ラベルを空にすると、値のある属性が「ラベルなしの値」になる
    for k in 0..<3 where labels[k] == nil && inventory.contains(where: { $0.typeId == typeId && $0.attrs[k] != nil }) {
        issues.append(FieldIssue(column: "attr_label_\(k + 1)", reason: "値のある商品があるため空にできません"))
    }
    guard issues.isEmpty else {
        return .failure(issues.map { "\($0.column): \($0.reason)" }.joined(separator: " / "))
    }
    types[i].name = name
    types[i].attrLabel1 = labels[0]; types[i].attrLabel2 = labels[1]; types[i].attrLabel3 = labels[2]
    types[i].groupId = groupId
    return .success("種類を編集: \(typeId)")
}

// ── 商品 ──

struct NewProductInput {
    var typeId: String
    var name: String
    var priceJpy: Int
    var priceSats: Int? = nil
    var attr1: String? = nil
    var attr2: String? = nil
    var attr3: String? = nil
    var initialStock: Int? = nil    // counted: 0以上 / unique: 0か1 / none: nil
    var isPublic: Bool = false
}

enum AddProductResult {
    case success(Product)
    case failure([String])
}

/// 商品を追加する（A-1、A-13）。**検証 → 採番 → INSERT → `nextNo` +1 → 初期在庫ログ**を
/// 1つのまとまりで行う。1件でも問題があれば**何も変えない**。
/// - 採番は `IdSequencer.makeProductID`。桁数を超える場合は追加しない（A-1）。
/// - `nextNo` は減らさない。欠番は再利用しない。
/// - 初期在庫は `initial` で記録する。0 と在庫管理なし型は記録しない（A-1、A-7）。
func addProduct(_ input: NewProductInput,
                correctPIN: String, pin: String,
                inventory: inout [Product],
                types: inout [ProductType],
                movements: inout [StockMovement],
                ids: inout IdSequencer,
                at: Date) -> AddProductResult {

    guard pin == correctPIN else { return .failure(["PINが違います"]) }
    guard let ti = types.firstIndex(where: { $0.typeId == input.typeId }) else {
        return .failure(["type_id: 種類が存在しません"])
    }
    let t = types[ti]

    var problems = validateProductFields(
        name: input.name, priceJpy: input.priceJpy, priceSats: input.priceSats,
        mode: t.stockMode, stock: input.initialStock,
        attrs: [input.attr1, input.attr2, input.attr3], labels: typeLabels(t))
        .map { "\($0.column): \($0.reason)" }

    guard let newId = ids.makeProductID(for: t) else {
        problems.append("product_id: 番号が桁数（\(t.idDigits)）を超えるため追加できません")
        return .failure(problems)
    }
    if inventory.contains(where: { $0.id == newId }) {
        problems.append("product_id: 採番したIDが既に存在します（next_no の不整合）")
    }
    guard problems.isEmpty else { return .failure(problems) }

    // ── ここから先は失敗しない ──
    let p = Product(id: newId, typeId: t.typeId, name: input.name,
                    priceJpy: input.priceJpy, priceSats: input.priceSats,
                    stock: t.stockMode == .none ? nil : input.initialStock,
                    attr1: input.attr1, attr2: input.attr2, attr3: input.attr3,
                    imageRef: nil, isPublic: input.isPublic, updatedAt: at)
    inventory.append(p)
    types[ti].nextNo = t.nextNo + 1
    if t.stockMode != .none, let s = input.initialStock, s > 0 {
        movements.append(StockMovement(
            id: ids.nextMovementID(), productId: newId,
            delta: s, reason: .initial, saleId: nil, at: at))
    }
    return .success(p)
}

/// 商品の編集。**変えられるのは名前・円価格・sats価格・属性・公開状態だけ**（A-1）。
/// 商品ID・種類・在庫は変えられない（在庫は `adjustStock`）。
/// 変更は以降の販売にのみ反映される。過去の販売明細は販売時点の単価を保持する（A-13）。
func editProduct(productId: String, name: String, priceJpy: Int, priceSats: Int?,
                 attrs: [String?], isPublic: Bool,
                 correctPIN: String, pin: String,
                 inventory: inout [Product], types: [ProductType]) -> EditResult {
    guard pin == correctPIN else { return .failure("PINが違います") }
    guard let i = inventory.firstIndex(where: { $0.id == productId }),
          let t = types.first(where: { $0.typeId == inventory[i].typeId }) else {
        return .failure("商品が見つかりません: \(productId)")
    }
    let issues = validateProductFields(name: name, priceJpy: priceJpy, priceSats: priceSats,
                                       mode: t.stockMode, stock: inventory[i].stock,
                                       attrs: attrs, labels: typeLabels(t))
    guard issues.isEmpty else {
        return .failure(issues.map { "\($0.column): \($0.reason)" }.joined(separator: " / "))
    }
    inventory[i].name = name
    inventory[i].priceJpy = priceJpy
    inventory[i].priceSats = priceSats
    inventory[i].attr1 = attrs[0]; inventory[i].attr2 = attrs[1]; inventory[i].attr3 = attrs[2]
    inventory[i].isPublic = isPublic
    return .success("\(productId) を編集")
}



// @section: csv
/// 解析済みの CSV。`headers` は1行目、`rows` は2行目以降（列名 → 値）
struct CSVTable {
    var headers: [String]
    var rows: [[String: String]]
    /// 各行のCSV上の開始行番号（ヘッダ行は含まない）。空行を飛ばしても行番号がずれないようにする。
    var lines: [Int] = []

    func lineNumber(at index: Int) -> Int {
        lines.indices.contains(index) ? lines[index] : index + 2
    }
}

/// CSV の問題1件。`row` は CSV 上の行番号（ヘッダ行が 1、データは 2 から）
struct ValidationIssue: Equatable {
    let row: Int
    let column: String
    let reason: String
}

private func cell(_ row: [String: String], _ col: String) -> String {
    (row[col] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

private func isBlank(_ row: [String: String]) -> Bool {
    row.values.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// 必須列の欠落と、不明な列（A-1）。列の順序は問わない
private func headerIssues(_ t: CSVTable, required: [String], optional: [String]) -> [ValidationIssue] {
    var r: [ValidationIssue] = []
    for c in required where !t.headers.contains(c) {
        r.append(ValidationIssue(row: 1, column: c, reason: "必須列がありません"))
    }
    for c in t.headers where !required.contains(c) && !optional.contains(c) {
        r.append(ValidationIssue(row: 1, column: c, reason: "不明な列です"))
    }
    return r
}

// ── グループ定義CSV ──

func parseGroupCSV(_ t: CSVTable) -> (groups: [ProductGroup], issues: [ValidationIssue]) {
    var issues = headerIssues(t, required: ["group_id", "label"], optional: [])
    if !issues.isEmpty { return ([], issues) }
    var out: [ProductGroup] = []
    var seen = Set<String>()
    for (i, row) in t.rows.enumerated() {
        if isBlank(row) { continue }
        let n = t.lineNumber(at: i)
        let gid = cell(row, "group_id"), label = cell(row, "label")
        for f in validateGroupFields(groupId: gid, label: label) {
            issues.append(ValidationIssue(row: n, column: f.column, reason: f.reason))
        }
        if !gid.isEmpty, !seen.insert(gid).inserted {
            issues.append(ValidationIssue(row: n, column: "group_id", reason: "ファイル内で重複"))
        }
        out.append(ProductGroup(groupId: gid, label: label))
    }
    return (issues.isEmpty ? out : [], issues)
}

/// 既存のグループはラベルを更新し、新規は追加する（A-1）
func applyGroups(_ parsed: [ProductGroup], groups: inout [ProductGroup]) {
    for g in parsed {
        if let i = groups.firstIndex(where: { $0.groupId == g.groupId }) {
            groups[i].label = g.label
        } else {
            groups.append(g)
        }
    }
}

// ── 種類定義CSV ──

struct ParsedType: Equatable {
    let type: ProductType
    let csvNextNo: Int?        // CSV の next_no。空なら nil
}

/// - Parameters:
///   - groups: 取り込み後に存在するグループ（既存＋今回のグループ定義）
func parseTypeCSV(_ t: CSVTable,
                  groups: [ProductGroup],
                  existing: [ProductType],
                  inventory: [Product],
                  items: [SaleItem]) -> (types: [ParsedType], issues: [ValidationIssue]) {

    var issues = headerIssues(t,
        required: ["type_id", "name", "id_prefix", "id_digits", "stock_mode"],
        optional: ["attr_label_1", "attr_label_2", "attr_label_3", "group_id", "next_no"])
    if !issues.isEmpty { return ([], issues) }

    var out: [ParsedType] = []
    var seenIds = Set<String>()
    var seenPrefix: [String: String] = [:]      // 接頭辞 → type_id
    var rowByTypeId: [String: Int] = [:]

    for (i, row) in t.rows.enumerated() {
        if isBlank(row) { continue }
        let n = t.lineNumber(at: i)
        func bad(_ col: String, _ why: String) {
            issues.append(ValidationIssue(row: n, column: col, reason: why))
        }

        let typeId = cell(row, "type_id"), name = cell(row, "name"), prefix = cell(row, "id_prefix")
        let digits = parseInt(cell(row, "id_digits")) ?? 0     // 0 は検証側が「1以上」で弾く
        let gid = cell(row, "group_id")
        let labels: [String?] = (1...3).map { (k: Int) -> String? in
            let v = cell(row, "attr_label_\(k)")
            return v.isEmpty ? nil : v
        }
        let mode = StockMode(rawValue: cell(row, "stock_mode"))
        if mode == nil { bad("stock_mode", "counted／unique／none のいずれか") }

        for f in validateTypeFields(typeId: typeId, name: name, idPrefix: prefix,
                                    idDigits: digits, labels: labels) {
            bad(f.column, f.reason)
        }
        if !typeId.isEmpty {
            rowByTypeId[typeId] = n
            if !seenIds.insert(typeId).inserted { bad("type_id", "ファイル内で重複") }
        }
        if !prefix.isEmpty {
            if let owner = seenPrefix[prefix], owner != typeId { bad("id_prefix", "ファイル内で重複（\(owner)）") }
            seenPrefix[prefix] = typeId
        }
        if !gid.isEmpty, !groups.contains(where: { $0.groupId == gid }) {
            bad("group_id", "グループに存在しません")
        }

        let old = existing.first { $0.typeId == typeId }

        // 値のある属性がある商品のラベルは外せない（編集画面と同じ扱い）
        if let o = old {
            for k in 0..<3 where labels[k] == nil
                && inventory.contains(where: { $0.typeId == o.typeId && $0.attrs[k] != nil }) {
                bad("attr_label_\(k + 1)", "値のある商品があるため空にできません")
            }
        }

        // next_no（A-1）
        var csvNext: Int? = nil
        let nextRaw = cell(row, "next_no")
        if !nextRaw.isEmpty {
            if let v = parseInt(nextRaw), v >= 1 {
                csvNext = v
                if let o = old {
                    if v <= maxProductNumber(of: o, in: inventory) { bad("next_no", "現存商品の最大番号以下") }
                    if v < o.nextNo { bad("next_no", "現在値（\(o.nextNo)）より小さい") }
                }
            } else {
                bad("next_no", "1以上の整数")
            }
        }

        // 商品または販売記録がある種類は、接頭辞・桁数・在庫の扱いを変えられない（A-1）
        if let o = old, let m = mode {
            let hasRecords = inventory.contains { $0.typeId == o.typeId }
                          || items.contains { $0.typeId == o.typeId }
            if hasRecords {
                if prefix != o.idPrefix { bad("id_prefix", "商品または販売記録がある種類は変更不可") }
                if digits != o.idDigits { bad("id_digits", "商品または販売記録がある種類は変更不可") }
                if m != o.stockMode { bad("stock_mode", "商品または販売記録がある種類は変更不可") }
            }
        }

        if let m = mode {
            var pt = old ?? ProductType(typeId: typeId, name: name, idPrefix: prefix,
                                        idDigits: digits, stockMode: m)
            pt.name = name; pt.idPrefix = prefix; pt.idDigits = digits; pt.stockMode = m
            pt.attrLabel1 = labels[0]; pt.attrLabel2 = labels[1]; pt.attrLabel3 = labels[2]
            pt.groupId = gid.isEmpty ? nil : gid
            out.append(ParsedType(type: pt, csvNextNo: csvNext))
        }
    }

    // 取り込み後の状態で接頭辞の一意性を確認する。
    // これにより、同じCSV内で接頭辞を入れ替えるような更新も正しく判定できる。
    var finalByPrefix: [String: [String]] = [:]
    var final = Dictionary(uniqueKeysWithValues: existing.map { ($0.typeId, $0) })
    for p in out { final[p.type.typeId] = p.type }
    for t in final.values { finalByPrefix[t.idPrefix, default: []].append(t.typeId) }
    for (prefix, ids) in finalByPrefix where ids.count > 1 {
        for id in ids where rowByTypeId[id] != nil {
            issues.append(ValidationIssue(row: rowByTypeId[id] ?? 0,
                                          column: "id_prefix",
                                          reason: "接頭辞が重複しています（\(prefix)）"))
        }
    }

    return (issues.isEmpty ? out : [], issues)
}

/// `nextNo` の決め方（A-1）。
/// 空 → 「現存最大番号+1」と「現在値」の大きい方。値あり → 検証済みなので、その値以上を採る。
func resolveNextNo(csv: Int?, current: ProductType?, maxExisting: Int) -> Int {
    let base = max(current?.nextNo ?? 1, maxExisting + 1)
    guard let n = csv else { return base }
    return max(base, n)
}

func applyTypes(_ parsed: [ParsedType], types: inout [ProductType],
                inventory: [Product], at: Date = Date()) {
    for p in parsed {
        let old = types.first { $0.typeId == p.type.typeId }
        var t = p.type
        let maxNo = old.map { maxProductNumber(of: $0, in: inventory) } ?? 0
        t.nextNo = resolveNextNo(csv: p.csvNextNo, current: old, maxExisting: maxNo)
        t.updatedAt = at
        if let i = types.firstIndex(where: { $0.typeId == t.typeId }) {
            types[i] = t
        } else {
            types.append(t)
        }
    }
}

// ── 商品マスタCSV ──

/// - Parameters:
///   - types: 取り込み後に存在する種類（既存＋今回の種類定義を適用したあと）
func parseProductCSV(_ t: CSVTable,
                     types: [ProductType],
                     inventory: [Product]) -> (products: [Product], issues: [ValidationIssue]) {

    var issues = headerIssues(t,
        required: ["product_id", "type_id", "name", "price_jpy", "is_public"],
        optional: ["price_sats", "stock", "attr_1", "attr_2", "attr_3"])
    if !issues.isEmpty { return ([], issues) }

    var out: [Product] = []
    var seen = Set<String>()
    var needsStock = false

    let typesWithProducts = Set(inventory.map { $0.typeId })

    for (i, row) in t.rows.enumerated() {
        if isBlank(row) { continue }
        let n = t.lineNumber(at: i)
        func bad(_ col: String, _ why: String) {
            issues.append(ValidationIssue(row: n, column: col, reason: why))
        }

        let pid = cell(row, "product_id"), tid = cell(row, "type_id"), name = cell(row, "name")
        guard let ty = types.first(where: { $0.typeId == tid }) else {
            bad("type_id", "種類定義に存在しません")
            continue
        }
        if ty.stockMode != .none { needsStock = true }

        let existing = inventory.first { $0.id == pid }
        let num = productNumber(of: pid, in: ty)
        if num == nil { bad("product_id", "形式が <接頭辞>-<\(ty.idDigits)桁の番号> と一致しません") }
        if !pid.isEmpty, !seen.insert(pid).inserted { bad("product_id", "ファイル内で重複") }
        if let e = existing {
            if e.typeId != tid { bad("type_id", "既存商品の種類は変更不可") }
        } else if let k = num, k < ty.nextNo, typesWithProducts.contains(ty.typeId) {
            bad("product_id", "番号 \(pid) は種類 \(ty.typeId) の next_no（\(ty.nextNo)）未満です。既存商品があるため、欠番の再利用として拒否しました")
        }

        let priceJpy = parseInt(cell(row, "price_jpy")) ?? 0
        let satsRaw = cell(row, "price_sats")
        let priceSats: Int? = satsRaw.isEmpty ? nil : (parseInt(satsRaw) ?? 0)
        let stockRaw = cell(row, "stock")
        let stock: Int? = stockRaw.isEmpty ? nil : (parseInt(stockRaw) ?? -1)
        let attrs: [String?] = (1...3).map { (k: Int) -> String? in
            let v = cell(row, "attr_\(k)")
            return v.isEmpty ? nil : v
        }
        let pub: Bool
        switch cell(row, "is_public") {
        case "1": pub = true
        case "0": pub = false
        default:  bad("is_public", "1 か 0"); pub = false
        }

        for f in validateProductFields(name: name, priceJpy: priceJpy, priceSats: priceSats,
                                       mode: ty.stockMode, stock: stock,
                                       attrs: attrs, labels: typeLabels(ty)) {
            bad(f.column, f.reason)
        }
        out.append(Product(id: pid, typeId: tid, name: name, priceJpy: priceJpy, priceSats: priceSats,
                           stock: stock, attr1: attrs[0], attr2: attrs[1], attr3: attrs[2],
                           imageRef: nil, isPublic: pub, updatedAt: nil))
    }
    if needsStock && !t.headers.contains("stock") {
        issues.append(ValidationIssue(row: 1, column: "stock", reason: "在庫管理ありの種類の商品があるため、列が必須"))
    }
    return (issues.isEmpty ? out : [], issues)
}

/// 商品マスタを適用する（A-1）。
/// - 既存の商品ID: 名前・価格・属性・公開状態だけ更新。**在庫は変更しない**
/// - 新規の商品ID: `registerInitialStock`（`initial` を記録、`nextNo` を更新）
/// - CSV に無い既存商品: 変更しない
/// - `overwriteStock` が true のときだけ、既存商品の在庫を CSV の値で上書きし `adjust` で記録する
///   （差分一覧の表示と確認ダイアログは呼び出し側。在庫管理なし型は対象外）
func applyProductMaster(_ parsed: [Product],
                        inventory: inout [Product],
                        movements: inout [StockMovement],
                        ids: inout IdSequencer,
                        types: inout [ProductType],
                        overwriteStock: Bool,
                        at: Date) {
    var fresh: [Product] = []
    for parsedProduct in parsed {
        var p = parsedProduct
        p.updatedAt = at
        guard let i = inventory.firstIndex(where: { $0.id == p.id }) else {
            fresh.append(p)
            continue
        }
        inventory[i].name = p.name
        inventory[i].priceJpy = p.priceJpy
        inventory[i].priceSats = p.priceSats
        inventory[i].attr1 = p.attr1; inventory[i].attr2 = p.attr2; inventory[i].attr3 = p.attr3
        inventory[i].isPublic = p.isPublic
        inventory[i].updatedAt = at

        if overwriteStock,
           inventory[i].managesStock(in: types),
           let new = p.stock, let cur = inventory[i].stock, new != cur {
            inventory[i].stock = new
            movements.append(StockMovement(
                id: ids.nextMovementID(), productId: p.id,
                delta: new - cur, reason: .adjust, saleId: nil, at: at))
        }
    }
    registerInitialStock(fresh, inventory: &inventory, movements: &movements,
                         ids: &ids, types: &types, at: at)
}



// @section: day
/// この会計を「何日目のもの」にするか。
/// - `completed` / 販売取消: `completed_at`（A-19-11）
/// - **sats確認済みの中断: `confirmed_at`**（`completed_at` が無いので）
func saleDay(_ sale: Sale) -> Date? {
    sale.completedAt ?? sale.confirmedAt
}

/// 「ローカル日付が day の日」の会計だけを取り出す（A-19-5、A-19-11）
func salesOn(_ day: Date, in sales: [Sale]) -> [Sale] {
    salesIn(from: day, to: day, in: sales)
}

/// 開始日〜終了日（含む）の会計を取り出す。nil は上限・下限なし（A-8）。
/// 日の比較は、端末のローカル日付の `YYYYMMDD` 文字列で行う（A-19-5）。
func salesIn(from: Date?, to: Date?, in sales: [Sale]) -> [Sale] {
    sales.filter { sale in
        guard let d = saleDay(sale) else { return false }
        let k = DayKey.string(from: d)
        if let f = from, k < DayKey.string(from: f) { return false }
        if let t = to, k > DayKey.string(from: t) { return false }
        return true
    }
}



// @section: summary
/// 集計の枠（A-8）
enum SummaryFrame: String {
    case sales        // status = completed。精算額に算入する
    case canceled     // voided かつ completedAt あり（販売取消・A-9）
    case suspended    // voided かつ completedAt 空（sats確認済みの中断・A-4）
}

/// 集計の軸。グループ → 登録/野良 → 種類 → 受取方法（A-8）
struct SettlementKey: Hashable {
    let groupId: String?         // nil = グループなし
    let itemType: ItemType
    let typeId: String?          // 野良は nil
    let paidIn: PaidIn

    var sortKey: String {
        "\(groupId ?? "")|\(itemType.rawValue)|\(typeId ?? "")|\(paidIn.rawValue)"
    }
}

/// 明細数・数量・金額（A-8）。`amount` は `paidIn` が jpy なら円、sats ならsats
struct SettlementAmount: Equatable {
    var lineCount = 0
    var qty = 0
    var amount = 0
}

struct Summary {
    // 売上（status = completed だけ）の受取方法別
    var cashSaleIDs: Set<String> = []
    var cashJpy: Int = 0                      // 現金決済の円合計 ＋ 併用会計の現金分
    var satsSaleIDs: Set<String> = []
    var satsAmount: Int = 0
    var mixedSaleIDs: Set<String> = []        // 併用会計（現金とsatsの両方に計上される）

    // 売上に含めない枠
    var canceledSaleIDs: Set<String> = []
    var suspendedSaleIDs: Set<String> = []
    var suspendedSats: Int = 0                // suspendedSaleIDs の totalSats 合計（A-8）

    // 明細の集計（枠 → 軸 → 金額）
    var lines: [SummaryFrame: [SettlementKey: SettlementAmount]] = [:]

    /// 軸の順に並べた明細集計（表示・CSV 出力用）
    func sortedLines(_ f: SummaryFrame) -> [(key: SettlementKey, value: SettlementAmount)] {
        (lines[f] ?? [:]).sorted { $0.key.sortKey < $1.key.sortKey }
    }

    /// 受取方法別の金額合計。`itemType` を指定すると登録商品／野良に絞る
    func amount(_ f: SummaryFrame, paidIn: PaidIn, itemType: ItemType? = nil) -> Int {
        (lines[f] ?? [:])
            .filter { $0.key.paidIn == paidIn && (itemType == nil || $0.key.itemType == itemType) }
            .values.reduce(0) { $0 + $1.amount }
    }
}

/// この会計がどの枠に入るか（A-19-7）
func summaryFrame(of sale: Sale) -> SummaryFrame {
    switch sale.status {
    case .completed: return .sales
    case .voided:    return sale.completedAt == nil ? .suspended : .canceled
    }
}

func groupLabel(_ groupId: String?, groups: [ProductGroup]) -> String {
    guard let g = groupId else { return "グループなし" }
    return groups.first { $0.groupId == g }?.label ?? g
}

/// 会計の集計（A-8）。**期間の切りは呼ぶ側**（`salesIn`）。「日」はローカル日付（A-19-5）。
/// 明細は、`sales` に含まれる会計のものだけを数える。
func summarize(_ sales: [Sale], items: [SaleItem]) -> Summary {
    var s = Summary()
    var frameOf: [String: SummaryFrame] = [:]

    for sale in sales {
        let f = summaryFrame(of: sale)
        frameOf[sale.id] = f
        switch f {
        case .suspended:
            s.suspendedSaleIDs.insert(sale.id)
            s.suspendedSats += sale.totalSats ?? 0          // A-8：件数・sats合計を別に表示
        case .canceled:
            s.canceledSaleIDs.insert(sale.id)
        case .sales:
            switch sale.method {
            case .cash:
                s.cashSaleIDs.insert(sale.id); s.cashJpy += sale.totalJpy ?? 0
            case .lightning:
                s.satsSaleIDs.insert(sale.id); s.satsAmount += sale.totalSats ?? 0
            case .mixed:
                s.cashSaleIDs.insert(sale.id); s.cashJpy += sale.totalJpy ?? 0
                s.satsSaleIDs.insert(sale.id); s.satsAmount += sale.totalSats ?? 0
                s.mixedSaleIDs.insert(sale.id)
            }
        }
    }

    for item in items {
        guard let f = frameOf[item.saleId] else { continue }
        let key = SettlementKey(groupId: item.groupId, itemType: item.itemType,
                                typeId: item.typeId, paidIn: item.paidIn)
        // 明細の単価×数量を、paid_in ごとに集計する（円とsatsは合算しない）
        let amount = item.paidIn == .sats
            ? (item.unitPriceSats ?? 0) * item.qty
            : item.unitPriceJpy * item.qty
        var c = s.lines[f, default: [:]][key, default: SettlementAmount()]
        c.lineCount += 1
        c.qty += item.qty
        c.amount += amount
        s.lines[f, default: [:]][key] = c
    }
    return s
}



// @section: period
struct DaySubtotal {
    let day: String           // YYYYMMDD（ローカル日付）
    let summary: Summary
}

struct PeriodSummary {
    let startDay: String?     // 指定した開始日。nil = 指定なし
    let endDay: String?
    let total: Summary
    let days: [DaySubtotal]   // 期間内の日ごとの小計
}

/// 期間全体の集計（A-8）。開始日＝終了日にすると日次集計と同じ結果になる。
/// 現金照合は日ごとに行い、期間全体では行わない（`reconcileCash`）。
func summarizeRange(_ sales: [Sale], items: [SaleItem], from: Date?, to: Date?) -> PeriodSummary {
    let target = salesIn(from: from, to: to, in: sales)
    let saleIds = Set(target.map { $0.id })
    let its = items.filter { saleIds.contains($0.saleId) }

    var byDay: [String: [Sale]] = [:]
    for s in target {
        if let d = saleDay(s) { byDay[DayKey.string(from: d), default: []].append(s) }
    }
    let days = byDay.keys.sorted().map { DaySubtotal(day: $0, summary: summarize(byDay[$0] ?? [], items: its)) }

    return PeriodSummary(startDay: from.map { DayKey.string(from: $0) },
                         endDay: to.map { DayKey.string(from: $0) },
                         total: summarize(target, items: its),
                         days: days)
}

// ── グループ別精算CSV（A-8）──

struct SettlementRow: Equatable {
    let groupId: String?          // グループなしは nil（CSV では空）
    let groupLabel: String?       // 出力時点のラベル
    let itemType: ItemType
    let typeId: String?
    let paidIn: PaidIn
    let lineCount: Int
    let qty: Int
    let amount: Int
    let periodStart: String
    let periodEnd: String
}

enum SettlementResult {
    case success([SettlementRow])
    case failure(String)
}

/// グループ別精算CSVの行を作る（A-8）。**PIN必須**。
/// 対象は `status = completed` の明細だけ。販売取消・sats確認済み中断は含めない。
func settlementRows(_ period: PeriodSummary,
                    groups: [ProductGroup],
                    periodStart: String, periodEnd: String,
                    correctPIN: String, pin: String) -> SettlementResult {
    guard pin == correctPIN else { return .failure("PINが違います") }
    let rows = period.total.sortedLines(.sales).map { e in
        SettlementRow(groupId: e.key.groupId,
                      groupLabel: e.key.groupId.flatMap { g in groups.first { $0.groupId == g }?.label },
                      itemType: e.key.itemType, typeId: e.key.typeId, paidIn: e.key.paidIn,
                      lineCount: e.value.lineCount, qty: e.value.qty, amount: e.value.amount,
                      periodStart: periodStart, periodEnd: periodEnd)
    }
    return .success(rows)
}

private func csvField(_ s: String) -> String {
    guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
    return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

/// 精算CSVの本文（A-8 の列）。改行は LF
func settlementCSV(_ rows: [SettlementRow]) -> String {
    var lines = ["group_id,group_label,item_type,type_id,paid_in,line_count,qty,amount,period_start,period_end"]
    for r in rows {
        let cols = [r.groupId ?? "", r.groupLabel ?? "", r.itemType.rawValue, r.typeId ?? "",
                    r.paidIn.rawValue, String(r.lineCount), String(r.qty), String(r.amount),
                    r.periodStart, r.periodEnd]
        lines.append(cols.map(csvField).joined(separator: ","))
    }
    return lines.joined(separator: "\n")
}

// ── 現金照合（A-8）──

struct CashReconciliation {
    let float: Int          // 釣銭準備金
    let cashSales: Int      // 現金売上（現金決済の円合計 ＋ 併用会計の現金分）
    let expected: Int       // 準備金 ＋ 現金売上
    let actual: Int         // 実残高
    var difference: Int { actual - expected }
}

/// 現金照合。**日ごとに行い、期間全体では行わない**（A-8）。
/// 現金売上は `status = completed` の会計だけ。販売取消・sats確認済み中断は含めない。
func reconcileCash(day: Date, float: Int, actual: Int,
                   sales: [Sale], items: [SaleItem]) -> CashReconciliation {
    let s = summarize(salesOn(day, in: sales), items: items)
    return CashReconciliation(float: float, cashSales: s.cashJpy,
                              expected: float + s.cashJpy, actual: actual)
}

// ── sats照合（A-8）──

/// sats決済の一覧（WoS履歴との照合用）。**sats確認済みで中断した会計（`voided`）を含む**（A-8）。
/// 列は `sale_id`、`status`、`completed_at`、`confirmed_at`、`total_sats`、`total_jpy`、`refunded`。
func satsReconciliation(_ sales: [Sale]) -> [Sale] {
    sales.filter { $0.method != .cash && $0.totalSats != nil }
         .sorted { (saleDay($0) ?? .distantPast) < (saleDay($1) ?? .distantPast) }
}



// @section: refund
/// 返金済みフラグ（sats分）を設定する。**PIN必須**（A-11）。
/// 併用会計の現金分の返却は、システム外の手動対応で、記録を保持しない（A-9）。
/// - Note: 対象は「sats分がある `voided`（販売取消、sats確認済みの中断）」に限る（仮置き・Q12）。
func setRefunded(saleId: String, value: Bool = true,
                 correctPIN: String, pin: String,
                 sales: inout [Sale]) -> EditResult {
    guard pin == correctPIN else { return .failure("PINが違います") }
    guard let i = sales.firstIndex(where: { $0.id == saleId }) else {
        return .failure("会計が見つかりません: \(saleId)")
    }
    guard sales[i].status == .voided else {
        return .failure("返金済みにできるのは取消・中断した会計だけです")
    }
    guard sales[i].totalSats != nil else {
        return .failure("sats分がない会計です")
    }
    sales[i].refunded = value
    return .success("\(saleId): refunded = \(value)")
}



// @section: snapshot
/// 送信スナップショットを作る。**`image_ref` は含めない**。
/// `has_image` は保存先フォルダまたは同梱画像の実在から導出（A-14）。
/// グループは送信しない（A-14）。
func makeSnapshot(types: [ProductType], inventory: [Product], now: Date) -> Snapshot {
    let publicProducts = inventory.filter { $0.isPublic }
    let usedTypeIDs = Set(publicProducts.map { $0.typeId })
    let usedTypes = types
        .filter { usedTypeIDs.contains($0.typeId) }
        .map { t in
            SnapshotType(typeId: t.typeId, name: t.name, stockMode: t.stockMode,
                         attrLabels: [t.attrLabel1, t.attrLabel2, t.attrLabel3].compactMap { $0 })
        }
    let products = publicProducts.map { p in
        SnapshotProduct(productId: p.id, typeId: p.typeId, name: p.name,
                        priceJpy: p.priceJpy, priceSats: p.priceSats,
                        attrs: [p.attr1, p.attr2, p.attr3],
                        stock: p.stock, hasImage: p.hasDisplayImage)
    }
    return Snapshot(createdAt: now, types: usedTypes, products: products)
}

/// 送信の成否を `sync_log` に記録する（A-14）。**失敗しても会計・在庫には影響させない**。
func recordSync(_ log: inout [SyncLogEntry], ids: inout IdSequencer,
                snapshot: Snapshot, error: String?, at: Date) -> SyncLogEntry {
    let entry = SyncLogEntry(id: ids.nextLogID(), at: at,
                             result: error == nil ? .success : .failed,
                             detail: error ?? "送信成功（商品 \(snapshot.products.count)件）")
    log.append(entry)
    return entry
}


