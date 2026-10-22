import SwiftUI

// MARK: - 初回起動（PIN未設定）

struct InitialLaunchView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var pin1 = ""
    @State private var pin2 = ""

    var body: some View {
        VStack(spacing: 0) {
            TopBar("起動", state: "PIN未設定")
            VStack(spacing: 14) {
                InfoBox(text: "アプリ起動\nPINが未設定です", size: 22)
                VStack(alignment: .leading, spacing: 6) {
                    Text("PIN").font(.caption).foregroundColor(.secondary)
                    SecureField("PIN", text: $pin1).textFieldStyle(.roundedBorder)
                    Text("PIN（確認）").font(.caption).foregroundColor(.secondary)
                    SecureField("PIN（確認）", text: $pin2).textFieldStyle(.roundedBorder)
                }
                Button("PINを設定する") { vm.setPin(pin1, confirm: pin2) }
                    .buttonStyle(.appPrimary)
                    .frame(height: 60)
                    .disabled(pin1.isEmpty || pin2.isEmpty)
                Button("初期投入（グループ・種類・商品の登録／CSV取り込み）") { vm.go(.edit) }
                    .buttonStyle(.app)
                    .frame(height: 60)
                Button("販売取消・在庫調整・エクスポート・価格編集") {}
                    .buttonStyle(.app)
                    .disabled(true)
                Text("PIN設定前は初期投入のみ可。PIN必須の操作は不可。")
                    .font(.caption).foregroundColor(.secondary)
                Panel(title: "起動時の状態復元") {
                    Text("保存済みの会計状態がある場合、直前の状態（スキャン中・sats待ち・併用現金入力中を含む）へ復元。")
                    Text("カメラ読み取りが再開できない場合は再起動を促す表示を出す。")
                }
            }
            .frame(width: 620)
            .padding(.top, 24)
            Spacer()
            MessageBar()
        }
    }
}

// MARK: - 機能メニュー

struct MenuView: View {
    @EnvironmentObject var vm: AppViewModel

    private struct Item: Identifiable {
        let id: String
        let title: String
        let note: String
        let action: () -> Void
    }

    private var items: [Item] {
        [
            Item(id: "register", title: "レジへ戻る", note: "") { vm.go(.register) },
            Item(id: "edit", title: "編集（グループ・種類・商品）", note: "待機中のみ・PIN必須") {
                vm.requirePin("編集") { vm.go(.edit) }
            },
            Item(id: "csv", title: "CSV取り込み・書き出し", note: "取り込みは待機中のみ・PIN必須") {
                vm.requirePin("CSV取り込み・書き出し") { vm.go(.csvImport) }
            },
            Item(id: "report", title: "集計（日次・期間全体）", note: "表示はPIN不要") { vm.go(.report) },
            Item(id: "history", title: "販売履歴・取消", note: "取消・返金済み設定はPIN必須") { vm.go(.salesHistory) },
            Item(id: "stock", title: "手動在庫調整", note: "PIN必須") {
                vm.requirePin("手動在庫調整") { vm.go(.stockAdjust) }
            },
            Item(id: "price", title: "価格一覧・画像なしID一覧", note: "") { vm.go(.priceList) },
            Item(id: "sync", title: "公開サイトへ送信・送信ログ", note: "") { vm.go(.sync) },
            Item(id: "export", title: "エクスポート（販売・在庫・精算CSV）", note: "PIN必須") {
                vm.requirePin("エクスポート") { vm.dialog = .message("エクスポート（スタブ）") }
            }
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar("機能メニュー", state: vm.saleState.label)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(items) { item in
                        Button { item.action() } label: {
                            VStack(spacing: 6) {
                                Text(item.title).font(.system(size: 16, weight: .bold)).multilineTextAlignment(.center)
                                if !item.note.isEmpty {
                                    Text(item.note).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 110)
                        }
                        .buttonStyle(AppButtonStyle(primary: item.id == "register"))
                    }
                }
                .padding(24)
                Text("メニューは待機中（カートが空）のみ開ける。PIN必須の操作は実行時にPIN入力。")
                    .font(.caption).foregroundColor(.secondary)
            }
            MessageBar()
        }
    }
}

// MARK: - 編集（グループ・種類・商品）

struct EditView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case group = "グループ"
        case type = "種類"
        case product = "商品"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .product

    var body: some View {
        AdminShell("編集（待機中）") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
                switch tab {
                case .group: GroupEditor()
                case .type: TypeEditor()
                case .product: ProductEditor()
                }
            }
        }
    }
}

struct GroupEditor: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var gid = ""
    @State private var label = ""
    @State private var editing = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Panel(title: "グループ一覧") {
                TableRowView(cells: ["グループID", "ラベル", "使用状況"], widths: [120, 180, 90], header: true)
                ForEach(vm.groups) { g in
                    HStack(spacing: 6) {
                        TableRowView(cells: [g.groupId, g.label, vm.isGroupInUse(g.groupId) ? "使用中" : "未使用"],
                                     widths: [120, 180, 90])
                        Button("ラベル変更") {
                            gid = g.groupId
                            label = g.label
                            editing = true
                        }
                        .buttonStyle(.app).frame(width: 100)
                        Button("削除") { vm.deleteGroup(g.groupId) }
                            .buttonStyle(.app).frame(width: 70)
                            .disabled(vm.isGroupInUse(g.groupId))
                    }
                }
                Text("削除: 種類または販売明細から参照されている場合は不可。ラベル変更は過去の集計表示にも反映される。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Panel(title: editing ? "ラベル変更" : "グループを追加") {
                LabeledField(label: "グループID（半角英数字・_。追加後変更不可）", text: $gid, required: true, disabled: editing)
                LabeledField(label: "ラベル", text: $label, required: true)
                Button(editing ? "ラベルを保存" : "保存") { save() }
                    .buttonStyle(.appPrimary)
                if editing {
                    Button("変更をやめる") { reset() }.buttonStyle(.app)
                }
            }
            .frame(width: 380)
        }
    }

    private func save() {
        let err = editing ? vm.renameGroup(id: gid, label: label) : vm.addGroup(id: gid, label: label)
        if let err { vm.message = err; return }
        vm.message = editing ? "ラベルを変更しました" : "グループを追加しました"
        reset()
    }

    private func reset() {
        gid = ""
        label = ""
        editing = false
    }
}

struct TypeEditor: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var typeId = ""
    @State private var name = ""
    @State private var prefix = ""
    @State private var digitsText = "3"
    @State private var mode: StockMode = .counted
    @State private var l1 = ""
    @State private var l2 = ""
    @State private var l3 = ""
    @State private var groupId = ""
    @State private var nextNoText = "1"
    @State private var editingId: String? = nil

    private var previewID: String {
        let d = Int(digitsText) ?? 0
        let n = Int(nextNoText) ?? 0
        guard d >= 1, n >= 1, !prefix.isEmpty else { return "―" }
        let num = String(n)
        return "\(prefix)-" + String(repeating: "0", count: max(0, d - num.count)) + num
    }

    private var locked: Bool { editingId.map { vm.isTypeLocked($0) } ?? false }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Panel(title: "種類一覧") {
                TableRowView(cells: ["種類ID", "表示名", "接頭辞", "桁", "在庫の扱い", "グループ", "next_no"],
                             widths: [90, 140, 60, 40, 110, 110, 70], header: true)
                ForEach(vm.types) { t in
                    HStack(spacing: 6) {
                        TableRowView(cells: [t.typeId, t.name, t.idPrefix, "\(t.idDigits)", t.stockMode.label,
                                             vm.groupLabel(t.groupId), "\(t.nextNo)"],
                                     widths: [90, 140, 60, 40, 110, 110, 70])
                        Button("編集") { load(t) }.buttonStyle(.app).frame(width: 60)
                    }
                }
                Text("編集可（既存）: 表示名・属性ラベル・グループ。種類ID・接頭辞・桁数・在庫の扱いは変更不可。next_no は減らさない。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Panel(title: editingId == nil ? "種類を追加" : "種類を編集") {
                LabeledField(label: "種類ID（半角英数字・_）", text: $typeId, required: true, disabled: editingId != nil)
                LabeledField(label: "表示名", text: $name, required: true)
                HStack {
                    LabeledField(label: "ID接頭辞（種類間で一意）", text: $prefix, required: true, disabled: editingId != nil)
                    LabeledField(label: "ID桁数", text: $digitsText, required: true, disabled: editingId != nil)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("在庫の扱い").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $mode) {
                        ForEach(StockMode.allCases, id: \.self) { m in Text(m.label).tag(m) }
                    }
                    .labelsHidden()
                    .disabled(editingId != nil)
                }
                HStack {
                    LabeledField(label: "属性ラベル1", text: $l1)
                    LabeledField(label: "属性ラベル2", text: $l2)
                    LabeledField(label: "属性ラベル3", text: $l3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("所属グループ").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $groupId) {
                        Text("（なし）").tag("")
                        ForEach(vm.groups) { g in Text(g.label).tag(g.groupId) }
                    }
                    .labelsHidden()
                }
                LabeledField(label: "開始番号 next_no（任意）", text: $nextNoText, disabled: editingId != nil)
                InfoBox(text: "ID形式プレビュー: \(previewID)", size: 14, tint: .yellow)
                Button("保存") { save() }.buttonStyle(.appPrimary)
                if editingId != nil {
                    Button("編集をやめる") { reset() }.buttonStyle(.app)
                }
            }
            .frame(width: 440)
        }
    }

    private func load(_ t: ProductType) {
        editingId = t.typeId
        typeId = t.typeId
        name = t.name
        prefix = t.idPrefix
        digitsText = "\(t.idDigits)"
        mode = t.stockMode
        l1 = t.attrLabel1 ?? ""
        l2 = t.attrLabel2 ?? ""
        l3 = t.attrLabel3 ?? ""
        groupId = t.groupId ?? ""
        nextNoText = "\(t.nextNo)"
    }

    private func save() {
        let err: String?
        if let id = editingId {
            err = vm.updateType(typeId: id, name: name, labels: [l1, l2, l3], groupId: groupId)
        } else {
            err = vm.addType(typeId: typeId, name: name, prefix: prefix, digits: Int(digitsText) ?? 0, mode: mode,
                             labels: [l1, l2, l3], groupId: groupId, nextNo: Int(nextNoText) ?? 0)
        }
        if let err { vm.message = err; return }
        vm.message = editingId == nil ? "種類を追加しました" : "種類を更新しました"
        reset()
    }

    private func reset() {
        editingId = nil
        typeId = ""
        name = ""
        prefix = ""
        digitsText = "3"
        mode = .counted
        l1 = ""
        l2 = ""
        l3 = ""
        groupId = ""
        nextNoText = "1"
    }
}

struct ProductEditor: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var typeId = ""
    @State private var name = ""
    @State private var priceText = ""
    @State private var satsText = ""
    @State private var a1 = ""
    @State private var a2 = ""
    @State private var a3 = ""
    @State private var stockText = "0"
    @State private var isPublic = true
    @State private var editingId: String? = nil
    @State private var showConfirm = false

    private var type: ProductType? { vm.types.first { $0.typeId == typeId } }
    private var priceJpy: Int? {
        guard let v = Int(priceText), v >= 1 else { return nil }
        return v
    }
    private var priceSats: Int? {
        guard let v = Int(satsText), v >= 1 else { return nil }
        return v
    }
    private var stockVal: Int? {
        guard let t = type, t.stockMode != StockMode.none else { return nil }
        return Int(stockText)
    }

    private var idPreview: String {
        if let id = editingId { return id }
        guard let t = type else { return "―" }
        return IdSequencer().makeProductID(for: t) ?? "桁数超過"
    }

    private var canSubmit: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, priceJpy != nil else { return false }
        if !satsText.isEmpty && priceSats == nil { return false }
        if editingId == nil, let t = type, t.stockMode != StockMode.none, stockVal == nil { return false }
        return true
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            listPanel
            formPanel.frame(width: 480)
        }
        .onAppear { if typeId.isEmpty { typeId = vm.types.first?.typeId ?? "" } }
        .sheet(isPresented: $showConfirm) {
            ProductConfirmSheet(
                priceJpy: priceJpy ?? 0,
                priceSats: priceSats,
                rows: confirmRows,
                editing: editingId != nil,
                onBack: { showConfirm = false },
                onConfirm: { continuous in commit(continuous: continuous) }
            )
        }
    }

    private var listPanel: some View {
        Panel(title: "商品一覧") {
            TableRowView(cells: ["商品ID", "種類", "商品名", "円", "sats", "在庫", "公開"],
                         widths: [70, 130, 150, 60, 60, 50, 50], header: true)
            ForEach(vm.inventory) { p in
                HStack(spacing: 6) {
                    TableRowView(cells: [p.id, vm.typeName(p.typeId), p.name, "\(p.priceJpy)",
                                         p.priceSats.map { "\($0)" } ?? "",
                                         p.stock.map { "\($0)" } ?? "―", p.isPublic ? "1" : "0"],
                                 widths: [70, 130, 150, 60, 60, 50, 50])
                    Button("編集") { load(p) }.buttonStyle(.app).frame(width: 60)
                }
            }
            HStack(spacing: 8) {
                Button("CSV取り込み") { vm.go(.csvImport) }.buttonStyle(.app)
                Button("CSV書き出し") { vm.dialog = .message("CSV書き出し（スタブ）") }.buttonStyle(.app)
                Button("価格一覧CSV") { vm.go(.priceList) }.buttonStyle(.app)
                Button("画像なしID一覧") { vm.go(.priceList) }.buttonStyle(.app)
            }
            Text("既存商品の編集可: 名前・円価格・sats価格・属性・公開状態。変更不可: 商品ID・種類。在庫は手動在庫調整。商品の削除なし（非公開・在庫0で代替）。")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var formPanel: some View {
        Panel(title: editingId == nil ? "商品を追加" : "商品を編集") {
            VStack(alignment: .leading, spacing: 2) {
                Text("種類 *").font(.caption).foregroundColor(.secondary)
                Picker("", selection: $typeId) {
                    ForEach(vm.types) { t in Text(t.name).tag(t.typeId) }
                }
                .labelsHidden()
                .disabled(editingId != nil)
            }
            LabeledField(label: "商品名", text: $name, required: true)
            HStack {
                LabeledField(label: "円価格", text: $priceText, required: true)
                LabeledField(label: "sats価格（任意）", text: $satsText)
            }
            HStack {
                LabeledField(label: "属性1（ラベル: \(type?.attrLabel1 ?? "未設定")）", text: $a1, disabled: type?.attrLabel1 == nil)
                LabeledField(label: "属性2（ラベル: \(type?.attrLabel2 ?? "未設定")）", text: $a2, disabled: type?.attrLabel2 == nil)
            }
            LabeledField(label: "属性3（ラベル: \(type?.attrLabel3 ?? "未設定")）", text: $a3, disabled: type?.attrLabel3 == nil)
            HStack(alignment: .bottom) {
                LabeledField(label: stockLabel, text: $stockText, disabled: editingId != nil || type?.stockMode == StockMode.none)
                Toggle("公開", isOn: $isPublic)
            }
            InfoBox(text: "採番: \(idPreview)", size: 14, tint: .yellow)
            Button("確認へ") { showConfirm = true }
                .buttonStyle(.appPrimary)
                .frame(height: 48)
                .disabled(!canSubmit)
            if editingId != nil {
                Button("編集をやめる") { reset(keepType: true) }.buttonStyle(.app)
            }
        }
    }

    private var stockLabel: String {
        switch type?.stockMode {
        case .some(.counted): return "初期在庫（0以上）"
        case .some(.unique): return "初期在庫（0または1）"
        case .some(.none): return "初期在庫（入力なし）"
        case nil: return "初期在庫"
        }
    }

    private var confirmRows: [(String, String)] {
        [
            ("商品ID", idPreview),
            ("種類", type?.name ?? "―"),
            ("グループ", vm.groupLabel(type?.groupId)),
            ("商品名", name),
            ("属性", attrSummary),
            ("初期在庫", editingId != nil ? "（変更なし）" : (stockVal.map { "\($0)" } ?? "―")),
            ("公開状態", isPublic ? "公開" : "非公開"),
            ("画像", "なし（文字表示）")
        ]
    }

    private var attrSummary: String {
        guard let t = type else { return "" }
        let labels = [t.attrLabel1, t.attrLabel2, t.attrLabel3]
        let values = [a1, a2, a3]
        var parts: [String] = []
        for i in 0..<3 {
            if let l = labels[i], !values[i].isEmpty { parts.append("\(l):\(values[i])") }
        }
        return parts.joined(separator: " ")
    }

    private func load(_ p: Product) {
        editingId = p.id
        typeId = p.typeId
        name = p.name
        priceText = "\(p.priceJpy)"
        satsText = p.priceSats.map { "\($0)" } ?? ""
        a1 = p.attr1 ?? ""
        a2 = p.attr2 ?? ""
        a3 = p.attr3 ?? ""
        isPublic = p.isPublic
    }

    private func commit(continuous: Bool) {
        guard let jpy = priceJpy else { return }
        let attrs: [String?] = [a1, a2, a3].map { $0.isEmpty ? nil : $0 }
        let err: String?
        if let id = editingId {
            err = vm.updateProduct(id: id, name: name, priceJpy: jpy, priceSats: priceSats, attrs: attrs, isPublic: isPublic)
        } else {
            err = vm.addProduct(typeId: typeId, name: name, priceJpy: jpy, priceSats: priceSats,
                                attrs: attrs, stock: stockVal, isPublic: isPublic)
        }
        if let err {
            vm.message = err
            showConfirm = false
            return
        }
        vm.message = editingId == nil ? "商品を追加しました" : "商品を更新しました"
        showConfirm = false
        reset(keepType: continuous)
    }

    private func reset(keepType: Bool) {
        editingId = nil
        name = ""
        priceText = ""
        satsText = ""
        a1 = ""
        a2 = ""
        a3 = ""
        stockText = "0"
        isPublic = true
        if !keepType { typeId = vm.types.first?.typeId ?? "" }
    }
}

struct ProductConfirmSheet: View {
    let priceJpy: Int
    let priceSats: Int?
    let rows: [(String, String)]
    let editing: Bool
    let onBack: () -> Void
    let onConfirm: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editing ? "商品編集の確認" : "商品追加の確認").font(.headline)
            InfoBox(text: Fmt.yen(priceJpy), size: 44)
            InfoBox(text: priceSats.map { Fmt.sats($0) } ?? "sats単価なし", size: 22, tint: .yellow)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                TableRowView(cells: [r.0, r.1], widths: [140, 380])
            }
            Spacer()
            HStack(spacing: 10) {
                Button("戻る") { onBack() }.buttonStyle(.app)
                Button(editing ? "確定して更新" : "確定して追加") { onConfirm(false) }.buttonStyle(.appPrimary)
                if !editing {
                    Button("確定して連続追加") { onConfirm(true) }.buttonStyle(.app)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 640)
    }
}

// MARK: - CSV取り込み

struct CSVError: Identifiable {
    let id = UUID()
    let row: Int
    let column: String
    let reason: String
}

struct CSVImportView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var files = ["", "", ""]
    @State private var overwriteStock = false
    @State private var errors: [CSVError] = [
        CSVError(row: 12, column: "product_id", reason: "接頭辞・桁数が種類と一致しない"),
        CSVError(row: 15, column: "product_id", reason: "next_no 未満の新規ID（欠番の再利用）"),
        CSVError(row: 21, column: "stock", reason: "unique の範囲外（0または1）")
    ]

    private let titles = ["① グループ定義CSV", "② 種類定義CSV", "③ 商品マスタCSV"]
    private let samples = ["groups.csv", "types.csv", "products.csv"]

    var body: some View {
        AdminShell("CSV取り込み") {
            VStack(alignment: .leading, spacing: 14) {
                Text("取り込み順序: グループ → 種類 → 商品").font(.headline)
                HStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { i in
                        Panel(title: titles[i]) {
                            Text(files[i].isEmpty ? "（未選択）" : files[i]).foregroundColor(.secondary)
                            Button("ファイルを選択") { files[i] = samples[i] }.buttonStyle(.app)
                        }
                    }
                }
                Toggle("既存商品の在庫をCSVの値で上書きする（明示選択時のみ。在庫管理なし型は対象外）", isOn: $overwriteStock)
                Text("検証結果（1行でもエラーがあれば全体を取り込まない）").font(.headline)
                TableRowView(cells: ["行番号", "列名", "理由"], widths: [80, 160, 460], header: true)
                ForEach(errors) { e in
                    TableRowView(cells: ["\(e.row)", e.column, e.reason], widths: [80, 160, 460])
                }
                if errors.isEmpty { Text("エラーなし").foregroundColor(.secondary) }
                if overwriteStock {
                    Text("在庫上書きの差分一覧（確認ダイアログを経て adjust で記録）").font(.headline)
                    TableRowView(cells: ["商品ID", "現在庫", "CSV値", "差分"], widths: [120, 100, 100, 100], header: true)
                    TableRowView(cells: ["MK-001", "12", "10", "-2"], widths: [120, 100, 100, 100])
                    TableRowView(cells: ["MK-002", "8", "5", "-3"], widths: [120, 100, 100, 100])
                }
                HStack(spacing: 10) {
                    Button("検証エラーを消す（スタブ）") { errors = [] }.buttonStyle(.app)
                    Button("取り込み実行") { vm.message = "取り込み（スタブ）" }
                        .buttonStyle(.appPrimary)
                        .disabled(!errors.isEmpty)
                    Button("キャンセル") { vm.exitAdmin() }.buttonStyle(.app)
                }
                .frame(width: 640)
            }
        }
    }
}

// MARK: - 集計

struct ReportView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var start = Date()
    @State private var end = Date()
    @State private var reserve = ""
    @State private var actual = ""

    private var completed: [Sale] { vm.completedSales(from: start, to: end) }
    private var cashSales: Int {
        completed.filter { $0.method == .cash || $0.method == .mixed }.reduce(0) { $0 + ($1.totalJpy ?? 0) }
    }
    private var satsSales: Int {
        completed.filter { $0.method == .lightning || $0.method == .mixed }.reduce(0) { $0 + ($1.totalSats ?? 0) }
    }
    private var mixedCount: Int { completed.filter { $0.method == .mixed }.count }
    private var voided: [Sale] { vm.voidedSales(from: start, to: end, confirmedOnly: false) }
    private var aborted: [Sale] { vm.voidedSales(from: start, to: end, confirmedOnly: true) }

    var body: some View {
        AdminShell("集計") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    DatePicker("開始日", selection: $start, displayedComponents: .date)
                    DatePicker("終了日", selection: $end, displayedComponents: .date)
                }
                .frame(width: 560)
                Text("グループ別（精算単位）").font(.headline)
                TableRowView(cells: ["グループ", "区分", "種類", "paid_in", "明細数", "数量", "金額"],
                             widths: [200, 60, 140, 70, 70, 60, 120], header: true)
                let rows = vm.reportRows(from: start, to: end)
                ForEach(rows) { r in
                    TableRowView(cells: [r.groupLabel, r.kind, r.typeName, r.paidIn.rawValue, "\(r.lines)", "\(r.qty)",
                                         r.paidIn == .sats ? Fmt.sats(r.amount) : Fmt.yen(r.amount)],
                                 widths: [200, 60, 140, 70, 70, 60, 120])
                }
                if rows.isEmpty { Text("対象の売上なし").foregroundColor(.secondary) }
                HStack(alignment: .top, spacing: 12) {
                    Panel(title: "売上（completed）") {
                        Text("会計 \(completed.count)件\n精算額に算入")
                    }
                    Panel(title: "販売取消（別枠）") {
                        Text("\(voided.count)件\n算入しない")
                    }
                    Panel(title: "sats確認済み中断（別枠）") {
                        Text("\(aborted.count)件 / sats合計 \(Fmt.sats(aborted.reduce(0) { $0 + ($1.totalSats ?? 0) }))\n算入しない")
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    Panel(title: "受取方法別集計") {
                        Text("現金: \(Fmt.yen(cashSales))（現金決済＋併用の現金分）")
                        Text("sats: \(Fmt.sats(satsSales))")
                        Text("併用会計の会計数: \(mixedCount)")
                    }
                    Panel(title: "現金照合（日ごと）") {
                        LabeledField(label: "釣銭準備金（円）", text: $reserve)
                        LabeledField(label: "実残高（円）", text: $actual)
                        Text("差額: " + diffText)
                    }
                }
                HStack(spacing: 10) {
                    Button("sats照合一覧") { vm.go(.salesHistory) }.buttonStyle(.app)
                    Button("グループ別精算CSV（PIN）") {
                        vm.requirePin("グループ別精算CSV") { vm.dialog = .message("精算CSV出力（スタブ）") }
                    }.buttonStyle(.app)
                    Button("販売・在庫エクスポート（PIN）") {
                        vm.requirePin("エクスポート") { vm.dialog = .message("エクスポート（スタブ）") }
                    }.buttonStyle(.app)
                    Button("販売履歴・取消") { vm.go(.salesHistory) }.buttonStyle(.app)
                }
                Text("「グループなし」に売上がある場合、営業終了時に内訳（野良の品名・金額）を確認。円とsatsは合算しない。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var diffText: String {
        guard let r = Int(reserve), let a = Int(actual) else { return "―" }
        return Fmt.yen(a - (r + cashSales))
    }
}

// MARK: - 販売履歴・取消

struct SalesHistoryView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        AdminShell("販売履歴") {
            VStack(alignment: .leading, spacing: 10) {
                TableRowView(cells: ["販売ID", "状態", "方法", "円", "sats", "完了 / 確認時刻", "返金済み"],
                             widths: [170, 90, 100, 80, 90, 170, 80], header: true)
                if vm.sales.isEmpty { Text("記録なし").foregroundColor(.secondary) }
                ForEach(vm.sales.reversed()) { s in
                    HStack(spacing: 6) {
                        TableRowView(cells: [s.id, s.status.rawValue, s.method.rawValue,
                                             s.totalJpy.map { Fmt.num($0) } ?? "―",
                                             s.totalSats.map { Fmt.num($0) } ?? "―",
                                             s.completedAt == nil ? "確認 " + Fmt.time(s.confirmedAt) + "（中断）" : Fmt.time(s.completedAt),
                                             s.refunded ? "済" : "―"],
                                     widths: [170, 90, 100, 80, 90, 170, 80])
                        Button("取消（PIN）") {
                            vm.dialogPin = ""
                            vm.dialog = .voidSale(s.id)
                        }
                        .buttonStyle(.app).frame(width: 110)
                        .disabled(s.status != .completed)
                        Button("返金済み設定（PIN）") {
                            vm.requirePin("返金済み設定") { vm.toggleRefunded(s.id) }
                        }
                        .buttonStyle(.app).frame(width: 160)
                        .disabled(s.totalSats == nil)
                    }
                }
                Text("取消: PIN認証 → 確認ダイアログ → 在庫を戻す（completed_atあり・在庫管理ありの種類のみ）。返金済みフラグはsats分のみ。現金分の返却はシステム外。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 手動在庫調整

struct StockAdjustView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var productId = ""
    @State private var newStockText = ""
    @State private var reason = ""

    private var target: Product? { vm.inventory.first { $0.id == productId } }
    private var managed: [Product] { vm.inventory.filter { vm.managesStock($0) } }

    var body: some View {
        AdminShell("手動在庫調整") {
            HStack(alignment: .top, spacing: 16) {
                Panel(title: "在庫一覧（在庫管理ありのみ）") {
                    TableRowView(cells: ["商品ID", "商品名", "在庫"], widths: [90, 200, 70], header: true)
                    ForEach(managed) { p in
                        TableRowView(cells: [p.id, p.name, p.stock.map { "\($0)" } ?? "―"], widths: [90, 200, 70])
                    }
                }
                Panel(title: "調整") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("対象 *").font(.caption).foregroundColor(.secondary)
                        Picker("", selection: $productId) {
                            ForEach(managed) { p in Text("\(p.id) \(p.name)").tag(p.id) }
                        }
                        .labelsHidden()
                    }
                    Text("現在庫: \(target?.stock.map { "\($0)" } ?? "―")")
                    LabeledField(label: "新しい在庫（counted: 0以上／unique: 0または1）", text: $newStockText, required: true)
                    Text("差分: " + diffText)
                    LabeledField(label: "理由（棚卸し等）", text: $reason, required: true)
                    HStack(spacing: 10) {
                        Button("キャンセル") { vm.exitAdmin() }.buttonStyle(.app)
                        Button("調整を確定（adjust記録）") { commit() }
                            .buttonStyle(.appPrimary)
                            .disabled(Int(newStockText) == nil || reason.isEmpty)
                    }
                }
                .frame(width: 440)
            }
        }
        .onAppear { if productId.isEmpty { productId = managed.first?.id ?? "" } }
    }

    private var diffText: String {
        guard let n = Int(newStockText), let cur = target?.stock else { return "―" }
        let d = n - cur
        return d >= 0 ? "+\(d)" : "\(d)"
    }

    private func commit() {
        guard let n = Int(newStockText) else { return }
        if let err = vm.adjustStock(productId: productId, newStock: n, reason: reason) {
            vm.message = err
            return
        }
        vm.message = "在庫を調整しました: \(productId) → \(n)"
        newStockText = ""
        reason = ""
    }
}

// MARK: - 価格一覧・画像なしID一覧

struct PriceListView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        AdminShell("価格一覧") {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("価格一覧（登録商品のみ・野良は含めない）").font(.headline)
                    TableRowView(cells: ["product_id", "type_id", "name", "price_jpy", "price_sats"],
                                 widths: [90, 100, 180, 80, 90], header: true)
                    ForEach(vm.inventory) { p in
                        TableRowView(cells: [p.id, p.typeId, p.name, "\(p.priceJpy)", p.priceSats.map { "\($0)" } ?? "（空）"],
                                     widths: [90, 100, 180, 80, 90])
                    }
                    Button("価格一覧CSV出力") { vm.dialog = .message("価格一覧CSV出力（スタブ）") }
                        .buttonStyle(.app)
                        .frame(width: 240)
                    Text("おしながきとの照合用。sats価格が空の商品を確認する。").font(.caption).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("画像なしの登録商品ID").font(.headline)
                    TableRowView(cells: ["product_id", "name"], widths: [100, 240], header: true)
                    ForEach(vm.productsWithoutImage) { p in
                        TableRowView(cells: [p.id, p.name], widths: [100, 240])
                    }
                    if vm.productsWithoutImage.isEmpty { Text("なし").foregroundColor(.secondary) }
                }
            }
        }
    }
}

// MARK: - 公開サイト送信・送信ログ

struct SyncView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        AdminShell("公開サイト送信") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    InfoBox(text: "通信: \(vm.isOnline ? "あり" : "なし")　／　最終送信: \(Fmt.time(vm.lastSyncAt))", size: 14, bold: false)
                    Button("公開サイトへ送信") { vm.sendSnapshot() }
                        .buttonStyle(.appPrimary)
                        .frame(width: 240, height: 56)
                    InfoBox(text: "画像の版識別子: a1b2c3d4（仮）", size: 12, bold: false)
                }
                TableRowView(cells: ["id", "at", "result", "detail"], widths: [110, 220, 90, 400], header: true)
                ForEach(vm.syncLog) { l in
                    TableRowView(cells: [l.id, Fmt.dateTime(l.at), l.result.rawValue, l.detail], widths: [110, 220, 90, 400])
                }
                if vm.syncLog.isEmpty { Text("送信ログなし").foregroundColor(.secondary) }
                Text("送信失敗は会計・在庫に影響しない。送信対象は公開商品のスナップショットのみ（グループ・野良・画像データは含めない）。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }
}