// 7-playgroundでやる

// ----------  8
import Foundation

let homeDirectory = NSHomeDirectory()
print("Home Directory: \(homeDirectory)")

struct CartLine: Codable {
    var id: String
    var name: String
    var priceJpy: Int
    var qty: Int
}

let lines = [CartLine(id: "ST-001", name: "ステッカー まる", priceJpy: 300, qty: 2)]

// 保存
let encoder = JSONEncoder()
guard let data = try? encoder.encode(lines) else {
    fatalError("エンコード失敗")
}

let userDefaults = UserDefaults.standard
userDefaults.set(data, forKey: "cart")
// 即時同期が必要な場合（通常は不要だがデバッグや直後確認に有効）
let isSynchronized = userDefaults.synchronize()
print("同期結果: \(isSynchronized)")

// 復元と確認
guard let savedData = userDefaults.data(forKey: "cart") else {
    fatalError("保存データなし")
}

do {
    let restored = try JSONDecoder().decode([CartLine].self, from: savedData)
    print("復元成功: \(restored)")
} catch {
    print("デコード失敗: \(error)")
}