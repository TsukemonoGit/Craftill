

// ════════ 通しの確認（カートへの追加と編集・A-1 / A-3 / C-6 #6 #7 #33 #49 #50）════════

// ── 前提データ（base/Types.swift 相当）──
let types: [ProductType] = [
    ProductType(typeId: "sticker", name: "ステッカー", idPrefix: "ST", idDigits: 3,
                stockMode: .counted, attrLabel1: "色", attrLabel2: "模様", attrLabel3: nil, updatedAt: nil),
    ProductType(typeId: "keyholder", name: "キーホルダー", idPrefix: "KH", idDigits: 3,
                stockMode: .unique, attrLabel1: "色", attrLabel2: "模様", attrLabel3: nil, updatedAt: nil),
    ProductType(typeId: "ticket", name: "入場券", idPrefix: "TB", idDigits: 3,
                stockMode: .none, attrLabel1: nil, attrLabel2: nil, attrLabel3: nil, updatedAt: nil),
]
var inventory: [Product] = [
    Product(id: "ST-001", typeId: "sticker", name: "ステッカー まる", priceJpy: 300, priceSats: 500,
            stock: 3, attr1: "黄", attr2: "まる", attr3: nil, imageRef: nil,
            isPublic: true, updatedAt: nil),
    Product(id: "ST-002", typeId: "sticker", name: "ステッカー さんかく", priceJpy: 300, priceSats: 500,
            stock: 0, attr1: "青", attr2: "さんかく", attr3: nil, imageRef: nil,
            isPublic: true, updatedAt: nil),
    Product(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01", priceJpy: 800, priceSats: 1200,
            stock: 1, attr1: "赤", attr2: "○", attr3: nil, imageRef: nil,
            isPublic: true, updatedAt: nil),
    Product(id: "KH-002", typeId: "keyholder", name: "キーホルダー 02", priceJpy: 800, priceSats: 1200,
            stock: 1, attr1: "青", attr2: "△", attr3: nil, imageRef: nil,
            isPublic: true, updatedAt: nil),
    Product(id: "TB-001", typeId: "ticket", name: "入場券", priceJpy: 1000, priceSats: nil,
            stock: nil, attr1: nil, attr2: nil, attr3: nil, imageRef: nil,
            isPublic: true, updatedAt: nil),
]
var cart: [CartLine] = []

func line(_ s: String) { print("  " + s) }
func show(_ r: CartEdit) -> String {
    switch r {
    case .applied(let m):      return "applied(\(m))"
    case .needsConfirm(let d): return "needsConfirm(\(d.message) を削除しますか)"
    case .rejected(let m):     return "rejected(\(m))"
    }
}
func rows() -> String {
    cart.enumerated().map { "[\($0.offset)]\($0.element.name)×\($0.element.qty)" }
        .joined(separator: " / ")
}

print("【0】はじめのカート")
line(rows())

print("【1】数量管理型を追加（A-1）")
line("ST-001 を1個: " + show(add(product: inventory[0], qty: 1, cart: &cart, inventory: inventory, types: types)))
line(rows())

print("【2】すでに入っているものを追加すると数量が増える（A-1）")
line("ST-001 を1個: " + show(add(product: inventory[0], qty: 1, cart: &cart, inventory: inventory, types: types)))
line(rows())

print("【3】一点物型は1つだけ（C-6 #6）")
line("KH-001 を1個: " + show(add(product: inventory[2], qty: 1, cart: &cart, inventory: inventory, types: types)))
line("KH-001 を1個: " + show(add(product: inventory[2], qty: 1, cart: &cart, inventory: inventory, types: types)))
line(rows())

print("【4】在庫0は SOLD OUT（追加経路によらず不可・A-1 / C-6 #33）")
line("ST-002: " + show(add(product: inventory[1], qty: 1, cart: &cart, inventory: inventory, types: types)))
line("isSoldOut(ST-002): \(isSoldOut(inventory[1], in: inventory, types: types))")
line("isSoldOut(ST-001): \(isSoldOut(inventory[0], in: inventory, types: types))")
line("isSoldOut(入場券): \(isSoldOut(inventory[4], in: inventory, types: types))　← 在庫管理なし型は SOLD OUT にならない（A-1）")

print("【5】在庫管理なし型は上限なし（A-1）")
for _ in 1...3 {
    line("入場券を1枚: " + show(add(product: inventory[4], qty: 1, cart: &cart, inventory: inventory, types: types)))
}
line(rows())

print("【6】在庫超過は弾かれる（C-6 #7）")
line("KH-002 を2個: " + show(add(product: inventory[3], qty: 2, cart: &cart, inventory: inventory, types: types)))
line("KH-002 を1個: " + show(add(product: inventory[3], qty: 1, cart: &cart, inventory: inventory, types: types)))
line("KH-002 を1個: " + show(add(product: inventory[3], qty: 1, cart: &cart, inventory: inventory, types: types)))

print("【7】＋ を押す（0にならない増減 → ダイアログは出ない・C-6 #50）")
line("ST-001 を＋: " + show(increase(at: 0, cart: &cart, inventory: inventory, types: types)))

print("【8】－ で 0にならない増減（ダイアログは出ない・C-6 #50）")
line("ST-001 を－: " + show(decrease(at: 0, cart: &cart, inventory: inventory, types: types)))
line(rows())

print("【9】－ で 0になるとき（needsConfirm。#50）")
var pending: CartDelete?
switch decrease(at: 0, cart: &cart, inventory: inventory, types: types) {
case .needsConfirm(let d):
    pending = d
    line("needsConfirm: " + d.message + " を削除しますか")
default:
    line("ダイアログが出なかった（これは失敗）")
}
line(rows() + "　← **まだ消えていない**")

print("【10】ダイアログで「キャンセル」")
line(cancelDelete())
line(rows())

print("【11】ダイアログで「削除」")
if let d = pending {
    line(performDelete(d, cart: &cart))
    line(rows() + "　← 後ろの行が前に寄る（index がずれる）")
}

print("【12】削除ボタン（つねに確認ダイアログ・C-6 #49）")
switch remove(at: 1, cart: cart) {
case .needsConfirm(let d):
    line("needsConfirm: " + d.message + " を削除しますか")
    line(cancelDelete())
    line("キャンセル後も " + rows())
case .applied(let m):
    line("即削除された（これは失敗）: " + m)
case .rejected(let m):
    line("拒否: " + m)
}

print("【13】合計（base/2 の定義をそのまま使う）")
line("小計: " + cart.map { "\($0.name)=\($0.subtotalJpy)" }.joined(separator: " / "))
line("合計: " + String(describing: cart.totals()))