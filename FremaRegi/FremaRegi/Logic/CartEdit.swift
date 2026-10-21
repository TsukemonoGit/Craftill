/// 商品をカートに追加できるかの判定結果
enum AddCheck: Equatable {
    case ok                                    // 追加できる
    case soldOut                               // 在庫0（A-1）。追加経路によらず不可
    case duplicateUnique                       // 一点物型が同一会計に既にある（A-1、C-6 #6）
    case overStock(current: Int, need: Int)     // 在庫不足（A-3、C-6 #7）
}

/// 商品をカートに追加できるか判定する。**何も書き換えない**。
/// - 在庫0は **追加経路によらず** 不可（A-1「QR・手動入力・商品パネルによらず」）
/// - 一点物型は **同一会計で2回** 追加できない（A-1、C-6 #6）
/// - 数量管理型は **すでに入っている分を足した** 総数で在庫と比べる（C-6 #7）
/// - 在庫管理なし型・野良は **上限なし**（A-1）
func addCheck(product p: Product, qty: Int, cart: [CartLine],
              inventory: [Product], types: [ProductType]) -> AddCheck {
    guard let i = inventory.firstIndex(where: { $0.id == p.id }) else { return .ok }
    let mode = inventory[i].stockMode(in: types)      // ★ 在庫の扱いは「種類」が決める（A-1）
    guard mode != .none else { return .ok }           // 在庫管理なし型は上限なし
    guard let stock = inventory[i].stock else { return .ok }

    if stock == 0 { return .soldOut }                 // A-1

    let inCart = cart.first { $0.id == p.id && !$0.isAdhoc }
    switch mode {
    case .unique:
        return inCart == nil ? .ok : .duplicateUnique
    case .counted:
        let after = (inCart?.qty ?? 0) + qty
        return after <= stock ? .ok : .overStock(current: stock, need: after)
    case .none:
        return .ok
    }
}

/// 判定の理由メッセージ。画面はこの1文をそのまま表示する
func addCheckMessage(_ c: AddCheck, productName: String) -> String {
    switch c {
    case .ok:              return "\(productName) を追加できます"
    case .soldOut:         return "SOLD OUT: \(productName)"
    case .duplicateUnique: return "\(productName) は一点物なので、同じ会計には1つだけ入れられます"
    case .overStock(let c, let n):
        return "在庫超過: \(productName)（在庫 \(c)、合計 \(n) 個になります）"
    }
}

/// 実際にカートへ追加する。`addCheck` が `.ok` のときだけ進む
func add(product p: Product, qty: Int, cart: inout [CartLine],
         inventory: [Product], types: [ProductType]) -> CartEdit {
    let check = addCheck(product: p, qty: qty, cart: cart, inventory: inventory, types: types)
    guard case .ok = check else {
        return .rejected(addCheckMessage(check, productName: p.name))
    }
    if let i = cart.firstIndex(where: { $0.id == p.id && !$0.isAdhoc }) {
        cart[i].qty += qty                              // すでに入っている行へ加算
        return .applied("\(p.name) ×\(cart[i].qty)")
    }
    cart.append(CartLine(product: p, qty: qty, in: types))
    return .applied("\(p.name) を追加しました")
}

/// SOLD OUT かどうか（商品パネルの表示用・C-6 #33）
/// - **在庫管理なし型は SOLD OUT にならない**（A-1、B-1）
func isSoldOut(_ p: Product, in inventory: [Product], types: [ProductType]) -> Bool {
    guard let i = inventory.firstIndex(where: { $0.id == p.id }) else { return false }
    guard inventory[i].managesStock(in: types) else { return false }
    return (inventory[i].stock ?? 0) == 0
}

/// 削除の確認ダイアログ。**表示するものは商品名と数量**（A-3）
struct CartDelete: Equatable {
    let index: Int        // 削除対象の行
    let name: String
    let qty: Int
    var message: String { "\(name) ×\(qty)" }
}

/// カート編集の結果。**確認ダイアログが要るか**で3つに分かれる。
enum CartEdit: Equatable {
    case applied(String)            // そのまま実行した。表示するメッセージ
    case needsConfirm(CartDelete)   // **まだ何も変えていない**。ダイアログで OK なら performDelete
    case rejected(String)           // できない（一点物・在庫超過・範囲外）
}

/// この行の在庫の扱い。**種類が決める**（A-1）。野良は種類を持たないので nil
func stockMode(of line: CartLine, in types: [ProductType]) -> StockMode? {
    guard let typeId = line.typeId else { return nil }      // 野良は種類を持たない
    return types.first { $0.typeId == typeId }?.stockMode
}

/// この行の**いまの**在庫。**在庫表から引く**（カートは在庫を持たない・A-7）
func currentStock(of line: CartLine, in inventory: [Product]) -> Int? {
    inventory.first { $0.id == line.id }?.stock
}

/// 数量を1増やす。**できるなら即実行**するので `inout`。
func increase(at i: Int,
              cart: inout [CartLine],
              inventory: [Product],
              types: [ProductType]) -> CartEdit {
    guard cart.indices.contains(i) else { return .rejected("行がありません") }
    let line = cart[i]

    // ★ `Optional<StockMode>` の `.none` と `StockMode.none` は名前がぶつかる。
    //   `if let` で取り出してから switch するのが安全（A-1：在庫管理なし型）。
    if let mode = stockMode(of: line, in: types) {
        switch mode {
        case .unique:
            return .rejected("\(line.name) は一点物なので数量1固定です")
        case .counted:
            // 在庫管理ありは在庫を超えない（A-3）
            if let stock = currentStock(of: line, in: inventory), line.qty + 1 > stock {
                return .rejected("在庫超過: \(line.name)（在庫 \(stock)）")
            }
        case .none:
            break                              // 在庫管理なし型は上限なし（A-1）
        }
    }
    // 上の `if let` が通らなかった＝野良。野良は種類を持たず上限なし（A-1）

    cart[i].qty += 1
    return .applied("\(line.name) ×\(cart[i].qty)")
}

/// 数量を1減らす。
/// - 減った結果が **0 になるなら、まだ何も変えず** 確認だけを要求する（C-6 #50）
/// - 0にならない増減では確認を要求しない（同 #50「数量が0にならない増減では表示されない」）
func decrease(at i: Int,
              cart: inout [CartLine],
              inventory: [Product],
              types: [ProductType]) -> CartEdit {
    guard cart.indices.contains(i) else { return .rejected("行がありません") }
    let line = cart[i]

    guard stockMode(of: line, in: types) != .unique else {
        return .rejected("\(line.name) は一点物なので数量1固定です")
    }

    if line.qty - 1 <= 0 {
        // ★ 0 になるなら行の削除になる。**この return より先に 1 度も書き換えない**
        return .needsConfirm(CartDelete(index: i, name: line.name, qty: line.qty))
    }

    // 0にならない増減はそのまま実行（確認ダイアログは出さない・C-6 #50）
    cart[i].qty -= 1
    return .applied("\(line.name) ×\(cart[i].qty)")
}

/// 行の削除を**要求**する。まだ削除はしない。
func remove(at i: Int, cart: [CartLine]) -> CartEdit {
    guard cart.indices.contains(i) else { return .rejected("行がありません") }
    let line = cart[i]
    return .needsConfirm(CartDelete(index: i, name: line.name, qty: line.qty))
}

/// ダイアログで「削除」を選んだとき
func performDelete(_ d: CartDelete, cart: inout [CartLine]) -> String {
    guard cart.indices.contains(d.index) else { return "対象が消えていました" }
    cart.remove(at: d.index)
    return "削除: \(d.message)"
}

/// ダイアログで「キャンセル」を選んだとき。**何もしない**（C-6 #49/#50/#51）
func cancelDelete() -> String {
    return "何もしませんでした"
}

/// SwiftUI 側は `.alert` を受けて.then これを呼ぶ（`09` レッスン §4）
