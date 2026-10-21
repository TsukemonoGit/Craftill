import SwiftUI
#if os(iOS)
import AVFoundation
#endif

// ════════════════════════════════════════════════════════════
// レジ画面1枚（営業モード・A-3「商品パネルとカートは同一画面」）
// 会計の状態（A-4）で下半分の表示が切り替わる：
//   idle / scanning → パネル＋カート
//   choosingPayment → 支払方法選択
//   cashInput       → 現金入力
//   satsWaiting     → sats待ち（P2画面だが最小実装）
//   mixedCashInput  → 併用現金入力
//   done            → 完了
// UI は store.send(...) の返り値に従うだけ。行き先をUIが決めない（A-4）。
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct RegisterView: View {
    @Environment(FremaRegiStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            switch store.state {
            case .idle, .scanning:
                HStack(spacing: 0) {
                    ProductPanel().frame(maxWidth: .infinity)
                    Divider()
                    CartPanel().frame(width: 340)
                }
            case .choosingPayment:
                PaymentChoiceView()
            case .cashInput:
                CashInputView(mixed: false)
            case .mixedCashInput:
                CashInputView(mixed: true)
            case .satsWaiting:
                SatsWaitingView()
            case .done:
                DoneView()
            case .suspended:
                // 中断状態から待機中へ戻す導線のみ
                VStack(spacing: 16) {
                    Text("会計を中断しました").font(.title2)
                    Button("もどる") { store.backToIdle() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(store.state == .idle ? "レジ（待機中）" : "レジ")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ConnectivityBadge()
                if store.state == .idle || store.state == .scanning {
                    Button("QR読取") { showScanner = true }
                    Button("ID入力") { showIDInput = true }
                    Button("野良") { showAdhoc = true }
                    Button("会計へ進む") { store.send(.toPaymentSelection) }
                        .disabled(store.cart.isEmpty)
                    Button("中断", role: .destructive) { showSuspend = true }
                        .disabled(store.cart.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showScanner) { ScannerSheet() }
        .sheet(isPresented: $showIDInput) { IDInputSheet() }
        .sheet(isPresented: $showAdhoc) { AdhocSheet() }
        .sheet(isPresented: $showSuspend) { SuspendSheet() }
        // カート削除の確認ダイアログ（C-6 #49/#50）
        .alert("商品を削除しますか？", isPresented: deleteBinding) {
            Button("OK", role: .destructive) {
                if let d = store.pendingDelete { store.confirmDelete(d) }
                store.pendingDelete = nil
            }
            Button("キャンセル", role: .cancel) { store.pendingDelete = nil }
        } message: {
            Text(store.pendingDelete?.message ?? "")
        }
        // 状態機械の needsConfirm / needsPIN ダイアログ（A-4）
        .alert(confirmTitle, isPresented: moveConfirmBinding) {
            Button("OK") {
                if case .needsPIN = store.pendingMove { showMovePin = true }
                else { store.confirmPendingMove() }
            }
            Button("キャンセル", role: .cancel) { store.cancelPendingMove() }
        } message: { Text(confirmMessage) }
        .sheet(isPresented: $showMovePin) {
            PinSheet(mode: .verify(confirmTitle)) { pin in
                showMovePin = false
                store.confirmPendingMove(pinInput: pin)
            } onCancel: {
                showMovePin = false; store.cancelPendingMove()
            }
        }
        .toast($store.lastMessage)
    }

    // ── ツールバー用のローカル状態 ──
    @State private var showScanner = false
    @State private var showIDInput = false
    @State private var showAdhoc = false
    @State private var showSuspend = false
    @State private var showMovePin = false

    private var deleteBinding: Binding<Bool> {
        Binding(get: { store.pendingDelete != nil }, set: { if !$0 { store.pendingDelete = nil } })
    }
    private var moveConfirmBinding: Binding<Bool> {
        Binding(get: { store.pendingMove != nil && !showMovePin },
                set: { if !$0 { store.cancelPendingMove() } })
    }
    private var confirmTitle: String { store.pendingMove?.reason?.title ?? "" }
    private var confirmMessage: String { store.pendingMove?.reason?.message ?? "" }

    /// 上部ステータスバー：現在の状態と合計（待機中も同じ。カートが空かどうかだけ）
    private var statusBar: some View {
        HStack {
            Label(stateName, systemImage: "circlebadge.fill")
                .font(.headline)
                .foregroundStyle(store.state == .idle ? Color.secondary : Color.accentColor)
            Spacer()
            if !store.cart.isEmpty {
                let t = store.cart.totals()
                if t.sats > 0 {
                    Text("sats払い \(sats(t.sats)) ＋ \(jpy(t.cashForSats))").font(.callout)
                }
                Text("現金 \(jpy(t.cash))").font(.callout.monospacedDigit())
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    private var stateName: String {
        switch store.state {
        case .idle: return "待機中"
        case .scanning: return "スキャン中"
        case .choosingPayment: return "お支払い方法"
        case .cashInput: return "現金"
        case .satsWaiting: return "sats待ち"
        case .mixedCashInput: return "現金分を受け取り"
        case .suspended: return "中断"
        case .done: return "完了"
        }
    }
}

// ════════════════════════════════════════════════════════════
// 左：商品パネル（種類タブ＋グリッド。在庫0は SOLD OUT）
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct ProductPanel: View {
    @Environment(FremaRegiStore.self) private var store
    @State private var selectedTypeId: String?

    private var visibleTypes: [ProductType] { store.types }

    var body: some View {
        VStack(spacing: 8) {
            // 種類タブ
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleTypes) { t in
                        Button {
                            selectedTypeId = t.typeId
                        } label: {
                            Text(t.name)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(selectedTypeId == t.typeId ? Color.accentColor : Color.secondary.opacity(0.15),
                                            in: Capsule())
                                .foregroundStyle(selectedTypeId == t.typeId ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            // 商品グリッド
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(productsToShow) { p in
                        ProductTile(product: p, soldOut: isSoldOut(p, in: store.inventory, types: store.types))
                            .onTapGesture { store.addRegistered(productId: p.id) }
                    }
                }
                .padding()
            }
        }
        .onAppear { selectedTypeId = visibleTypes.first?.typeId }
    }

    private var productsToShow: [Product] {
        guard let tid = selectedTypeId else { return [] }
        return store.inventory.filter { $0.typeId == tid }
    }
}

/// 商品のタイル（画像 or 名前・属性の文字表示で代替・A-1）
@available(iOS 17.0, macOS 14.0, *)
struct ProductTile: View {
    let product: Product
    let soldOut: Bool
    @Environment(FremaRegiStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 78)
                if let ref = product.imageRef, let img = loadImage(ref) {
                    #if os(macOS)
                    Image(nsImage: img).resizable().scaledToFit().frame(height: 74)
                    #else
                    Image(uiImage: img).resizable().scaledToFit().frame(height: 74)
                    #endif
                } else {
                    // 画像なしは商品名・属性の文字表示で代替（A-1）
                    VStack {
                        Text(product.name).font(.caption.bold()).lineLimit(1)
                        Text(product.attrText(in: store.types) ?? product.id)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if soldOut {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.55))
                    Text("SOLD OUT").font(.caption.bold()).foregroundStyle(.white)
                }
            }
            Text(product.id).font(.caption.monospaced())
            HStack(spacing: 4) {
                Text(jpy(product.priceJpy)).font(.caption2)
                if let s = product.priceSats { Text(sats(s)).font(.caption2).foregroundStyle(.orange) }
                else { Text("―（現金）").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        .opacity(soldOut ? 0.7 : 1)
    }

    private func loadImage(_ ref: String) -> PlatformImage? {
        PlatformImage(named: ref) ?? PlatformImage(contentsOfFile: ref)
    }
}

// ════════════════════════════════════════════════════════════
// 右：カート（[－][＋][削除]で行を選ぶ・A-3）
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct CartPanel: View {
    @Environment(FremaRegiStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("カート").font(.headline).padding(10)
            Divider()
            if store.cart.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "basket").font(.largeTitle).foregroundStyle(.secondary)
                    Text("商品をスキャンしてください").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.cart.enumerated()), id: \.element.id) { i, line in
                            cartRow(i: i, line: line)
                            Divider()
                        }
                    }
                }
                Spacer()
                totalsFooter
            }
        }
    }

    private func cartRow(i: Int, line: CartLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(line.name).lineLimit(1)
                if line.isAdhoc { Text("野良").font(.caption2).padding(2)
                    .background(Color.purple.opacity(0.15), in: Capsule()) }
                Spacer()
                Text(jpy(line.subtotalJpy)).monospacedDigit()
            }
            HStack {
                Text("\(line.id) ×\(line.qty)").font(.caption).foregroundStyle(.secondary)
                if let s = line.unitPriceSats { Text(sats(s) + "×" + String(line.qty)).font(.caption).foregroundStyle(.orange) }
                Spacer()
                Button { store.decrease(at: i) } label: { Image(systemName: "minus.circle") }
                Button { store.increase(at: i) } label: { Image(systemName: "plus.circle") }
                Button(role: .destructive) { store.requestDelete(at: i) } label: { Image(systemName: "trash") }
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private var totalsFooter: some View {
        let t = store.cart.totals()
        return VStack(alignment: .trailing, spacing: 4) {
            Divider()
            if t.sats > 0 {
                HStack { Text("sats払い"); Spacer(); Text(sats(t.sats) + " ＋ " + jpy(t.cashForSats)) }
                    .foregroundStyle(.orange)
            }
            HStack { Text("現金").font(.headline); Spacer(); Text(jpy(t.cash)).font(.headline.monospacedDigit()) }
        }
        .padding(10)
    }
}

// ════════════════════════════════════════════════════════════
// 支払方法選択（sats単価のない行だけなら sats払いは無効表示・A-6-1/A-10）
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct PaymentChoiceView: View {
    @Environment(FremaRegiStore.self) private var store

    var body: some View {
        let t = store.cart.totals()
        VStack(spacing: 24) {
            Spacer()
            Text("お支払い方法").font(.title2.bold())
            if t.sats > 0 {
                Text("sats払い  \(sats(t.sats)) ＋ \(jpy(t.cashForSats))").foregroundStyle(.orange)
            }
            Text("現金  \(jpy(t.cash))")
            HStack(spacing: 24) {
                Button { store.send(.chooseCash) } label: {
                    VStack { Image(systemName: "banknote").font(.largeTitle); Text("現金") }
                        .frame(width: 200, height: 120)
                }.buttonStyle(.borderedProminent)

                Button { store.send(.chooseSats) } label: {
                    VStack { Image(systemName: "bolt.fill").font(.largeTitle); Text("sats払い") }
                        .frame(width: 200, height: 120)
                }
                .buttonStyle(.bordered)
                .disabled(!store.satsAvailable)   // 通信なし・sats単価なし行のみなら無効（A-10）
                .overlay(alignment: .bottom) {
                    if !store.satsAvailable {
                        Text(store.hasConnectivity ? "sats単価のある行がありません" : "オフラインのため不可")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Button("← 戻る") { store.send(.backToScan) }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ════════════════════════════════════════════════════════════
// 現金入力（請求/受取/お釣り。受取<請求の間は確定できない・A-4①〜④）
// mixed=true なら併用現金入力中（sats確認済みの現金分だけ受け取る・C-6 #77）
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct CashInputView: View {
    @Environment(FremaRegiStore.self) private var store
    let mixed: Bool

    @State private var receivedText: String = ""

    private var billed: Int {
        mixed ? store.cart.totals().cashForSats   // sats確認後に据え置いた現金分（C-6 #77/#78）
              : store.cart.totals().cash
    }
    private var received: Int { Int(receivedText) ?? 0 }
    private var change: Int { max(0, received - billed) }
    private var canConfirm: Bool { received >= billed && billed > 0 }

    var body: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 14) {
                if mixed {
                    Label("sats確認済み  \(sats(store.ctx.confirmedSats ?? 0))", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                row("請求額", jpy(billed))
                row("受取額", jpy(received))
                row("お釣り", jpy(change)).foregroundStyle(change > 0 ? .green : .primary)
                Spacer()
                Button(mixed ? "確 定" : "確 定") {
                    if mixed { store.confirmMixedCash(received: received) }
                    else { store.confirmCash(received: received) }
                }
                .buttonStyle(.borderedProminent)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 54)
                .disabled(!canConfirm)   // 受取 < 請求 の間は押せない
                Text(canConfirm ? "" : "受取額が請求額に達していません").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                quickButtons
                NumericKeypad(showDoubleZero: true) { key in handle(key) }
                    .frame(maxWidth: 320)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).font(.title2.monospacedDigit()) }
            .frame(maxWidth: 320)
    }

    private var quickButtons: some View {
        HStack {
            ForEach([1000, 5000, 10000], id: \.self) { v in
                Button(jpy(v)) { receivedText = String(received + v) }
            }
        }
        .font(.callout)
    }

    private func handle(_ key: KeypadKey) {
        switch key {
        case .digit(let d): receivedText.append(d)
        case .doubleZero: receivedText += "00"
        case .backspace: if !receivedText.isEmpty { receivedText.removeLast() }
        }
    }
}

// ════════════════════════════════════════════════════════════
// sats待ち（WoS誘導。「済」は確認ダイアログを経由・C-6 #23）
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct SatsWaitingView: View {
    @Environment(FremaRegiStore.self) private var store
    @State private var showDoneConfirm = false

    var body: some View {
        let t = store.cart.totals()
        VStack(spacing: 20) {
            Spacer()
            Text("sats払い").font(.title2.bold())
            Text("請求  \(sats(t.sats))").font(.title)
            if t.cashForSats > 0 {
                Text("（現金分 \(jpy(t.cashForSats)) は sats確認後に受け取り）").foregroundStyle(.secondary)
            }
            Button {
                #if os(iOS)
                UIPasteboard.general.string = String(t.sats)
                #endif
                store.lastMessage = "sats額をコピーしました"
            } label: { Label("sats額をコピー", systemImage: "doc.on.doc") }

            Text("WoSでInvoice作成 → 客が支払う").font(.callout).foregroundStyle(.secondary)

            HStack(spacing: 24) {
                Button("方法を選び直す") { store.changeMethod() }
                Button("済") { showDoneConfirm = true }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("客からsatsの入金を確認できましたか？", isPresented: $showDoneConfirm, titleVisibility: .visible) {
            Button("確認できた（済）") { store.tapSatsDoneConfirmed() }
            Button("まだです", role: .cancel) {}
        }
    }
}

// ════════════════════════════════════════════════════════════
// 完了（タップで待機中へ・A-4）
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct DoneView: View {
    @Environment(FremaRegiStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(.green)
            Text("完 了").font(.largeTitle.bold())
            Text("（タップで待機中へ）").foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { store.backToIdle() }
    }
}

// ════════════════════════════════════════════════════════════
// シート群：QRスキャナー / ID手動入力 / 野良追加 / 中断
// ════════════════════════════════════════════════════════════

/// QR読み取り（連続読み取りのクールダウン＝同一IDを2秒あけない・A-2）
@available(iOS 17.0, macOS 14.0, *)
struct ScannerSheet: View {
    @Environment(FremaRegiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var lastCode = ""      // macOS デモ入力のテキスト
    @State private var lastID = ""        // 直前に取り込んだ商品ID（クールダウン用）
    @State private var lastAt = Date.distantPast

    var body: some View {
        VStack(spacing: 16) {
            Text("QRスキャナー").font(.headline)
            #if os(iOS)
            CameraQRPreview { code in ingest(code) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            TextField("商品ID（デモ：カメラなし）", text: $lastCode)
                .frame(maxWidth: 300)
                .textInputItem()
                .onSubmit { ingest(lastCode); lastCode = "" }
            #endif
            Button("閉じる") { dismiss() }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 420)
    }

    private func ingest(_ payload: String) {
        let now = Date()
        let pid = IDNormalizer.fromQR(payload)
        // クールダウン：直前と同じIDは2秒受け付けない（A-2）
        if pid == lastID && now.timeIntervalSince(lastAt) < 2 { return }
        lastID = pid; lastAt = now
        store.scanQR(payload)
    }
}

#if os(iOS)
/// AVFoundation でメタフレームからQRを拾う簡易プレビュー
@available(iOS 17.0, *)
struct CameraQRPreview: UIViewRepresentable {
    let onCode: (String) -> Void

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.onCode = onCode
        v.start()
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            // プレビューレイヤーは親の bounds に常に追従させる（P2「カメラ映像が表示されない」対策）
            previewLayer?.frame = bounds
        }

        func start() {
            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr, .ean13, .code128]
            let pl = AVCaptureVideoPreviewLayer(session: session)
            pl.videoGravity = .resizeAspectFill
            pl.frame = bounds
            layer.insertSublayer(pl, at: 0)
            previewLayer = pl
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }

        func metadataOutput(_ o: AVCaptureMetadataOutput, didOutput m: [AVMetadataObject], from c: AVCaptureConnection) {
            if let obj = m.first as? AVMetadataMachineReadableCodeObject, let s = obj.stringValue {
                onCode?(s)
            }
        }
    }
}
#endif

/// ID手動入力（全角→半角補正は Store.enterID / IDNormalizer が行う・A-2）
@available(iOS 17.0, macOS 14.0, *)
struct IDInputSheet: View {
    @Environment(FremaRegiStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var raw = ""

    var body: some View {
        VStack(spacing: 14) {
            Text("商品IDを入力").font(.headline)
            TextField("例: KH-001（全角でも補正します）", text: $raw)
                .frame(maxWidth: 320).textInputItem()
                .onSubmit { submit() }
            HStack {
                Button("キャンセル") { dismiss() }
                Button("追加") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(raw.isEmpty)
            }
        }
        .padding(24)
    }

    private func submit() {
        store.enterID(raw)
        raw = ""
        dismiss()
    }
}

/// 野良商品の追加（金額はここで確認してから最終確定・A-19-10）
@available(iOS 17.0, macOS 14.0, *)
struct AdhocSheet: View {
    @Environment(FremaRegiStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var priceJpyText = ""
    @State private var priceSats: Int? = nil
    @State private var groupId: String? = nil
    @State private var qtyText = "1"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("野良商品を追加").font(.headline)
            LabeledField(label: "名称") { TextField("例: ○○さんの手作り石けん", text: $name).frame(maxWidth: 320) }
            LabeledField(label: "円価格（1以上）") { TextField("800", text: $priceJpyText).keyboardType(.numberPad).frame(maxWidth: 160) }
            LabeledField(label: "sats単価（空欄＝現金のみ）") { OptionalIntField(placeholder: "任意", value: $priceSats).frame(maxWidth: 160) }
            LabeledField(label: "委託元グループ") {
                Picker("", selection: $groupId) {
                    Text("グループなし").tag(String?.none)
                    ForEach(store.groups) { g in Text(g.label).tag(String?.some(g.groupId)) }
                }.labelsHidden().frame(maxWidth: 220)
            }
            LabeledField(label: "数量") { TextField("1", text: $qtyText).keyboardType(.numberPad).frame(maxWidth: 80) }
            HStack {
                Button("キャンセル") { dismiss() }
                Button("カートに追加") {
                    store.addAdhoc(name: name,
                                   priceJpy: Int(priceJpyText) ?? 0,
                                   priceSats: priceSats,
                                   groupId: groupId,
                                   qty: max(1, Int(qtyText) ?? 1))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(Int(priceJpyText) == nil || (Int(priceJpyText) ?? 0) < 1)
            }
        }
        .padding(24)
    }
}

/// 会計中断（sats未確認なら記録なし／sats確認済みならPIN必須・A-19-2、C-6 #67）
@available(iOS 17.0, macOS 14.0, *)
struct SuspendSheet: View {
    @Environment(FremaRegiStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PinSheet(mode: .verify("会計中断")) { pin in
            store.suspendSale(pinInput: pin)
            dismiss()
        } onCancel: {
            dismiss()
        }
    }
}
