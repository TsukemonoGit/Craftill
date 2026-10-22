import SwiftUI

// MARK: - レジ画面（待機中・スキャン中）

struct RegisterView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var manualID = ""
    @State private var showScanner = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ", state: vm.saleState.label) {
                Toggle("通信", isOn: $vm.isOnline)
                    .toggleStyle(.switch)
                Button("メニュー") { vm.openMenu() }
                    .buttonStyle(.app)
                    .frame(maxWidth: 160)
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.types) { t in
                        Button(vm.tabLabel(t)) { vm.selectedTypeId = t.typeId }
                            .buttonStyle(AppButtonStyle(primary: t.typeId == vm.selectedTypeId))
                            .frame(minWidth: 120, maxWidth: 240)
                    }
                }
            }
            .frame(minHeight: 40, maxHeight: 56)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 8)], spacing: 8) {
                    ForEach(vm.products(ofType: vm.selectedTypeId)) { p in
                        ProductTile(product: p)
                    }
                }
            }
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
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
                Text("カートは空です\n商品を追加すると「スキャン中」へ遷移")
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
        .frame(minWidth: 360, idealWidth: 520, maxWidth: .infinity,
               minHeight: 420, idealHeight: 560, maxHeight: .infinity)
    }

    private var formView: some View {
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
            Stepper("数量: \(qty)", value: $qty, in: 1...999)
            Spacer()
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
            Spacer()
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

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ", state: vm.saleState.label)
            AdaptiveHStack(breakpoint: 900, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("カート（読み取り専用）").font(.headline)
                    TableRowView(cells: ["商品ID", "商品名", "数量", "小計"], widths: [100, 200, 60, 110], header: true)
                    ForEach(vm.cart) { l in
                        TableRowView(cells: [l.id, l.name, "\(l.qty)", Fmt.yen(l.subtotalJpy)], widths: [100, 200, 60, 110])
                    }
                    Spacer()
                    Panel {
                        Text(vm.satsLine).font(.system(size: 16, weight: .bold))
                        Text(vm.cashLine).font(.system(size: 16, weight: .bold))
                    }
                }
            } second: {
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
            .padding(20)
            MessageBar()
        }
    }
}

// MARK: - 現金入力（現金／併用現金入力 共通）

struct CashEntryView: View {
    @EnvironmentObject var vm: AppViewModel
    let mixed: Bool

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ", state: vm.saleState.label)
            AdaptiveHStack(breakpoint: 820, spacing: 28) {
                VStack(spacing: 12) {
                    if mixed {
                        InfoBox(text: "sats確認済み　\(Fmt.sats(vm.totals.sats))　確認 \(Fmt.time(vm.satsConfirmedAt))",
                                size: 16, tint: .green)
                    }
                    InfoBox(text: (mixed ? "請求額（現金分）\n" : "請求額\n") + Fmt.yen(vm.cashDue), size: 28)
                    InfoBox(text: "受取額\n\(Fmt.yen(vm.cashReceived))", size: 22)
                    InfoBox(text: "お釣り\n" + (vm.canConfirmCash ? Fmt.yen(vm.change) : "―"), size: 22)
                    Button("確定") { vm.confirmCash() }
                        .buttonStyle(.appPrimary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .disabled(!vm.canConfirmCash)
                    Text("受取額 < 請求額の間、確定ボタン無効").font(.caption).foregroundColor(.secondary)
                    Button(mixed ? "会計中断（PIN必須・記録を残す）" : "会計中断") { vm.requestSuspend() }
                        .buttonStyle(.app)
                }
            } second: {
                VStack(alignment: .leading, spacing: 12) {
                    KeypadView { vm.pressKey($0) }
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
            .padding(24)
            Spacer()
            MessageBar()
        }
    }
}

// MARK: - sats待ち

struct SatsWaitingView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ", state: vm.saleState.label)
            VStack(spacing: 14) {
                InfoBox(text: "請求sats額\n\(Fmt.num(vm.totals.sats)) sats", size: 38)
                if vm.totals.cashForSats > 0 {
                    InfoBox(text: "sats確認後に現金 \(Fmt.yen(vm.totals.cashForSats))を受け取る", size: 18, tint: .yellow)
                }
                Text("WoSへ入力する額は請求sats額のみ（現金分は入力しない）")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 14) {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let s = max(0, Int(ctx.date.timeIntervalSince(vm.satsStartedAt)))
                        InfoBox(text: String(format: "経過時間　%02d:%02d", s / 60, s % 60), size: 16)
                    }
                    Button("sats額をコピー") { vm.copySatsAmount() }
                        .buttonStyle(.app)
                        .frame(maxWidth: 220, minHeight: 52)
                }
                Button("済（WoSで入金を確認）") { vm.askSatsConfirm() }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: 520, minHeight: 72)
                HStack(spacing: 14) {
                    Button("方法選び直し") { vm.reselectMethod() }.buttonStyle(.app)
                    Button("キャンセル（確認あり）") { vm.requestSuspend() }.buttonStyle(.app)
                }
                Text("済承認前のみ方法選び直し・キャンセル可。")
                    .font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: 620)
            .padding(.top, 24)
            Spacer()
            MessageBar()
        }
    }
}

// MARK: - 完了

struct DoneView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar("レジ", state: vm.saleState.label)
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
            .padding(.top, 24)
            .frame(maxWidth: 720)
            Spacer()
            MessageBar()
        }
    }
}