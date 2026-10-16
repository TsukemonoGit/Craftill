//----------  5
import Foundation

//----------  1
//------------①
// 変数と定数
let shopName = "ステッカー屋"
var count = 0
count = count + 1
count += 1

let priceJpy: Int = 300
let name:String = "ステッカー"

print(shopName, count , priceJpy, name)
print("\(name) は\(priceJpy)")

//------------②
// if
let stock = 0

if stock > 0 {
    print("かえる")
}else{
    print("かえない")
}

//------------③
// 配列とfor
let prices = [300,300,800]

var sum = 0
for p in prices {
    sum += p
}
print(sum)
print(prices.count)

//------------④
//関数
func addTax(_ price: Int ) -> Int {
    return price * 110/100
}
print(addTax(300))
print(addTax(_:300))

//------------⑤
//構造体
struct Item {
    let name:String
    let priceJpy:Int
}
let a = Item(name:"ステッカー",priceJpy: 300)
print(a.name,a.priceJpy)

//------------⑥
// 列挙型 (enumerated type)
enum Pay {
    case cash
    case lightning
}
let pay = Pay.cash

switch pay{
    case .cash: print("gennkinn")
    case .lightning : print("lightning")
}
print(Pay.lightning)

//----------⑦
//オプショナル ( nilかもしれない値)
let satsPrice : Int? = nil

if let s = satsPrice{
    print("\(s) sats")
}else{
    print("さっつなし")
}

let shown = satsPrice ?? 0
print(shown)

//----------  2

struct Product {
    let id:String
    let name:String
    let priceJpy: Int
    let priceSats: Int?
    var stock: Int?
}

enum StockMode{
    case counted//数量管理がた
    case unique//いってんもの
    case none //数量管理外
}

let sticker = Product(id: "ST-001",name:"ステッカー",priceJpy:300,priceSats:500,stock:10)

print(sticker.id)
print(sticker.priceSats ?? 0)
if let sats = sticker.priceSats{
    print(sats)
}

var item = sticker
if let s = item.stock {
    item.stock = s - 1
}

print(item.stock)

let mode = StockMode.unique
switch mode{
    case .counted: print("数量管理")
    case .unique: print("いてんもの")
    case .none : print("none")
}


//----------  3
let products: [Product] = [
    Product(id: "ST-001", name: "ステッカー まる",   priceJpy: 300, priceSats: 500,  stock: 10),
    Product(id: "ST-003", name: "ステッカー しかく", priceJpy: 300, priceSats: nil,  stock: 10),
    Product(id: "KH-001", name: "キーホルダー 01",   priceJpy: 800, priceSats: 1200, stock: 1),
    Product(id: "KH-008", name: "キーホルダー 08",   priceJpy: 800, priceSats: 1200, stock: 1),
]

print(products.count)

for p in products{
    print(p.id,p.name,p.priceJpy)
}

//----------  4

func totals(_ items:[Product]) -> (sats:Int, jpyForSats:Int,cashJpy:Int){
    var sats = 0
    var jpyForSats = 0
    var cashJpy = 0
    for p in items {
        if let s = p.priceSats {
            sats += s
        }else{
            jpyForSats += p.priceJpy
        }
        cashJpy += p.priceJpy

    }
    return (sats,jpyForSats,cashJpy)

}

let t = totals([products[0],products[1]])//0,1を購入
print("sats払い:\(t.sats)sats + \(t.jpyForSats)円")
print("円払い:\(t.cashJpy)円")

//----------  5
func normalizeID(_ raw: String) -> String {
    let upper: String = raw.uppercased()
    let letters: String = upper.filter {$0.isLetter}
    let digits: String = upper.filter{$0.isNumber}
    let n: Int = Int(digits) ?? 0
    return letters + "-" + String(format: "%03d", n)
}


print(normalizeID("kh08"))
print(normalizeID("KH-020"))
print(normalizeID("st 1"))
