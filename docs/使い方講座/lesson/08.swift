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
//減らしてよいか？
///在庫不足があれば理由(文字列)を返す。問題なければnil
func checkStock(_ cart: [CartLine], inventory: [Product]) -? String? {
    //在庫管理アリの行を順に見る
    for line in cart where line.product.stockMode != .nome {
        let id = line.product.id

        //野良は対象外(nil)
        guard let current = inventory.first(where: $0.id  == id }),

    }
}