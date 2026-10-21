import SwiftUI
import UniformTypeIdentifiers

// ════════════════════════════════════════════════════════════
// データ：CSV取り込み（グループ→種類→商品の順・A-1）とエクスポート（A-8、N-4）
// 1行でもエラーがあれば全体を取り込まない（ImportOutcomeView で問題を一覧表示）
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct DataExportView: View {
    @Environment(FremaRegiStore.self) private var store

    // インポート用の取り込んだテキスト
    @State private var groupText: String?
    @State private var typeText: String?
    @State private var productText: String?
    @State private var overwriteStock = false
    @State private var importPin = ""
    @State private var outcome: FremaRegiStore.ImportOutcome?
    @State private var showImporter = false

    // エクスポート共有
    @State private var shareURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── インポート ──
            GroupBox("CSV取り込み（groups / types / product_master）") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        importedChip("groups", text: groupText)
                        importedChip("types", text: typeText)
                        importedChip("products", text: productText)
                    }
                    Toggle("既存の商品の在庫もCSVで上書き（通常は価格・名前だけ更新・A-1）", isOn: $overwriteStock)
                        .font(.callout)
                    HStack {
                        LabeledField(label: "PIN") { SecretInput(text: $importPin).frame(maxWidth: 140) }
                        Button("検証して取り込む") { runImport() }
                            .buttonStyle(.borderedProminent)
                            .disabled(groupText == nil && typeText == nil && productText == nil)
                        Button("ファイルを選ぶ…") { showImporter = true }
                    }
                    if let outcome { ImportOutcomeView(outcome: outcome) }
                }
                .padding(10)
            }

            // ── エクスポート ──
            GroupBox("出力（Exports/ に書き出して共有・A-8/N-4）") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                    ForEach(FremaRegiStore.ExportKind.allCases) { kind in
                        Button {
                            if let url = store.exportFile(kind: kind) { shareURL = url }
                            else { store.lastMessage = "出力に失敗しました" }
                        } label: {
                            Label(kind.fileName, systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(10)
            }
            Spacer()
        }
        .padding(20)
        .navigationTitle("データ CSV/出力")
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { loadFiles(urls) }
        }
        #if os(macOS)
        .sheet(item: $shareURL) { url in MacShareSheet(url: url) }
        #else
        .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
        #endif
        .toast($store.lastMessage)
    }

    private func importedChip(_ name: String, text: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: text == nil ? "doc" : "checkmark.doc")
                .foregroundStyle(text == nil ? .secondary : .green)
            Text(name + (text.map { "（\($0.split(separator: "\n").count - 1)行）" } ?? "（未選択）"))
                .font(.caption)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private func loadFiles(_ urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let base = url.deletingPathExtension().lastPathComponent.lowercased()
            if base.contains("group") { groupText = text }
            else if base.contains("type") { typeText = text }
            else if base.contains("product") || base.contains("master") { productText = text }
            else { productText = text }   // 判別できないものは商品マスタ扱い
        }
        store.lastMessage = "ファイルを読み込みました。内容を確認して「検証して取り込む」を押してください"
    }

    private func runImport() {
        outcome = store.importCSV(groupText: groupText, typeText: typeText, productText: productText,
                                  overwriteStock: overwriteStock, pin: importPin)
        if outcome?.ok == true {
            groupText = nil; typeText = nil; productText = nil; importPin = ""
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
extension URL: Identifiable {
    public var id: String { absoluteString }
}

#if os(macOS)
/// macOS の共有シート（Finderで表示するだけ）
@available(iOS 17.0, macOS 14.0, *)
struct MacShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(.green)
            Text("書き出しました").font(.headline)
            Text(url.path).font(.caption).monospaced().lineLimit(2).frame(maxWidth: 420)
            HStack {
                Button("閉じる") { dismiss() }
                Button("Finderで表示") { NSWorkspace.shared.activateFileViewerSelecting([url]); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}
#else
/// iOS の UIActivityViewController シート
@available(iOS 17.0, *)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif

// ════════════════════════════════════════════════════════════
// 集計・精算（A-8）：日次／期間・現金照合・販売取消・精算CSV
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct SummaryView: View {
    @Environment(FremaRegiStore.self) private var store

    @State private var day = Date()
    // 期間の初期値は表示と実データの一致を担保するため nil にしない（P1「表示と違う期間を精算する」対策）
    @State private var from: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var to: Date = Date()
    @State private var floatText = "0"
    @State private var actualText = "0"
    @State private var settlePin = ""
    @State private var settlement: String?
    @State private var voidTarget: Sale?
    @State private var voidPin = ""
    // PIN必須の操作（取消・返金フラグ）は alert 内の SecretInput では正しく入力できないため PinSheet を使う
    @State private var showVoidPin = false
    @State private var refundTarget: Sale?
    @State private var refundValue = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("日次集計（ローカル日付の境界・A-19-5）") {
                        VStack(alignment: .leading, spacing: 8) {
                            DatePicker("日付", selection: $day, displayedComponents: .date)
                            let s = store.dailySummary(day: day)
                            summaryRows(s)
                        }.padding(10)
                    }
                    GroupBox("期間集計") {
                        VStack(alignment: .leading, spacing: 8) {
                            DatePicker("開始", selection: $from, displayedComponents: .date)
                            DatePicker("終了", selection: $to, displayedComponents: .date)
                            summaryRows(store.periodSummary(from: from, to: to).total)
                        }.padding(10)
                    }
                    GroupBox("現金照合（日ごと・A-8）") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { LabeledField(label: "釣銭準備金") { TextField("0", text: $floatText).keyboardType(.numberPad).frame(maxWidth: 120) }
                                   LabeledField(label: "実残高") { TextField("0", text: $actualText).keyboardType(.numberPad).frame(maxWidth: 120) } }
                            let r = store.cashReconciliation(day: day, float: Int(floatText) ?? 0, actual: Int(actualText) ?? 0)
                            Text("期待残高 \(jpy(r.expected)) ／ 差引 \(jpy(r.difference))")
                                .foregroundStyle(r.difference == 0 ? Color.green : Color.red)
                        }.padding(10)
                    }
                    GroupBox("精算CSV（PIN必須・A-8。期間は上の「期間集計」と同じ範囲）") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledField(label: "PIN") { SecretInput(text: $settlePin).frame(maxWidth: 140) }
                            Button("生成") { settlement = store.settlementCSV(from: from, to: to, pin: settlePin) }
                            if let settlement {
                                TextEditor(text: .constant(settlement))
                                    .font(.caption.monospaced()).frame(height: 160)
                            }
                        }.padding(10)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: 460)

            Divider()

            // 販売履歴（取消・返金フラグ・A-9）
            VStack(alignment: .leading, spacing: 0) {
                Text("販売履歴").font(.headline).padding(10)
                List {
                    ForEach(store.sales.reversed()) { sale in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(sale.id).fontWeight(.medium).monospaced()
                                Spacer()
                                statusTag(sale)
                            }
                            Text("\(methodLabel(sale.method))  現金 \(sale.totalJpy.map(jpy) ?? "―")  sats \(sale.totalSats.map(sats) ?? "―")")
                                .font(.caption).foregroundStyle(.secondary)
                            if sale.status == .completed {
                                HStack(spacing: 10) {
                                    Button("取消") { voidTarget = sale; showVoidPin = true }
                                        .font(.caption)
                                    Button(sale.refunded ? "返金を取り消す" : "返金済みとして記録") {
                                        refundTarget = sale; refundValue = !sale.refunded
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("集計・精算")
        // 販売取消（PIN必須・A-9）。確認 → PinSheet の順で行う
        .confirmationDialog("販売を取消しますか？（在庫に戻り、記録が残ります・A-9）",
                            isPresented: $showVoidPin, titleVisibility: .visible) {
            Button("次に進んでPINを入力") { voidPin = "" }   // 実際の入力は下の PinSheet で受ける
            Button("やめる", role: .cancel) { voidTarget = nil }
        }
        .sheet(isPresented: Binding(
            get: { voidTarget != nil && !showVoidPin }, set: { on in
                if !on { voidTarget = nil; voidPin = "" }
            })) {
            PinSheet(mode: .verify("販売取消")) { pin in
                if let s = voidTarget { store.lastMessage = store.voidSale(saleId: s.id, pin: pin) }
                voidTarget = nil
            } onCancel: {
                voidTarget = nil
            }
        }
        // 返金フラグ（PIN必須・A-9）
        .sheet(item: $refundTarget) { sale in
            PinSheet(mode: .verify(refundValue ? "返金記録" : "返金の取消し")) { pin in
                store.lastMessage = store.setRefundedFlag(saleId: sale.id, value: refundValue, pin: pin)
            } onCancel: {}
        }
    }

    @ViewBuilder private func summaryRows(_ s: Summary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row("現金売上（併用の現金分を含む）", jpy(s.cashJpy))
            row("sats売上", s.satsAmount > 0 ? sats(s.satsAmount) : "―")
            row("完了件数", "\(s.cashSaleIDs.union(s.satsSaleIDs).count)")
            row("取消", "\(s.canceledSaleIDs.count)件")
            row("中断（sats確認済み）", "\(s.suspendedSaleIDs.count)件")
        }.font(.callout)
    }
    private func row(_ l: String, _ v: String) -> some View {
        HStack { Text(l).foregroundStyle(.secondary); Spacer(); Text(v).monospacedDigit() }
    }
    private func methodLabel(_ m: PaymentMethod) -> String {
        switch m { case .cash: return "現金"; case .lightning: return "sats"; case .mixed: return "併用" }
    }
    @ViewBuilder private func statusTag(_ sale: Sale) -> some View {
        switch sale.status {
        case .completed: Text(sale.refunded ? "返金済" : "完了").font(.caption2).padding(3)
            .background((sale.refunded ? Color.orange : Color.green).opacity(0.15), in: Capsule())
        case .voided: Text("取消").font(.caption2).padding(3)
            .background(Color.red.opacity(0.15), in: Capsule())
        }
    }
}
