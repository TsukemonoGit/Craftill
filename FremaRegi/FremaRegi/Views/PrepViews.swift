import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

/// imageRef（解決済みの実体パス）から同梱画像を読み出す。
/// 起動時・追加時の attachMissingImages で実体パスが記録されているため、
/// contentsOfFile が主経路。旧データで名前のみ保存されていた場合の保険として named も試す。
func loadProductImage(_ ref: String) -> PlatformImage? {
    PlatformImage(contentsOfFile: ref) ?? PlatformImage(named: ref)
}

// ════════════════════════════════════════════════════════════
// 準備モード（営業前）のメニュー（5_画面構成.md）
//   商品 ○ / QRラベル ○ / 在庫 △ / データCSV ×→最小で実装 / 設定 △
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct PrepMenuView: View {
    @Environment(FremaRegiStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !store.canEdit {
                    Label("会計中のため編集できません。レジを完了/中断してから戻ってください（A-1）",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).padding()
                }
                HStack(spacing: 20) {
                    prepCard("商品", "square.grid.2x2", ProductsAdminView())
                    prepCard("QRラベル", "qrcode", QRLabelView())
                    prepCard("在庫", "shippingbox", InventoryAdminView())
                }
                HStack(spacing: 20) {
                    prepCard("データ CSV/出力", "doc.on.doc", DataExportView())
                    prepCard("集計・精算", "chart.bar.xaxis", SummaryView())
                    prepCard("設定 (PIN)", "gearshape", SettingsView())
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("準備（営業前）")
        .toast($store.lastMessage)
    }

    private func prepCard<V: View>(_ title: String, _ icon: String, _ dest: V) -> some View {
        NavigationLink { dest } label: {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 34))
                Text(title).font(.headline)
            }
            .frame(width: 180, height: 120)
            .background(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
        }
        .buttonStyle(.plain)
        .disabled(!store.canEdit && title != "集計・精算" && title != "設定 (PIN)")
    }
}

// ════════════════════════════════════════════════════════════
// 商品：一覧・確認（画像なし件数表示・種類タブ・属性表示）
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct ProductsAdminView: View {
    @Environment(FremaRegiStore.self) private var store
    @State private var selectedTypeId: String?
    @State private var showAdd = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("種類", selection: $selectedTypeId) {
                    Text("すべて").tag(String?.none)
                    ForEach(store.types) { t in Text(t.name).tag(String?.some(t.typeId)) }
                }
                .frame(maxWidth: 260)
                Spacer()
                Text("画像なし: \(store.missingImageIDs.count)件")
                    .font(.callout).foregroundStyle(store.missingImageIDs.isEmpty ? .secondary : .orange)
                Button("商品を追加") { showAdd = true }
                    .disabled(store.types.isEmpty)
            }
            .padding([.horizontal, .top])

            List {
                ForEach(filtered) { p in
                    HStack(spacing: 12) {
                        // 画像 or 文字代替（A-1）
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)).frame(width: 56, height: 56)
                            if let ref = p.imageRef, let img = loadProductImage(ref) {
                                #if os(macOS)
                                Image(nsImage: img).resizable().scaledToFit().frame(width: 52, height: 52)
                                #else
                                Image(uiImage: img).resizable().scaledToFit().frame(width: 52, height: 52)
                                #endif
                            } else {
                                Image(systemName: "photo").foregroundStyle(.tertiary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(p.id)  \(p.name)").fontWeight(.medium)
                            if let a = p.attrText(in: store.types) { Text(a).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(jpy(p.priceJpy))
                            if let s = p.priceSats { Text(sats(s)).font(.caption).foregroundStyle(.orange) }
                            else { Text("―（現金）").font(.caption).foregroundStyle(.secondary) }
                            if p.managesStock(in: store.types) {
                                Text("在庫 \(p.stock ?? 0)").font(.caption2)
                                    .foregroundStyle((p.stock ?? 0) == 0 ? Color.red : .secondary)
                            } else {
                                Text("在庫なし型").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button("公開切替") {
                            store.editProduct(productId: p.id, name: p.name, priceJpy: p.priceJpy,
                                              priceSats: p.priceSats, attrs: Array(p.attrs),
                                              isPublic: !p.isPublic, pin: "")
                        }
                    }
                }
            }
        }
        .navigationTitle("商品")
        .sheet(isPresented: $showAdd) { AddProductSheet() }
        .onAppear { if selectedTypeId == nil { selectedTypeId = store.types.first?.typeId } }
    }

    private var filtered: [Product] {
        guard let tid = selectedTypeId else { return store.inventory }
        return store.inventory.filter { $0.typeId == tid }
    }
}

/// 商品追加シート（IDは種類の nextNo から自動採番・A-1）
@available(iOS 17.0, macOS 14.0, *)
struct AddProductSheet: View {
    @Environment(FremaRegiStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var typeId = ""
    @State private var name = ""
    @State private var priceJpyText = ""
    @State private var priceSats: Int? = nil
    @State private var attr1 = "", attr2 = "", attr3 = ""
    @State private var stockText = ""
    @State private var isPublic = false
    @State private var pin = ""
    @State private var result: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("種類", selection: $typeId) {
                    Text("選択してください").tag("")
                    ForEach(store.types) { t in Text("\(t.name)（\(t.idPrefix)-…・\(t.stockMode.rawValue)）").tag(t.typeId) }
                }
                LabeledField(label: "商品名") { TextField("", text: $name) }
                LabeledField(label: "円価格") { TextField("800", text: $priceJpyText).keyboardType(.numberPad) }
                LabeledField(label: "sats単価（空欄＝現金のみ）") { OptionalIntField(placeholder: "任意", value: $priceSats) }
                Section("属性（種類のラベル順に左から詰める）") {
                    if label(at: 0) != nil { LabeledField(label: label(at: 0)!) { TextField("", text: $attr1) } }
                    if label(at: 1) != nil { LabeledField(label: label(at: 1)!) { TextField("", text: $attr2) } }
                    if label(at: 2) != nil { LabeledField(label: label(at: 2)!) { TextField("", text: $attr3) } }
                }
                if let mode = selectedMode, mode != .none {
                    LabeledField(label: mode == .unique ? "在庫（0か1）" : "初期在庫（0以上）") {
                        TextField("0", text: $stockText).keyboardType(.numberPad)
                    }
                }
                Toggle("公開（Bへ送る）", isOn: $isPublic)
                LabeledField(label: "PIN") { SecretInput(text: $pin) }
                if let result { Text(result).font(.callout).foregroundStyle(.red) }
                Button("追加") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(typeId.isEmpty || name.isEmpty || Int(priceJpyText) == nil)
            }
            .padding(20)
            .navigationTitle("商品を追加")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
    }

    private var selectedMode: StockMode? {
        store.types.first { $0.typeId == typeId }?.stockMode
    }
    private func label(at i: Int) -> String? {
        guard let t = store.types.first(where: { $0.typeId == typeId }) else { return nil }
        return [t.attrLabel1, t.attrLabel2, t.attrLabel3][i]
    }

    private func submit() {
        var input = NewProductInput(typeId: typeId, name: name,
                                    priceJpy: Int(priceJpyText) ?? 0, priceSats: priceSats)
        input.attr1 = attr1.isEmpty ? nil : attr1
        input.attr2 = attr2.isEmpty ? nil : attr2
        input.attr3 = attr3.isEmpty ? nil : attr3
        input.initialStock = selectedMode == .none ? nil : Int(stockText)
        input.isPublic = isPublic
        let msg = store.addProduct(input, pin: pin)
        if msg.hasPrefix("追加:") { dismiss() } else { result = msg }
    }
}

// ════════════════════════════════════════════════════════════
// QRラベル生成（QRの中身＝商品ID。ID文字を併記して印刷・A-2）
// CoreImage でQRシンボルを描画。印刷は Print / Share 経由。
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct QRLabelView: View {
    @Environment(FremaRegiStore.self) private var store
    @State private var scopeAll = true
    @State private var typeId = ""

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Toggle("全商品", isOn: $scopeAll).toggleStyle(.radioGroup)
                if !scopeAll {
                    Picker("", selection: $typeId) {
                        ForEach(store.types) { t in Text(t.name).tag(t.typeId) }
                    }.labelsHidden().frame(maxWidth: 200)
                } else {
                    // radioGroup は iOS のみ。macOS では CheckMark スタイルで代用
                    EmptyView()
                }
                Spacer()
                #if os(iOS)
                Button(action: printLabels) { Label("印刷", systemImage: "printer") }
                #endif
            }
            .padding(.horizontal)
            // QRのないラベルを印刷しない（A-2・P1対策）：QR生成に失敗した商品は対象から除外する
            if targetsWithQR.isEmpty {
                ContentUnavailableCompat(title: "印刷できるラベルがありません",
                                         description: "QRコードを生成できた商品がありません。商品IDを確認してください。")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 14) {
                        ForEach(targetsWithQR) { p in
                            VStack(spacing: 6) {
                                QRCodeImage(text: p.id, size: 110)
                                    .frame(width: 110, height: 110)
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                                Text(p.id).font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("QRラベル生成")
        .onAppear { if typeId.isEmpty { typeId = store.types.first?.typeId ?? "" } }
    }

    private var targets: [Product] {
        scopeAll ? store.inventory : store.inventory.filter { $0.typeId == typeId }
    }

    /// QR生成に成功する商品のみを印刷対象にする（QRなしラベルの印刷防止）
    private var targetsWithQR: [Product] {
        targets.filter { QRCodeImage.canGenerate(text: $0.id) }
    }

    #if os(iOS)
    private func printLabels() {
        let vc = UIActivityViewController(activityItems: [targetsWithQR.map(\.id).joined(separator: "\n")],
                                          applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(vc, animated: true)
        }
    }
    #endif
}

/// CoreImage によるQRコード画像
@available(iOS 17.0, macOS 14.0, *)
struct QRCodeImage: View {
    let text: String
    var size: CGFloat = 120

    var body: some View {
        if let img = generate() {
            #if os(macOS)
            Image(nsImage: img).interpolation(.none).resizable()
            #else
            Image(uiImage: img).interpolation(.none).resizable()
            #endif
        } else {
            Image(systemName: "qrcode").resizable().scaledToFit()
        }
    }

    private func generate() -> PlatformImage? {
        let data = text.data(using: .utf8) ?? Data()
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(data, forKey: "inputData")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage else { return nil }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: size / out.extent.width, y: size / out.extent.height))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        #if os(macOS)
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
        #else
        return UIImage(cgImage: cg)
        #endif
    }

    /// QR生成が可能かどうかを事前判定する（印刷対象の絞り込みに使用）
    static func canGenerate(text: String) -> Bool {
        let data = text.data(using: .utf8) ?? Data()
        guard !data.isEmpty, let f = CIFilter(name: "CIQRCodeGenerator") else { return false }
        f.setValue(data, forKey: "inputData")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage else { return false }
        return CIContext().createCGImage(out, from: out.extent) != nil
    }
}

/// iOS15/macOS12 以降で使える「該当なし」表示の簡易版（ContentUnavailableView のフォールバック）
@available(iOS 17.0, macOS 14.0, *)
struct ContentUnavailableCompat: View {
    let title: String
    var description: String? = nil

    var body: some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            ContentUnavailableView(title, systemImage: "qrcode.viewfinder", description: Text(description ?? ""))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "qrcode.viewfinder").font(.largeTitle).foregroundStyle(.secondary)
                Text(title).font(.headline)
                if let description { Text(description).font(.callout).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// ════════════════════════════════════════════════════════════
// 在庫（棚卸し調整・△扱いだが最小実装。変動ログが残る・A-7）
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct InventoryAdminView: View {
    @Environment(FremaRegiStore.self) private var store
    @State private var target: Product?
    @State private var newStockText = ""
    @State private var pin = ""
    @State private var result: String?

    var body: some View {
        HStack(spacing: 0) {
            List(store.inventory.filter { $0.managesStock(in: store.types) }) { p in
                Button {
                    target = p; newStockText = String(p.stock ?? 0); result = nil
                } label: {
                    HStack {
                        Text(p.id).monospaced()
                        Text(p.name).lineLimit(1)
                        Spacer()
                        Text("現在 \(p.stock ?? 0)")
                            .foregroundStyle((p.stock ?? 0) == 0 ? Color.red : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 420)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                if let p = target {
                    Text("\(p.id) \(p.name) を棚卸し").font(.headline)
                    LabeledField(label: "新しい在庫数") {
                        TextField("0", text: $newStockText).keyboardType(.numberPad).frame(maxWidth: 120)
                    }
                    LabeledField(label: "PIN") { SecretInput(text: $pin).frame(maxWidth: 160) }
                    Button("調整（理由: 棚卸し）") {
                        result = store.adjustStock(productId: p.id, newStock: Int(newStockText) ?? -1, pin: pin)
                    }
                    .buttonStyle(.borderedProminent)
                    if let result { Text(result).font(.callout).foregroundStyle(.orange) }
                } else {
                    Text("左から商品を選ぶと在庫を調整できます（更新は stock_movements に追記されるだけ・A-7）")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Divider()
                Text("自己点検（products.stock と movements 合計の一致・A-19-1）").font(.caption.bold())
                let bad = store.stockSelfCheck().filter { !$0.3 }
                Text(bad.isEmpty ? "OK：すべての商品で一致しています"
                                 : "不一致 \(bad.count)件: " + bad.map { $0.0 }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(bad.isEmpty ? .green : .red)
                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("在庫")
    }
}

// ════════════════════════════════════════════════════════════
// 設定（PIN再設定・スナップショット送信・送信ログ）
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct SettingsView: View {
    @Environment(FremaRegiStore.self) private var store
    @State private var showReset = false
    @State private var sending = false
    @State private var sendResult: String?

    var body: some View {
        Form {
            Section("PIN") {
                Button("PINを変更する") { showReset = true }
            }
            Section("Bへの送信（公開用スナップショット・A-14）") {
                LabeledField(label: "エンドポイント") {
                    Text(AppKVConfig.endpoint.isEmpty ? "未設定（Services/AppConfig.swift）" : AppKVConfig.endpoint)
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Button(sending ? "送信中…" : "いまのスナップショットを送信") {
                    sending = true
                    Task {
                        sendResult = await store.sendSnapshot()
                        sending = false
                    }
                }
                .disabled(sending || AppKVConfig.endpoint.isEmpty)
                if let sendResult { Text(sendResult).font(.callout) }
            }
            Section("送信ログ（sync_log）") {
                if store.syncLog.isEmpty { Text("まだ送信していません").foregroundStyle(.secondary) }
                ForEach(store.syncLog.suffix(10).reversed()) { e in
                    HStack {
                        Image(systemName: e.result == .success ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(e.result == .success ? .green : .red)
                        Text(e.detail).font(.caption)
                        Spacer()
                        Text(e.at.formatted(date: .omitted, time: .shortened)).font(.caption2)
                    }
                }
            }
        }
        .padding(20)
        .navigationTitle("設定")
        .sheet(isPresented: $showReset) {
            PinSheet(mode: .setup) { pin in
                showReset = false
                if !store.setPIN(pin) { store.lastMessage = "PINは4〜8桁の数字で" }
            } onCancel: { showReset = false }
        }
    }
}
