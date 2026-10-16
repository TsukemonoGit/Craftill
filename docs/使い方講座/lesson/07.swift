//種類
enum StockMode{
    case counted
    case unique
    case none
}


//商品
struct Product{
    let id: String      //"KH-008"
    let typeId: String  //"keyholder"
    let name: String
    let priceJpy: Int
    let priceSats:Int?
    var stock: Int?
    let stockMode:StockMode
}


//サンプル商品
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

//カート
struct CartLine{
    let product:Product //商品
    var qty:Int         //数量
}


//追加できたのか？
enum AddResult{
    case added(Product,qty:Int)
    case failed(String)
}

func message(_ r:AddResult) -> String{
    switch r {
        case .added(let p,let qty):     return "追加: \(p.name) × \(qty)"
        case .failed(let reason):       return "エラー: \(reason)"
    }
}


func addToCart(_ product , to cart: inout [CartLine] ){
    
}