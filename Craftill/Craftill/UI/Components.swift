import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - 書式

enum Fmt {
    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func num(_ n: Int) -> String { numberFormatter.string(from: NSNumber(value: n)) ?? String(n) }
    static func yen(_ n: Int) -> String { num(n) + "円" }
    static func sats(_ n: Int) -> String { num(n) + "sats" }

    static func time(_ d: Date?) -> String {
        guard let d else { return "―" }
        return timeFormatter.string(from: d)
    }

    static func dateTime(_ d: Date?) -> String {
        guard let d else { return "―" }
        return dateTimeFormatter.string(from: d)
    }
}

// MARK: - ボタンスタイル

struct AppButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        StyledLabel(configuration: configuration, primary: primary)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        @Environment(\.isEnabled) private var isEnabled

        private var fill: Color {
            if !isEnabled { return Color.gray.opacity(0.15) }
            return primary ? Color.black : Color.white
        }

        private var textColor: Color {
            if !isEnabled { return Color.gray }
            return primary ? Color.white : Color.black
        }

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: primary ? .bold : .regular))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(fill))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isEnabled ? Color.black.opacity(0.7) : Color.gray.opacity(0.6),
                                style: StrokeStyle(lineWidth: 1, dash: isEnabled ? [] : [4]))
                )
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var app: AppButtonStyle { AppButtonStyle(primary: false) }
    static var appPrimary: AppButtonStyle { AppButtonStyle(primary: true) }
}

// MARK: - 汎用部品

struct Panel<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.4)))
    }
}

struct InfoBox: View {
    let text: String
    var size: CGFloat = 20
    var bold = true
    var tint: Color? = nil

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: bold ? .bold : .regular))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill((tint ?? Color.gray).opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5)))
    }
}

struct PlaceholderImage: View {
    var label = "画像"

    var body: some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.25))
            Text(label).font(.caption).foregroundColor(.secondary)
        }
    }
}

/// 同梱画像（`image_ref`）を表示する。ファイルが無い場合はプレースホルダー。
/// 画像ファイル名は商品IDと同一（例: `KH-008.jpg`。A-17）。
struct ProductImageView: View {
    let imageRef: String?
    var placeholder = "画像"

    var body: some View {
        ZStack {
            if let image = Self.bundledImage(imageRef) {
                image.resizable().scaledToFill()
            } else {
                PlaceholderImage(label: placeholder)
            }
        }
        .clipped()
    }

    private static func bundledImage(_ ref: String?) -> Image? {
        guard let ref, !ref.isEmpty,
              let url = Bundle.main.url(forResource: ref, withExtension: nil) else {
            return nil
        }
        #if canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: image)
        #elseif canImport(UIKit)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: image)
        #else
        return nil
        #endif
    }
}

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var required = false
    var disabled = false
    var placeholder = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label + (required ? " *" : "")).font(.caption).foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .disabled(disabled)
        }
    }
}

struct TableRowView: View {
    let cells: [String]
    let widths: [CGFloat]
    var header = false

    var body: some View {
        TableRowLayout(weights: widths) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                Text(c)
                    .font(.system(size: 12, weight: header ? .bold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .overlay(Rectangle().stroke(Color.gray.opacity(0.3)))
            }
        }
        .background(header ? Color.gray.opacity(0.15) : Color.clear)
    }
}

/// 列幅を「比率」として扱う。画面幅が変わっても表がはみ出さない。
private struct TableRowLayout: Layout {
    let weights: [CGFloat]
    var spacing: CGFloat = 0

    private func columnWidths(total: CGFloat) -> [CGFloat] {
        let valid = weights.isEmpty ? [1] : weights.map { max(0.01, $0) }
        let sum = valid.reduce(0, +)
        return valid.map { total * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let widths = columnWidths(total: width)
        var height: CGFloat = 0
        for (i, subview) in subviews.enumerated() {
            let w = widths.indices.contains(i) ? widths[i] : 0
            height = max(height, subview.sizeThatFits(ProposedViewSize(width: w, height: nil)).height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = columnWidths(total: bounds.width)
        var x = bounds.minX
        for (i, subview) in subviews.enumerated() {
            let w = widths.indices.contains(i) ? widths[i] : 0
            subview.place(at: CGPoint(x: x, y: bounds.minY),
                          proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}

struct TopBar<Trailing: View>: View {
    let title: String
    let state: String?
    let trailing: Trailing

    init(_ title: String, state: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.state = state
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(state == nil ? title : "\(title)　｜　状態: \(state ?? "")")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.15))
    }
}

extension TopBar where Trailing == EmptyView {
    init(_ title: String, state: String? = nil) {
        self.init(title, state: state) { EmptyView() }
    }
}

struct MessageBar: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        if !vm.message.isEmpty {
            HStack {
                Text(vm.message).font(.callout).lineLimit(3)
                Spacer(minLength: 8)
                Button("閉じる") { vm.message = "" }
                    .buttonStyle(.app)
                    .frame(maxWidth: 90)
            }
            .padding(8)
            .background(Color.yellow.opacity(0.25))
        }
    }
}

struct KeypadView: View {
    let onKey: (String) -> Void
    private let keys = ["7", "8", "9", "4", "5", "6", "1", "2", "3", "0", "00", "C"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(keys, id: \.self) { k in
                Button(k) { onKey(k) }
                    .buttonStyle(.app)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .frame(maxWidth: 360)
    }
}

/// 横幅が足りない機種（小さいMac・ウィンドウ縮小）では縦に積む。
struct AdaptiveHStack<First: View, Second: View>: View {
    var breakpoint: CGFloat = 900
    var spacing: CGFloat = 12
    private let first: First
    private let second: Second

    init(breakpoint: CGFloat = 900, spacing: CGFloat = 12,
         @ViewBuilder first: () -> First, @ViewBuilder second: () -> Second) {
        self.breakpoint = breakpoint
        self.spacing = spacing
        self.first = first()
        self.second = second()
    }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= breakpoint {
                HStack(alignment: .top, spacing: spacing) {
                    first.frame(maxWidth: .infinity, maxHeight: .infinity)
                    second.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: spacing) {
                    first.frame(maxWidth: .infinity, maxHeight: .infinity)
                    second.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct AdminShell<Content: View>: View {
    @EnvironmentObject var vm: AppViewModel
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title, state: vm.saleState.label) {
                Button("メニューへ") { vm.exitAdmin() }
                    .buttonStyle(.app)
                    .frame(maxWidth: 140)
            }
            ScrollView {
                content
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            MessageBar()
        }
    }
}

// MARK: - 商品タイル・カート行

struct ProductTile: View {
    @EnvironmentObject var vm: AppViewModel
    let product: Product

    var body: some View {
        let sold = isSoldOut(product, in: vm.inventory, types: vm.types)
        let added = vm.isUniqueInCart(product)
        let satsText = product.priceSats.map { Fmt.sats($0) } ?? "―"
        Button { vm.addToCart(product) } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    if product.imageRef != nil {
                        ProductImageView(imageRef: product.imageRef)
                    } else {
                        Text("画像なし\n" + (product.attrText(in: vm.types) ?? ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(style: StrokeStyle(lineWidth: 1, dash: [3])).foregroundColor(.gray))
                    }
                    if sold {
                        Rectangle().fill(Color.black.opacity(0.6))
                        Text("SOLD OUT").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    }
                    if added {
                        Text("追加済み")
                            .font(.caption2)
                            .padding(4)
                            .background(Color.black)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(1.5, contentMode: .fit)
                .frame(maxHeight: 140)
                Text(product.id + "\n" + product.name)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(Fmt.yen(product.priceJpy)) / \(satsText)")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.6)))
            .foregroundColor(.black)
        }
        .buttonStyle(.plain)
    }
}

struct CartRowView: View {
    @EnvironmentObject var vm: AppViewModel
    let index: Int
    let line: CartLine

    private var priceText: String {
        let s = line.unitPriceSats.map { Fmt.sats($0) } ?? "―（現金）"
        return "\(Fmt.yen(line.unitPriceJpy))／\(s)"
    }

    var body: some View {
        let fixedQty = stockMode(of: line, in: vm.types) == .unique
        let imageRef = line.isAdhoc ? nil : vm.inventory.first(where: { $0.id == line.id })?.imageRef
        HStack(spacing: 8) {
            ProductImageView(imageRef: imageRef, placeholder: line.isAdhoc ? "野良" : "画像")
                .frame(minWidth: 36, idealWidth: 52, maxWidth: 52, minHeight: 36, idealHeight: 52, maxHeight: 52)
                .cornerRadius(4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(line.id).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    if line.isAdhoc {
                        Text("野良")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .background(Color.orange.opacity(0.3))
                            .cornerRadius(3)
                    }
                }
                Text(line.name).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(priceText).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
                if line.isAdhoc {
                    Text("グループ: \(vm.groupLabel(line.groupId))").font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("−") { vm.decreaseQty(index) }
                .buttonStyle(.app).frame(minWidth: 32, maxWidth: 44).disabled(fixedQty)
            Text("\(line.qty)").frame(minWidth: 24)
            Button("＋") { vm.increaseQty(index) }
                .buttonStyle(.app).frame(minWidth: 32, maxWidth: 44).disabled(fixedQty)
            Text(Fmt.yen(line.subtotalJpy))
                .font(.system(size: 13))
                .frame(minWidth: 60, maxWidth: 90, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Button("削除") { vm.removeLine(index) }
                .buttonStyle(.app).frame(minWidth: 52, maxWidth: 70)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.4)))
    }
}

// MARK: - オーバーレイ（ダイアログ・PIN）

struct DialogOverlay: View {
    @EnvironmentObject var vm: AppViewModel
    let dialog: Dialog

    private var needsPin: Bool {
        switch dialog {
        case .suspendSatsConfirmed, .voidSale: return true
        default: return false
        }
    }

    private var isMessage: Bool {
        if case .message = dialog { return true }
        return false
    }

    private var title: String {
        switch dialog {
        case .deleteLine: return "行の削除"
        case .zeroQty: return "数量が0になります"
        case .suspend: return "会計の中断"
        case .suspendSatsConfirmed: return "会計の中断（sats確認済み・PIN）"
        case .satsConfirm: return "WoSで入金を確認済みですか?"
        case .voidSale: return "販売取消（PIN）"
        case .message: return "お知らせ"
        }
    }

    private var bodyText: String {
        switch dialog {
        case .deleteLine(let d): return "\(d.message)\n削除しますか?"
        case .zeroQty(let d): return "\(d.message)\n行を削除しますか?"
        case .suspend:
            return "カート \(vm.cart.count)行 / 合計 \(Fmt.yen(vm.totals.cash))\nカートの内容は破棄されます。記録は残りません。"
        case .suspendSatsConfirmed:
            return "sats確認済みの会計です。\n中断の記録が残ります。在庫は変化しません。\n返金はWoSで手動対応。"
        case .satsConfirm:
            let t = vm.totals
            var s = "請求sats額 \(Fmt.sats(t.sats))"
            if t.cashForSats > 0 { s += "\n現金分 \(Fmt.yen(t.cashForSats))（承認後に受け取り）" }
            return s
        case .voidSale(let id):
            guard let sale = vm.sales.first(where: { $0.id == id }) else { return id }
            let jpy = sale.totalJpy.map { Fmt.yen($0) } ?? "―"
            let sats = sale.totalSats.map { Fmt.sats($0) } ?? "―"
            return "販売ID \(id)\n方法 \(sale.method.label)\nsats \(sats) / 現金 \(jpy)"
        case .message(let m): return m
        }
    }

    private var okTitle: String {
        switch dialog {
        case .deleteLine, .zeroQty: return "削除"
        case .suspend: return "中断"
        case .suspendSatsConfirmed: return "PIN確認して中断"
        case .satsConfirm: return "確認済み"
        case .voidSale: return "取消実行"
        case .message: return "OK"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                Text(bodyText)
                if needsPin {
                    SecureField("PIN", text: $vm.dialogPin).textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 10) {
                    if !isMessage {
                        Button("キャンセル") { vm.closeDialog() }.buttonStyle(.app)
                    }
                    Button(okTitle) { vm.confirmDialog(dialog) }.buttonStyle(.appPrimary)
                }
            }
            .padding(20)
            .frame(minWidth: 280, idealWidth: 440, maxWidth: 560)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5)))
        }
    }
}

struct PinOverlay: View {
    @EnvironmentObject var vm: AppViewModel
    let prompt: PinPrompt
    @State private var entered = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(prompt.title).font(.headline)
                Text(entered.isEmpty ? "PINを入力" : String(repeating: "● ", count: entered.count))
                    .font(.system(size: 24))
                    .frame(minHeight: 40)
                KeypadView { k in
                    if k == "C" {
                        entered = ""
                    } else if entered.count + k.count <= 8 {
                        entered += k
                    }
                }
                HStack(spacing: 10) {
                    Button("キャンセル") { vm.pinPrompt = nil }.buttonStyle(.app)
                    Button("確定") {
                        vm.submitPin(entered)
                        entered = ""
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(entered.isEmpty)
                }
                .frame(maxWidth: 360)
            }
            .padding(20)
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)
            .background(RoundedRectangle(cornerRadius: 10).fill(.background))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.5)))
        }
    }
}