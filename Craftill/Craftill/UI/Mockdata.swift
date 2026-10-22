import Foundation

/// 画面確認用の仮データ。ロジック実装後は永続化層からの読み込みに置き換える。
enum MockData {
    static let groups: [ProductGroup] = [
        ProductGroup(groupId: "mono", label: "もの製品"),
        ProductGroup(groupId: "roku", label: "ロクヨウ製品"),
        ProductGroup(groupId: "tmp", label: "臨時")
    ]

    static let types: [ProductType] = [
        ProductType(typeId: "mono_kh", name: "ものキーホルダー", idPrefix: "MK", idDigits: 3, stockMode: .counted,
                    attrLabel1: "色", attrLabel2: "模様", groupId: "mono", nextNo: 10),
        ProductType(typeId: "mono_st", name: "ものステッカー", idPrefix: "MS", idDigits: 3, stockMode: .counted,
                    attrLabel1: "サイズ", groupId: "mono", nextNo: 4),
        ProductType(typeId: "roku_kh", name: "ロクヨウ一点物", idPrefix: "RK", idDigits: 3, stockMode: .unique,
                    attrLabel1: "素材", groupId: "roku", nextNo: 4),
        ProductType(typeId: "svc", name: "サービス", idPrefix: "SV", idDigits: 2, stockMode: .none, nextNo: 2)
    ]

    private static func item(_ id: String, _ typeId: String, _ name: String, _ jpy: Int, _ sats: Int?, _ stock: Int?,
                             _ a1: String? = nil, _ a2: String? = nil, image: Bool = true, pub: Bool = true) -> Product {
        Product(id: id, typeId: typeId, name: name, priceJpy: jpy, priceSats: sats, stock: stock,
                attr1: a1, attr2: a2, imageRef: image ? "\(id).jpg" : nil, isPublic: pub)
    }

    static let products: [Product] = [
        item("MK-001", "mono_kh", "キーホルダー 赤", 500, 300, 12, "赤", "○"),
        item("MK-002", "mono_kh", "キーホルダー 青", 500, 300, 8, "青", "○"),
        item("MK-003", "mono_kh", "キーホルダー 緑", 500, 300, 0, "緑", "○"),
        item("MK-004", "mono_kh", "キーホルダー 黄", 500, 300, 5, "黄", "△"),
        item("MK-005", "mono_kh", "キーホルダー 白", 500, 300, 20, "白", "△"),
        item("MK-006", "mono_kh", "キーホルダー 黒", 500, 300, 3, "黒", "□"),
        item("MK-007", "mono_kh", "キーホルダー 桃", 500, 300, 7, "桃", "□"),
        item("MK-008", "mono_kh", "キーホルダー 紫", 500, 300, 10, "紫", "○"),
        item("MK-009", "mono_kh", "当日追加 キーホルダー", 500, nil, 5, "橙", "○", image: false, pub: false),
        item("MS-001", "mono_st", "ステッカー 小", 300, 150, 30, "小"),
        item("MS-002", "mono_st", "ステッカー 大", 500, 300, 15, "大"),
        item("MS-003", "mono_st", "ステッカーセット", 800, nil, 4, "セット"),
        item("RK-001", "roku_kh", "一点物 銀", 1200, 800, 1, "銀"),
        item("RK-002", "roku_kh", "一点物 木", 1500, 1000, 0, "木"),
        item("RK-003", "roku_kh", "一点物 革", 2000, 1300, 1, "革"),
        item("SV-01", "svc", "似顔絵", 1000, nil, nil)
    ]
}