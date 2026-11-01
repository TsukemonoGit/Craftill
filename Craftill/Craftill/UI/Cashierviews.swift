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
            AdaptiveHStack(breakpoint: 900, spacing: 10) {
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
                    .frame(maxWidth: .infinity, minHeight: 160)
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
        guard let v = Int(priceText), v >= 1 else { return nil }
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
                    LabeledField(label: "円価格（1以上の整数）", text: $priceText, required: true, placeholder: "例: 1500")
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

struct PaymentSelectView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ", state: compact ? nil : vm.saleState.label)
            if compact {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        cartSummary
                        paymentOptions.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(14)
                }
            } else {
                AdaptiveHStack(breakpoint: 900, spacing: 20) {
                    cartSummary
                } second: {
                    paymentOptions
                }
                .padding(20)
            }
            MessageBar()
        }
    }

    private var paymentOptions: some View {
        VStack(spacing: 14) {
            Text("支払方法を選択").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            Button { vm.chooseCash() } label: {
                VStack(spacing: 6) {
                    Text("現金").font(.system(size: 24, weight: .bold))
                    Text(Fmt.yen(vm.totals.cash)).font(.system(size: 22))
                }
                .frame(maxWidth: .infinity, minHeight: 130)
            }
            .buttonStyle(.app)
            Button { vm.chooseSats() } label: {
                VStack(spacing: 6) {
                    Text("sats払い").font(.system(size: 24, weight: .bold))
                    Text(vm.satsLine.replacingOccurrences(of: "sats払い　", with: "")).font(.system(size: 18))
                    if vm.totals.cashForSats > 0 && vm.cart.canPayBySats() {
                        Text("（\(Fmt.yen(vm.totals.cashForSats))分は現金で受け取り）").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 130)
            }
            .buttonStyle(.app)
            .disabled(!vm.canPayBySats)
            if let reason = vm.satsDisabledReason {
                Text("sats払い　選択不可: \(reason)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            HStack(spacing: 10) {
                Button("戻る") { vm.backToScan() }.buttonStyle(.app)
                Button("会計中断") { vm.requestSuspend() }.buttonStyle(.app)
            }
        }
    }

    private var cartSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("カート（読み取り専用）").font(.headline)
            TableRowView(cells: ["商品ID", "商品名", "数量", "小計"], widths: [100, 200, 60, 110], header: true)
            ForEach(vm.cart) { l in
                TableRowView(cells: [l.id, l.name, "\(l.qty)", Fmt.yen(l.subtotalJpy)], widths: [100, 200, 60, 110])
            }
            Spacer(minLength: 8)
            Panel {
                Text(vm.satsLine).font(.system(size: 16, weight: .bold))
                Text(vm.cashLine).font(.system(size: 16, weight: .bold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 現金入力（現金／併用現金入力 共通）

struct CashEntryView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact
    let mixed: Bool

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ", state: compact ? nil : vm.saleState.label)
            if compact {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        cashPanel
                        keypadPanel.frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(14)
                }
            } else {
                AdaptiveHStack(breakpoint: 820, spacing: 28) {
                    cashPanel
                } second: {
                    keypadPanel
                }
                .padding(24)
            }
            Spacer(minLength: 0)
            MessageBar()
        }
    }

    private var cashPanel: some View {
        VStack(spacing: compact ? 8 : 12) {
            if mixed {
                InfoBox(text: "sats確認済み　\(Fmt.sats(vm.totals.sats))　確認 \(Fmt.time(vm.satsConfirmedAt))",
                        size: 16, tint: .green)
            }
            AmountBox(label: mixed ? "請求額（現金分）" : "請求額",
                      value: Fmt.yen(vm.cashDue), size: 28, horizontal: compact)
            AmountBox(label: "受取額",
                      value: Fmt.yen(vm.cashReceived), size: 22, horizontal: compact)
            AmountBox(label: "お釣り",
                      value: vm.canConfirmCash ? Fmt.yen(vm.change) : "―",
                      size: 22, horizontal: compact)
            Button("確定") { vm.confirmCash() }
                .buttonStyle(.appPrimary)
                .frame(maxWidth: .infinity, minHeight: 60)
                .disabled(!vm.canConfirmCash)
            Text("受取額 < 請求額の間、確定ボタン無効").font(.caption).foregroundColor(.secondary)
            Button(mixed ? "会計中断（PIN必須・記録を残す）" : "会計中断") { vm.requestSuspend() }
                .buttonStyle(.app)
        }
        .frame(maxWidth: .infinity)
    }

    private var keypadPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            KeypadView(keyboard: true) { vm.pressKey($0) }
            HStack(spacing: 8) {
                Button("＋1,000円") { vm.addCash(1_000) }.buttonStyle(.app)
                Button("＋5,000円") { vm.addCash(5_000) }.buttonStyle(.app)
            }
            .frame(maxWidth: 360)
            HStack(spacing: 8) {
                Button("＋10,000円") { vm.addCash(10_000) }.buttonStyle(.app)
                Button("クリア") { vm.pressKey("C") }.buttonStyle(.app)
            }
            .frame(maxWidth: 360)
            if mixed {
                Text("済承認後は方法選び直し・キャンセル不可。").font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - sats待ち

struct SatsWaitingView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ", state: compact ? nil : vm.saleState.label)
            ScrollView(showsIndicators: false) {
                VStack(spacing: compact ? 10 : 14) {
                    AmountBox(label: "請求sats額",
                              value: "\(Fmt.num(vm.totals.sats)) sats",
                              size: 38, horizontal: compact)
                    if vm.totals.cashForSats > 0 {
                        InfoBox(text: "sats確認後に現金 \(Fmt.yen(vm.totals.cashForSats))を受け取る", size: 18, tint: .yellow)
                    }
                    Text("WoSへ入力する額は請求sats額のみ（現金分は入力しない）")
                        .font(.caption).foregroundColor(.secondary)
                    if compact {
                        VStack(spacing: 10) {
                            elapsedTime
                            Button("sats額をコピー") { vm.copySatsAmount() }
                                .buttonStyle(.app)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                    } else {
                        HStack(spacing: 14) {
                            elapsedTime
                            Button("sats額をコピー") { vm.copySatsAmount() }
                                .buttonStyle(.app)
                                .frame(maxWidth: 220, minHeight: 52)
                        }
                    }
                    Button("済（WoSで入金を確認）") { vm.askSatsConfirm() }
                        .buttonStyle(.appPrimary)
                        .frame(maxWidth: 520, minHeight: 72)
                    if compact {
                        VStack(spacing: 10) {
                            Button("方法選び直し") { vm.reselectMethod() }.buttonStyle(.app)
                            Button("キャンセル（確認あり）") { vm.requestSuspend() }.buttonStyle(.app)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        HStack(spacing: 14) {
                            Button("方法選び直し") { vm.reselectMethod() }.buttonStyle(.app)
                            Button("キャンセル（確認あり）") { vm.requestSuspend() }.buttonStyle(.app)
                        }
                    }
                    Text("済承認前のみ方法選び直し・キャンセル可。")
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 16)
                .padding(.top, compact ? 16 : 24)
                .frame(maxWidth: .infinity)
            }
            MessageBar()
        }
    }

    private var elapsedTime: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = max(0, Int(ctx.date.timeIntervalSince(vm.satsStartedAt)))
            AmountBox(label: "経過時間",
                      value: String(format: "%02d:%02d", s / 60, s % 60),
                      size: 16, horizontal: compact)
        }
    }
}

// MARK: - 完了

struct DoneView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ", state: compact ? nil : vm.saleState.label)
            VStack(spacing: 14) {
                InfoBox(text: "完了", size: 32)
                if let d = vm.done {
                    TableRowView(cells: ["販売ID", d.saleId], widths: [200, 400])
                    TableRowView(cells: ["方法", d.method.label], widths: [200, 400])
                    TableRowView(cells: ["請求sats額", d.totalSats.map { Fmt.sats($0) } ?? "―"], widths: [200, 400])
                    TableRowView(cells: ["現金（請求）", d.cashPart.map { Fmt.yen($0) } ?? "―"], widths: [200, 400])
                    TableRowView(cells: ["受取額", d.received.map { Fmt.yen($0) } ?? "―"], widths: [200, 400])
                    TableRowView(cells: ["お釣り", d.change.map { Fmt.yen($0) } ?? "―"], widths: [200, 400])
                }
                Button("次の会計へ") { vm.nextSale() }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: 600, minHeight: 64)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .frame(maxWidth: 720)
            Spacer()
            MessageBar()
        }
    }
}