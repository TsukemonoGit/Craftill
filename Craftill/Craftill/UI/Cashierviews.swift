import SwiftUI

// MARK: - レジ画面（待機中・スキャン中）

/// 商品リストの各見出しがスクロール領域の上端からどれだけ離れているか。
/// いちばん上にある種類をタブの選択状態に反映する（スクロールスパイ）。
private struct ProductSectionOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct RegisterView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact
    @State private var manualID = ""
    @State private var showScanner = false
    /// タブを押したときだけ商品リストをスクロールする。スクロール中の検知とは分ける。
    @State private var scrollRequest: String? = nil
    /// 商品リストとカートの表示比率（0.5 = 50:50）。横並び時は幅、縦積み時は高さ。
    /// 仕切りをドラッグした結果を保存する。
    @AppStorage("registerSplitRatio") private var registerSplitRatio: Double = 0.5

    private var splitRatio: Binding<CGFloat> {
        Binding(
            get: { CGFloat(registerSplitRatio) },
            set: { registerSplitRatio = Double($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ", state: compact ? nil : vm.saleState.label) {
                Text(vm.isOnline ? "通信あり" : "通信なし")
                    .font(.caption)
                    .foregroundColor(vm.isOnline ? .secondary : .orange)
                Button("メニュー") { vm.openMenu() }
                    .buttonStyle(.app)
                    .frame(maxWidth: compact ? 110 : 160)
                    .disabled(vm.saleState != .idle)
            }
            AdaptiveHStack(breakpoint: 900, spacing: 10, ratio: splitRatio) {
                productPanel
            } second: {
                cartPanel
            }
            .padding(10)
            MessageBar()
        }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet().environmentObject(vm)
        }
    }

    private var productPanel: some View {
        VStack(spacing: 8) {
            typeTabBar
            productList
            if compact {
                VStack(spacing: 8) {
                    TextField("商品ID手動入力（例: mk8）", text: $manualID)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submitID() }
                    HStack(spacing: 8) {
                        Button("カメラ読み取り") { showScanner = true }
                            .buttonStyle(.app)
                        Button("追加") { submitID() }
                            .buttonStyle(.app)
                    }
                    Button("野良追加") { vm.showAdhoc = true }
                        .buttonStyle(.app)
                    suggestionRow
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Button("カメラ読み取り") { showScanner = true }
                            .buttonStyle(.app)
                            .frame(minWidth: 120, maxWidth: 180)
                        TextField("商品ID手動入力（例: mk8）", text: $manualID)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 120)
                            .onSubmit { submitID() }
                        Button("追加") { submitID() }
                            .buttonStyle(.app)
                            .frame(minWidth: 64, maxWidth: 90)
                        Button("野良追加") { vm.showAdhoc = true }
                            .buttonStyle(.app)
                            .frame(minWidth: 88, maxWidth: 130)
                    }
                    suggestionRow
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
    }

    // MARK: 種類タブ（スクロールスパイ）

    private var typeTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.types) { t in
                        Button(vm.tabLabel(t)) {
                            vm.selectedTypeId = t.typeId
                            scrollRequest = t.typeId
                        }
                        .buttonStyle(AppButtonStyle(primary: t.typeId == vm.selectedTypeId))
                        .frame(minWidth: 120, maxWidth: 240)
                        .id(t.typeId)
                    }
                }
            }
            .frame(minHeight: 40, maxHeight: 56)
            .onChange(of: vm.selectedTypeId) { _, newValue in
                guard vm.types.contains(where: { $0.typeId == newValue }) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    // MARK: 商品リスト（種類ごとのセクション）

    private var productList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if vm.types.isEmpty {
                        Text("商品の種類がありません。メニューの「編集」で登録してください。")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                    }
                    ForEach(vm.types) { t in
                        productSection(t)
                            .id(t.typeId)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 8)
            }
            .coordinateSpace(name: "register.productScroll")
            .onPreferenceChange(ProductSectionOffsetKey.self) { offsets in
                updateActiveType(from: offsets)
            }
            .onChange(of: scrollRequest) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newValue, anchor: .top)
                }
                scrollRequest = nil
            }
        }
    }

    private func productSection(_ t: ProductType) -> some View {
        let products = vm.products(ofType: t.typeId)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.tabLabel(t)).font(.headline)
                Text("\(products.count)件")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ProductSectionOffsetKey.self,
                        value: [t.typeId: geo.frame(in: .named("register.productScroll")).minY]
                    )
                }
            )

            if products.isEmpty {
                Text("この種類の商品はありません")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 8)],
                          spacing: 8) {
                    ForEach(products) { p in
                        ProductTile(product: p)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 上端にいちばん近い見出しの種類を、タブの選択状態に反映する。
    private func updateActiveType(from offsets: [String: CGFloat]) {
        guard !vm.types.isEmpty else { return }
        let threshold: CGFloat = 16
        let active = vm.types.last {
            (offsets[$0.typeId] ?? CGFloat.greatestFiniteMagnitude) <= threshold
        } ?? vm.types.first
        guard let active, active.typeId != vm.selectedTypeId else { return }
        vm.selectedTypeId = active.typeId
    }

    /// 入力中の在庫候補（A-2、C-6 #69）。ID・商品名の部分一致で絞る。
    private var suggestions: [Product] {
        let raw = manualID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return [] }
        let normalized = vm.normalizeID(raw)
        return Array(vm.inventory.filter {
            $0.id.contains(normalized) || $0.name.localizedCaseInsensitiveContains(raw)
        }.prefix(6))
    }

    @ViewBuilder
    private var suggestionRow: some View {
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(suggestions) { p in
                        Button("\(p.id)　\(p.name)") {
                            manualID = ""
                            vm.addToCart(p)
                        }
                        .buttonStyle(.app)
                    }
                }
            }
        }
    }

    private func submitID() {
        guard !manualID.isEmpty else { return }
        vm.addByID(manualID)
        manualID = ""
    }

    private var cartPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("カート").font(.headline)
            if vm.cart.isEmpty {
                Text("カートは空です\nQRを読み取る／商品をタップ／IDを手入力\nのいずれかで追加してください")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 72,
                           idealHeight: 160, maxHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundColor(.gray))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(vm.cart.enumerated()), id: \.element.id) { i, line in
                            CartRowView(index: i, line: line)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Panel {
                Text(vm.satsLine).font(.system(size: 16, weight: .bold))
                Text(vm.cashLine).font(.system(size: 16, weight: .bold))
            }
            HStack(spacing: 10) {
                Button("会計へ進む") { vm.proceedToPayment() }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .disabled(vm.saleState != .scanning || vm.cart.isEmpty)
                Button("会計中断") { vm.requestSuspend() }
                    .buttonStyle(.app)
                    .frame(maxWidth: 160, minHeight: 52)
                    .disabled(vm.saleState != .scanning)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
    }
}

// MARK: - 野良追加（入力 → 確認）

struct AdhocSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""
    @State private var satsText = ""
    @State private var name = ""
    @State private var groupId = ""
    @State private var qty = 1
    @State private var confirming = false

    private var priceJpy: Int? {
        guard let v = Int(priceText), v >= 0 else { return nil }
        return v
    }

    private var priceSats: Int? {
        guard let v = Int(satsText), v >= 1 else { return nil }
        return v
    }

    private var canConfirm: Bool {
        priceJpy != nil && (satsText.isEmpty || priceSats != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if confirming { confirmView } else { formView }
        }
        .padding(20)
        .frame(minWidth: 300, idealWidth: 520, maxWidth: .infinity,
               minHeight: 360, idealHeight: 560, maxHeight: .infinity)
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("野良商品を追加").font(.headline)
                    LabeledField(label: "円価格（0以上の整数）", text: $priceText, required: true, placeholder: "例: 1500／0")
                    LabeledField(label: "sats価格（未入力 = sats払いでも現金で受け取り）", text: $satsText)
                    LabeledField(label: "品名（未入力時「野良」）", text: $name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("グループ（選択のみ。新規作成不可）").font(.caption).foregroundColor(.secondary)
                        Picker("", selection: $groupId) {
                            Text("（グループなし）").tag("")
                            ForEach(vm.groups) { g in Text(g.label).tag(g.groupId) }
                        }
                        .labelsHidden()
                    }
                    HStack(spacing: 8) {
                        Text("数量").font(.caption).foregroundColor(.secondary)
                        Button("−") { qty = max(1, qty - 1) }.buttonStyle(.app)
                        TextField("数量", value: $qty, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Button("＋") { qty += 1 }.buttonStyle(.app)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button("キャンセル") { dismiss() }.buttonStyle(.app)
                Button("確認へ") { confirming = true }
                    .buttonStyle(.appPrimary)
                    .disabled(!canConfirm)
            }
        }
    }

    private var confirmView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("追加内容の確認").font(.headline)
                    InfoBox(text: Fmt.yen(priceJpy ?? 0), size: 44)
                    if priceSats == nil {
                        InfoBox(text: "sats単価なし：sats払いでも現金で受け取り", size: 14, tint: .yellow)
                    } else {
                        InfoBox(text: Fmt.sats(priceSats ?? 0), size: 22, tint: .yellow)
                    }
                    if groupId.isEmpty {
                        InfoBox(text: "グループなし", size: 14, tint: .yellow)
                    } else {
                        InfoBox(text: "グループ: \(vm.groupLabel(groupId))", size: 14)
                    }
                    Text("品名: \(name.isEmpty ? "野良" : name)　／　数量: \(qty)")
                    Text("桁の誤りはこの確認表示で検出。追加後の修正は行の削除→再追加。")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button("戻る") { confirming = false }.buttonStyle(.app)
                Button("カートに追加") {
                    vm.addAdhoc(priceJpy: priceJpy ?? 0, priceSats: priceSats, name: name,
                                groupId: groupId.isEmpty ? nil : groupId, qty: qty)
                    dismiss()
                }
                .buttonStyle(.appPrimary)
            }
        }
    }
}

// MARK: - 支払方法選択

/// 支払方法の選択カード。ホバー・押下範囲・無効時の見た目を1か所にまとめる。
private struct PaymentMethodCard<Content: View>: View {
    let tint: Color
    let enabled: Bool
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void
    private let content: Content
    @State private var hovering = false

    init(tint: Color,
         enabled: Bool = true,
         accessibilityLabel: String,
         accessibilityHint: String,
         action: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.enabled = enabled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .opacity(enabled ? 1 : 0.7)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(tint.opacity(enabled ? (hovering ? 0.17 : 0.09) : 0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(enabled ? tint.opacity(hovering ? 0.85 : 0.45)
                                        : Color.gray.opacity(0.45),
                                style: StrokeStyle(lineWidth: enabled && hovering ? 2 : 1.5,
                                                   dash: enabled ? [] : [5, 4]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(accessibilityHint)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

struct PaymentSelectView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact
    @State private var cartExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ（支払方法）", state: compact ? nil : vm.saleState.label)
            CheckoutSteps(current: .method)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            if compact {
                compactContent
            } else {
                wideContent
            }
            footerActions
            MessageBar()
        }
    }

    // MARK: レイアウト

    /// 狭い画面では、まず支払方法を選べるようにして、カート明細は折りたたむ。
    private var compactContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                selectionHeader
                cashCard
                satsCard
                if vm.canPayBySats { paymentHint }
                cartDisclosure
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var wideContent: some View {
        HStack(alignment: .top, spacing: 20) {
            cartPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    selectionHeader
                    cashCard
                    satsCard
                    if vm.canPayBySats { paymentHint }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var selectionHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("お支払い方法").font(.system(size: 20, weight: .bold))
            Text("方法を選ぶと次の画面に進みます。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var paymentHint: some View {
        Label("sats払いはWoSで請求し、入金を確認してから「済」を押します。",
              systemImage: "info.circle")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 支払方法カード

    private var cashCard: some View {
        PaymentMethodCard(
            tint: .green,
            accessibilityLabel: "現金で支払う。請求額 \(Fmt.yen(vm.totals.cash))",
            accessibilityHint: "お預かり金額の入力画面に進みます",
            action: { vm.chooseCash() }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    methodIcon("yensign.circle.fill", tint: .green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("現金").font(.system(size: 22, weight: .bold))
                        Text("お預かり金額を入力して、お釣りを計算します")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                amountLine("請求") {
                    Text(Fmt.yen(vm.totals.cash))
                        .font(.system(size: 27, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }

    private var satsCard: some View {
        PaymentMethodCard(
            tint: .orange,
            enabled: vm.canPayBySats,
            accessibilityLabel: satsAccessibilityLabel,
            accessibilityHint: vm.canPayBySats
                ? "WoSでの請求画面に進みます"
                : (vm.satsDisabledReason ?? "このカートではsats払いを選べません"),
            action: { vm.chooseSats() }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    methodIcon("bitcoinsign.circle.fill", tint: .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("sats払い").font(.system(size: 22, weight: .bold))
                            if vm.canPayBySats && vm.totals.cashForSats > 0 {
                                badge("現金併用")
                            }
                            if !vm.canPayBySats {
                                badge("利用不可", gray: true)
                            }
                        }
                        Text(satsSubtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: vm.canPayBySats ? "chevron.right" : "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                if vm.canPayBySats {
                    amountLine("請求") {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Fmt.sats(vm.totals.sats))
                                .font(.system(size: 27, weight: .bold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            if vm.totals.cashForSats > 0 {
                                Text("＋ \(Fmt.yen(vm.totals.cashForSats)) 現金")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }
                } else if let reason = vm.satsDisabledReason {
                    Divider().opacity(0.5)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text(reason)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private var satsSubtitle: String {
        guard vm.canPayBySats else { return "このカートではsats払いを選べません" }
        return vm.totals.cashForSats > 0
            ? "satsで受け取り、現金分はあとで受け取ります"
            : "WoSで請求して、satsで受け取ります"
    }

    private var satsAccessibilityLabel: String {
        guard vm.canPayBySats else {
            return "sats払い。利用できません。\(vm.satsDisabledReason ?? "")"
        }
        if vm.totals.cashForSats > 0 {
            return "sats払い。\(Fmt.sats(vm.totals.sats))と現金\(Fmt.yen(vm.totals.cashForSats))"
        }
        return "sats払い。\(Fmt.sats(vm.totals.sats))"
    }

    private func methodIcon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 23, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: 46, height: 46)
            .background(Circle().fill(tint.opacity(0.14)))
            .overlay(Circle().stroke(tint.opacity(0.35), lineWidth: 1))
    }

    private func badge(_ text: String, gray: Bool = false) -> some View {
        let tint: Color = gray ? .gray : .orange
        return Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(gray ? .secondary : .primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 0.5))
    }

    private func amountLine<Value: View>(_ label: String,
                                         @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer(minLength: 8)
            value()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: カート明細

    private var cartTotalQty: Int { vm.cart.reduce(0) { $0 + $1.qty } }

    private var cartPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("カート").font(.headline)
                Text("\(cartTotalQty)点")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
                Text("読み取り専用")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            totalsPanel
            ScrollView(showsIndicators: false) {
                cartTable
                    .padding(.bottom, 2)
            }
            notePanel
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
    }

    /// 狭い画面用。支払方法を選ぶ操作を邪魔しないよう、明細は折りたたむ。
    private var cartDisclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { cartExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: cartExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("カートの内容").font(.headline)
                    Text("\(cartTotalQty)点")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 8)
                    if !vm.checkoutNote.isEmpty {
                        Label("メモあり", systemImage: "note.text")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("カートの内容を\(cartExpanded ? "閉じる" : "開く")")
            if cartExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    cartTable
                    totalsPanel
                    notePanel
                }
                .padding(12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3)))
    }

    private var cartTable: some View {
        VStack(spacing: 0) {
            TableRowView(cells: ["商品ID", "商品名", "数量", "小計"],
                         widths: [100, 200, 60, 110], header: true)
            ForEach(vm.cart) { l in
                TableRowView(cells: [l.id, l.name, "\(l.qty)", Fmt.yen(l.subtotalJpy)],
                             widths: [100, 200, 60, 110])
            }
        }
    }

    /// 会計ごとの任意メモ。販売履歴・CSV にも残る。
    private var notePanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("会計メモ（任意）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
                Text("\(vm.checkoutNote.count) / 500")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            TextField("例: 取り置き・袋入れ・値引き理由", text: $vm.checkoutNote)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// 「現金いくら／satsいくら」を並べて、選ぶ前に金額が分かるようにする。
    private var totalsPanel: some View {
        Panel(title: "お支払い合計") {
            VStack(alignment: .leading, spacing: 8) {
                totalRow("現金", Fmt.yen(vm.totals.cash),
                         tint: .green, icon: "yensign.circle")
                totalRow("sats払い", satsPayText,
                         tint: .orange, icon: "bitcoinsign.circle")
            }
        }
    }

    private var satsPayText: String {
        guard vm.canPayBySats else { return "選択できません" }
        if vm.totals.cashForSats == 0 { return Fmt.sats(vm.totals.sats) }
        return "\(Fmt.sats(vm.totals.sats)) ＋ \(Fmt.yen(vm.totals.cashForSats))"
    }

    private func totalRow(_ label: String, _ value: String,
                          tint: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .frame(width: 18)
            Text(label).foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: 戻る・中断

    private var footerActions: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if !compact {
                    Text("方法を選ぶと自動で次へ進みます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                Button("戻る（カート）") { vm.backToScan() }
                    .buttonStyle(.app)
                    .frame(maxWidth: compact ? .infinity : 170)
                Button("会計中断") { vm.requestSuspend() }
                    .buttonStyle(.app)
                    .frame(maxWidth: compact ? .infinity : 140)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.08))
        }
    }
}

// MARK: - 現金入力（現金／併用現金入力 共通）

struct CashEntryView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact
    let mixed: Bool

    var body: some View {
        VStack(spacing: 0) {
            TopBar(mixed ? "レジ（sats＋現金）" : "レジ（現金）",
                   state: compact ? nil : vm.saleState.label)
            CheckoutSteps(current: .receive)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            if compact {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        if mixed { satsConfirmedBox }
                        requestBox
                        VStack(spacing: 8) {
                            receivedBox
                            quickCashButtons
                        }
                        keypadPanel
                            .frame(maxWidth: .infinity, alignment: .center)
                        changeAndConfirm
                    }
                    .padding(14)
                }
            } else {
                AdaptiveHStack(breakpoint: 820, spacing: 28) {
                    // ウィンドウが低いときも「確定」「会計中断」へ届くように、
                    // 左列だけを独立してスクロールさせる（キーパッドは固定）。
                    ScrollView(showsIndicators: false) {
                        amountColumn
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } second: {
                    keypadPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(24)
            }
            MessageBar()
        }
    }

    /// 金額の確認と確定操作。左列の内容。
    private var amountColumn: some View {
        VStack(spacing: 12) {
            if mixed { satsConfirmedBox }
            requestBox
            VStack(spacing: 8) {
                receivedBox
                quickCashButtons
            }
            changeAndConfirm
        }
    }

    // MARK: 金額

    private var satsConfirmedBox: some View {
        VStack(spacing: 2) {
            Text("sats は受け取り済み")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(Fmt.sats(vm.totals.sats))　\(Fmt.time(vm.satsConfirmedAt)) 確認")
                .font(.system(size: 17, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.45)))
    }

    private var requestBox: some View {
        AmountBox(label: mixed ? "請求額（現金分）" : "請求額",
                  value: Fmt.yen(vm.cashDue),
                  size: compact ? 24 : 32,
                  tint: .blue,
                  horizontal: compact)
    }

    private var receivedBox: some View {
        AmountBox(label: "受取額（入力）",
                  value: Fmt.yen(vm.cashReceived),
                  size: compact ? 22 : 28,
                  horizontal: compact)
    }

    private var quickCashButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("ちょうど") { vm.acceptExactCash() }
                    .buttonStyle(.app)
                    .disabled(vm.cashReceived == vm.cashDue)
                Button("＋1,000円") { vm.addCash(1_000) }.buttonStyle(.app)
                Button("＋5,000円") { vm.addCash(5_000) }.buttonStyle(.app)
            }
            HStack(spacing: 8) {
                Button("＋10,000円") { vm.addCash(10_000) }.buttonStyle(.app)
                Button("クリア") { vm.pressKey("C") }
                    .buttonStyle(.app)
                    .disabled(vm.cashReceived == 0)
            }
        }
    }

    /// この画面でいちばん大事な「お釣り」。足りないときは不足額を出す。
    private var changeAndConfirm: some View {
        VStack(spacing: 10) {
            changeBox
            Button("確定") { vm.confirmCash() }
                .buttonStyle(.appPrimary)
                .frame(maxWidth: .infinity, minHeight: 64)
                .disabled(!vm.canConfirmCash)
            HStack(spacing: 10) {
                // sats確認後（併用）は支払方法を戻せない。現金のみのときだけ戻れる。
                if !mixed {
                    Button("戻る（支払方法）") { vm.reselectMethod() }
                        .buttonStyle(.app)
                        .frame(maxWidth: .infinity)
                }
                Button(mixed ? "会計中断（PIN必須・記録を残す）" : "会計中断") {
                    vm.requestSuspend()
                }
                .buttonStyle(.app)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var changeBox: some View {
        let enough = vm.canConfirmCash
        let tint: Color = enough ? .green : .orange
        return VStack(spacing: 2) {
            Text(enough ? "お釣り" : "不足")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(tint)
            Text(Fmt.yen(enough ? vm.change : vm.cashShortfall))
                .font(.system(size: compact ? 40 : 48, weight: .bold))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            Text(enough
                 ? (vm.change == 0 ? "ちょうどの受取額です" : "受取額 − 請求額")
                 : "受取額が請求額に届いていません")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.6), lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    private var keypadPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("受取額を入力").font(.headline)
            KeypadView(keyboard: true) { vm.pressKey($0) }
            #if os(macOS)
            Text("数字キー・Delete（クリア）でも入力できます")
                .font(.caption)
                .foregroundColor(.secondary)
            #endif
            if mixed {
                Text("sats確認後は支払方法の選び直し・キャンセルはできません。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - sats待ち

struct SatsWaitingView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact

    private var satsAmount: String { "\(Fmt.num(vm.totals.sats)) sats" }

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ（sats払い）", state: compact ? nil : vm.saleState.label)
            CheckoutSteps(current: .receive)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            ScrollView(showsIndicators: false) {
                VStack(spacing: compact ? 12 : 14) {
                    amountCard
                    if vm.totals.cashForSats > 0 { cashNotice }
                    stepsPanel
                    confirmButton
                    secondaryActions
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 16)
                .padding(.top, compact ? 14 : 20)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            MessageBar()
        }
    }

    /// 請求するsats額。コピーしてWoSへ貼り付ける。
    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundColor(.orange)
                Text("WoSで請求する額")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer(minLength: 8)
                elapsedCaption
            }
            Text(satsAmount)
                .font(.system(size: compact ? 40 : 52, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Button("sats額をコピー") { vm.copySatsAmount() }
                .buttonStyle(.app)
                .frame(maxWidth: 240)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.55), lineWidth: 1.5))
    }

    private var cashNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "banknote")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("入金確認後に、現金 \(Fmt.yen(vm.totals.cashForSats)) を受け取ります")
                    .font(.callout.weight(.semibold))
                Text("現金分はWoSの請求額に含めません。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.45)))
    }

    private var stepsPanel: some View {
        Panel(title: "手順") {
            VStack(alignment: .leading, spacing: 12) {
                stepRow(1, "WoSで \(satsAmount) の請求を作る",
                        "「sats額をコピー」で入力ミスを防げます")
                stepRow(2, "お客様がsatsで支払う", nil)
                stepRow(3, "入金を確認して「入金を確認した」を押す",
                        vm.totals.cashForSats > 0
                        ? "このあと現金分 \(Fmt.yen(vm.totals.cashForSats)) を受け取ります"
                        : nil)
            }
        }
    }

    private func stepRow(_ number: Int, _ title: String, _ note: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.black))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                if let note {
                    Text(note).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var confirmButton: some View {
        Button { vm.askSatsConfirm() } label: {
            VStack(spacing: 3) {
                Text("入金を確認した（済）")
                    .font(.system(size: 20, weight: .bold))
                Text("WoSで入金を確認してから押してください")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(.appPrimary)
    }

    private var secondaryActions: some View {
        VStack(spacing: 10) {
            if compact {
                VStack(spacing: 10) {
                    Button("戻る（支払方法）") { vm.reselectMethod() }.buttonStyle(.app)
                    Button("キャンセル（確認あり）") { vm.requestSuspend() }.buttonStyle(.app)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 14) {
                    Button("戻る（支払方法）") { vm.reselectMethod() }.buttonStyle(.app)
                    Button("キャンセル（確認あり）") { vm.requestSuspend() }.buttonStyle(.app)
                }
                .frame(maxWidth: 520)
            }
            Text("入金確認の前だけ、支払方法へ戻る・キャンセルができます。戻ってもカートは残ります。")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var elapsedCaption: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = max(0, Int(ctx.date.timeIntervalSince(vm.satsStartedAt)))
            Text("経過 \(String(format: "%02d:%02d", s / 60, s % 60))")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - 完了

struct DoneView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ（完了）", state: compact ? nil : vm.saleState.label)
            CheckoutSteps(current: .done)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.green)
                        Text("会計完了")
                            .font(.system(size: 28, weight: .bold))
                    }
                    if let d = vm.done {
                        if let change = d.change {
                            changeCard(change)
                        }
                        detailPanel(d)
                    }
                    Button("次の会計へ") { vm.nextSale() }
                        .buttonStyle(.appPrimary)
                        .frame(maxWidth: 600, minHeight: 64)
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            MessageBar()
        }
    }

    /// 完了後にいちばん確認したい「お釣り」を大きく出す。
    private func changeCard(_ change: Int) -> some View {
        VStack(spacing: 4) {
            Text("お釣り")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.green)
            Text(Fmt.yen(change))
                .font(.system(size: compact ? 44 : 56, weight: .bold))
                .foregroundColor(.green)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
            Text(change == 0 ? "お釣りはありません" : "お客様にお渡しください")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.5), lineWidth: 2))
        .accessibilityElement(children: .combine)
    }

    private func detailPanel(_ d: DoneInfo) -> some View {
        VStack(spacing: 0) {
            detailRow("販売ID", d.saleId)
            Divider()
            detailRow("支払方法", d.method.label)
            if let totalSats = d.totalSats {
                Divider()
                detailRow("請求sats額", Fmt.sats(totalSats))
            }
            if let cashPart = d.cashPart {
                Divider()
                detailRow("現金（請求）", Fmt.yen(cashPart))
            }
            if let received = d.received {
                Divider()
                detailRow("受取額", Fmt.yen(received))
            }
            if let note = d.note, !note.isEmpty {
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    Text("メモ").foregroundColor(.secondary)
                    Spacer(minLength: 12)
                    Text(note)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.4)))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 8)
    }
}
