// ── 種類（在庫の扱い）────────────────────
enum StockMode {
    case counted   // 数量管理型（ステッカー）
    case unique    // 一点物型（キーホルダー）
    case none      // 在庫管理なし型（今回は未使用）
}

// ── 商品1つ分（テーブル products 相当）──
struct Product {
    let id: String
    let typeId: String
    let name: String
    let priceJpy: Int
    let priceSats: Int?
    var stock: Int?         // 在庫（none は nil）
    let stockMode: StockMode
}

// ── カートの行 ──
struct CartLine {
    let product: Product    // カートに入れた時点の商品情報（在庫数は古い可能性がある）
    var qty: Int
}

// ── 在庫変動ログ1件（テーブル stock_movements 相当）──
struct StockMovement {
    let productId: String
    let delta: Int          // 増減数（-/＋）
    let reason: String      // initial / sale / void / adjust
    let saleId: String?     // 販売に関係するときだけ入る
}

// ── サンプル商品（../開発/6_データベース.md）──
let products: [Product] = [
    Product(id: "ST-001", typeId: "sticker",   name: "ステッカー まる",     priceJpy: 300, priceSats: 500,  stock: 10, stockMode: .counted),
    Product(id: "ST-002", typeId: "sticker",   name: "ステッカー さんかく", priceJpy: 300, priceSats: 500,  stock: 10, stockMode: .counted),
    Product(id: "ST-003", typeId: "sticker",   name: "ステッカー しかく",   priceJpy: 300, priceSats: nil,  stock: 10, stockMode: .counted),
    Product(id: "KH-001", typeId: "keyholder", name: "キーホルダー 01", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-002", typeId: "keyholder", name: "キーホルダー 02", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-003", typeId: "keyholder", name: "キーホルダー 03", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-004", typeId: "keyholder", name: "キーホルダー 04", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-005", typeId: "keyholder", name: "キーホルダー 05", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-006", typeId: "keyholder", name: "キーホルダー 06", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-007", typeId: "keyholder", name: "キーホルダー 07", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-008", typeId: "keyholder", name: "キーホルダー 08", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-009", typeId: "keyholder", name: "キーホルダー 09", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-010", typeId: "keyholder", name: "キーホルダー 10", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-011", typeId: "keyholder", name: "キーホルダー 11", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-012", typeId: "keyholder", name: "キーホルダー 12", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-013", typeId: "keyholder", name: "キーホルダー 13", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-014", typeId: "keyholder", name: "キーホルダー 14", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-015", typeId: "keyholder", name: "キーホルダー 15", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-016", typeId: "keyholder", name: "キーホルダー 16", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-017", typeId: "keyholder", name: "キーホルダー 17", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-018", typeId: "keyholder", name: "キーホルダー 18", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-019", typeId: "keyholder", name: "キーホルダー 19", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
    Product(id: "KH-020", typeId: "keyholder", name: "キーホルダー 20", priceJpy: 800, priceSats: 1200, stock: 1, stockMode: .unique),
]

// サンプルにあるので必ず見つかる前提の小さな補助
func product(_ id: String) -> Product { products.first { $0.id == id }! }


//----------------
//1
//カート内の全ての商品が本当に購入可能か？
///在庫不足があれば理由[文字列]を返す。問題なければ空[]
func checkStock(_ cart: [CartLine], inventory: [Product]) -> [String]{
   var problems: [String] = []  

   //カートのなかで、管理ありの行だけみる(野良除外)
   for line in cart where line.product.stockMode != .none {
    
    guard let current = inventory.first(where: {$0.id == line.product.id}),
        let stock = current.stock else {continue}

    if line.qty > stock {
        problems.append("在庫不足: \(current.name) (在庫: \(stock) , 必要: \(line.qty))")
    }
   }
   return problems
}


//試す
func run(_ label: String, _ cart: [CartLine], inventory: [Product] = products) {
    let problems = checkStock(cart, inventory: inventory)
    print("[\(label)]")
    print(problems.isEmpty ? "  購入可能" : problems.map { "  " + $0 }.joined(separator: "\n"))
}

// 1. 正常
run("1 正常", [
    CartLine(product: product("ST-001"), qty: 2),
    CartLine(product: product("KH-001"), qty: 1),
])

// 2. ステッカー在庫超過（在庫10に対して11）
run("2 数量超過", [
    CartLine(product: product("ST-001"), qty: 11),
])

// 3. 在庫ちょうど（境界値）
run("3 在庫ちょうど", [
    CartLine(product: product("ST-001"), qty: 10),
])

// 4. 一点物を2個
run("4 一点物2個", [
    CartLine(product: product("KH-001"), qty: 2),
])

// 5. 複数行で同時に不足
run("5 複数不足", [
    CartLine(product: product("ST-002"), qty: 11),
    CartLine(product: product("KH-003"), qty: 2),
    CartLine(product: product("ST-003"), qty: 1),   // これは問題なし
])

// 6. 空カート
run("6 空カート", [])

// 7. カート投入後に在庫が減った場合（cart側のstockは古いまま）
var changed = products
if let i = changed.firstIndex(where: { $0.id == "ST-001" }) {
    changed[i].stock = 1
}
run("7 在庫変動後", [
    CartLine(product: product("ST-001"), qty: 2),   // product.stock は10のまま
], inventory: changed)

// 8. inventory に存在しない商品
let ghost = Product(id: "XX-999", typeId: "sticker", name: "存在しない商品",
                    priceJpy: 100, priceSats: nil, stock: 5, stockMode: .counted)
run("8 在庫表に無い商品", [
    CartLine(product: ghost, qty: 99),
])

// 9. 在庫管理なし型（.none）
let noStock = Product(id: "FR-001", typeId: "free", name: "在庫管理なし商品",
                      priceJpy: 100, priceSats: nil, stock: nil, stockMode: .none)
run("9 在庫管理なし", [
    CartLine(product: noStock, qty: 100),
], inventory: products + [noStock])

//----------------
//2
//検証がすべて通ったときだけ、まとめて反映する。
//inout で在庫表と、ログをかきかえる
enum CompleteResult{
    case success(lines: [String])
    case failure([String])
}

func completeSale(saleId: String, cart: [CartLine], inventory: inout [Product], movements: inout [StockMovement]) -> CompleteResult {

    //在庫検証
    let problems = checkStock(cart, inventory:inventory)
    if !problems.isEmpty{
        return .failure(problems)

    }   

    //
    var memo: [String] = []
    for line in cart {
        let p = line.product

        guard p.stockMode != .none, 
            let i = inventory.firstIndex(where: { $0.id == p.id}),
            let current = inventory[i].stock else {continue}

            let after = current - line.qty

            inventory[i].stock = after
            memo.append("\(p.name): 在庫 \(current) → \(after)")
            movements.append(StockMovement(productId: p.id, delta: -line.qty, reason: "sale", saleId: saleId))

    } 
    return .success(lines: memo)
}


//-----------------------
//試す
//a
var inventory = products
var movements: [StockMovement] = []

let cart = [
    CartLine(product: product("ST-001"), qty:2)
    ,CartLine(product: product("KH-001"), qty:1
    )
]

switch completeSale(saleId: "S-001", cart : cart, inventory: &inventory, movements: &movements){
    case .success(let lines):
        print("完了")
        lines.forEach{print(" \($0)")}
    case .failure(let reasons):
        reasons.forEach {print("失敗: \($0)")}
}
print("------a")
print("変動ログ:" , movements.map{"\($0.productId) \($0.delta)"})

//b 
var inventoryB = products + [noStock]
var movementsB: [StockMovement] = []

let cartB = [
    CartLine(product: product("ST-003"), qty:1),
    CartLine(product: noStock, qty:100),
    CartLine(product: ghost, qty:5)
]

switch completeSale(saleId: "S-004",cart: cartB, inventory: &inventoryB, movements: &movementsB){
    case .success(let lines):
        print("完了")
        lines.forEach {print(" \($0)")}
    case .failure(let reasons):
        reasons.forEach {print("失敗: \($0)")}
}
print("------b")
print("変動ログ: ",movementsB.map{"\($0.productId) \($0.delta)"})
print("FR-001 の在庫: ", inventoryB.first{$0.id == "FR-001"}!.stock as Any)