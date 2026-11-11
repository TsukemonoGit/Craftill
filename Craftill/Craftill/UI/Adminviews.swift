import SwiftUI
import UniformTypeIdentifiers

// MARK: - 起動時のロック解除

struct LockView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var entered = ""

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("レ ジ").font(.system(size: 34, weight: .bold))
            PinEntryView(pin: $entered, maxLength: 12) {
                if !entered.isEmpty, vm.unlock(entered) { entered = "" }
            }
            .frame(maxWidth: 320)
            HStack(spacing: 12) {
                Button("クリア") { entered = "" }.buttonStyle(.app)
                Button("解除") {
                    if vm.unlock(entered) { entered = "" }
                }
                .buttonStyle(.appPrimary)
                .disabled(entered.isEmpty)
            }
            .frame(maxWidth: 320)
            if !vm.message.isEmpty {
                Text(vm.message).font(.callout).foregroundColor(.red)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.05))
    }
}

// MARK: - 初回起動（PIN未設定）

struct InitialLaunchView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var pin1 = ""
    @State private var pin2 = ""
    @State private var keypadTarget: PinField = .first
    @FocusState private var focusedPin: PinField?

    private enum PinField { case first, second }

    var body: some View {
        VStack(spacing: 0) {
            TopBar("起動", state: "PIN未設定")
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    InfoBox(text: "アプリ起動\nPINが未設定です", size: 22)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PIN").font(.caption).foregroundColor(.secondary)
                        SecureField("PIN", text: $pin1)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedPin, equals: .first)
                            .onSubmit { focusedPin = .second }
                        Text("PIN（確認）").font(.caption).foregroundColor(.secondary)
                        SecureField("PIN（確認）", text: $pin2)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedPin, equals: .second)
                            .onSubmit {
                                if !pin1.isEmpty && !pin2.isEmpty {
                                    vm.setPin(pin1, confirm: pin2)
                                }
                            }
                    }
                    KeypadView(compact: true) { key in
                        switch keypadTarget {
                        case .first: pin1 = updated(pin1, key)
                        case .second: pin2 = updated(pin2, key)
                        }
                        #if os(macOS)
                        focusedPin = keypadTarget
                        #else
                        focusedPin = nil
                        #endif
                    }
                    .frame(maxWidth: 360)
                    Text("キーボードでも、下の数字ボタンでも入力できます。")
                        .font(.caption).foregroundColor(.secondary)
                    Button("PINを設定する") { vm.setPin(pin1, confirm: pin2) }
                        .buttonStyle(.appPrimary)
                        .frame(minHeight: 52)
                        .disabled(pin1.isEmpty || pin2.isEmpty)
                    Button("初期投入（グループ・種類・商品の登録）") { vm.go(.edit) }
                        .buttonStyle(.app)
                        .frame(minHeight: 52)
                    Button("初期投入（CSV取り込み）") { vm.go(.csvImport) }
                        .buttonStyle(.app)
                        .frame(minHeight: 52)
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
                .frame(maxWidth: 680)
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .frame(maxWidth: .infinity)
            }
            MessageBar()
        }
        .onAppear {
            #if os(macOS)
            focusedPin = .first
            #endif
        }
        .onChange(of: focusedPin) { _, newValue in
            if let newValue { keypadTarget = newValue }
        }
    }

    private func updated(_ current: String, _ key: String) -> String {
        if key == "C" { return "" }
        guard current.count + key.count <= 12 else { return current }
        return current + key
    }
}

// MARK: - 機能メニュー

struct MenuView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact

    private struct Item: Identifiable {
        let id: String
        let title: String
        let note: String
        let action: () -> Void
    }

    private struct Section: Identifiable {
        let id: String
        let title: String
        let note: String
        let items: [Item]
    }

    private struct Step {
        let number: String
        let text: String
    }

    private let steps = [
        Step(number: "1", text: "商品を読み取る"),
        Step(number: "2", text: "支払方法を選ぶ"),
        Step(number: "3", text: "会計を確定する")
    ]

    /// 本日の完了会計数（メニューを開いた時点の目安）。
    private var todaySaleCount: Int {
        let now = Date()
        return vm.completedSales(from: now, to: now).count
    }

    private var sections: [Section] {
        [
            Section(id: "daily", title: "会計・集計",
                    note: "レジを閉めたあとの確認・訂正", items: [
                Item(id: "report", title: "集計（日次・期間全体）", note: "表示はPIN不要") {
                    vm.go(.report)
                },
                Item(id: "history", title: "販売履歴・取消", note: "取消・返金済み設定はPIN必須") {
                    vm.go(.salesHistory)
                },
                Item(id: "stock", title: "手動在庫調整", note: "PIN必須") {
                    vm.requirePin("手動在庫調整") { vm.go(.stockAdjust) }
                }
            ]),
            Section(id: "master", title: "商品マスタ",
                    note: "商品が未登録なら、まずここで準備", items: [
                Item(id: "edit", title: "編集（グループ・種類・商品）", note: "待機中のみ・PIN必須") {
                    vm.requirePin("編集") { vm.go(.edit) }
                },
                Item(id: "csv", title: "CSV取り込み・書き出し", note: "取り込みは待機中のみ・PIN必須") {
                    vm.requirePin("CSV取り込み・書き出し") { vm.go(.csvImport) }
                },
                Item(id: "price", title: "価格一覧・画像なしID一覧", note: "") {
                    vm.go(.priceList)
                },
                Item(id: "imageFolder", title: "画像の保存先", note: "撮影・選択した写真を originals/ などへ") {
                    vm.go(.imageFolder)
                },
                Item(id: "qr", title: "商品一覧（QR生成）", note: "商品を選んで任意枚数のQRラベルを印刷") {
                    vm.go(.qrLabels)
                }
            ]),
            Section(id: "maintenance", title: "連携・バックアップ・保守",
                    note: "公開サイトへの送信、CSV出力", items: [
                Item(id: "sync", title: "公開サイトへ送信・送信ログ", note: "") {
                    vm.go(.sync)
                },
                Item(id: "export", title: "エクスポート（販売・在庫・精算CSV）", note: "PIN必須") {
                    vm.requirePin("エクスポート") { vm.exportAll() }
                }
            ]),
            Section(id: "data", title: "データ管理",
                    note: "会計・在庫・全データの初期化とリセット。テストに限らず、運用前の初期化にも使えます", items: [
                Item(id: "dataManagement", title: "データ管理（初期化・リセット）",
                     note: "会計初期化・在庫リセット・全データ初期化・送信ログ削除") {
                    vm.go(.dataManagement)
                }
            ])
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar("機能メニュー", state: vm.saleState.label)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    startCard
                    if vm.inventory.isEmpty { setupHint }
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(section.title).font(.headline)
                                Text(section.note).font(.caption).foregroundColor(.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14)],
                                      alignment: .leading, spacing: 12) {
                                ForEach(section.items) { item in
                                    menuButton(item)
                                }
                            }
                        }
                    }
                    Text("メニューは待機中（カートが空）のみ開けます。PIN必須の操作は実行時にPIN入力します。")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 1100, alignment: .leading)
            }
            MessageBar()
        }
    }

    // MARK: レジ開始カード

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if compact {
                VStack(alignment: .leading, spacing: 10) {
                    startTitle
                    Button("レジを開く") { vm.go(.register) }
                        .buttonStyle(.appPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    startTitle
                    Spacer(minLength: 8)
                    Button("レジを開く") { vm.go(.register) }
                        .buttonStyle(.appPrimary)
                        .frame(minWidth: 140, minHeight: 52)
                }
            }
            stepsRow
            HStack(spacing: 16) {
                Text("商品 \(vm.inventory.count)件")
                Text("本日の会計 \(todaySaleCount)件")
                Text(vm.isOnline ? "通信あり" : "通信なし")
                    .foregroundColor(vm.isOnline ? .secondary : .orange)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.4)))
    }

    private var startTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("レジを開始する").font(.title2.bold())
            Text("商品を読み取って、支払方法を選び、会計を確定します。")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var stepsRow: some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(steps, id: \.number) { step in
                    stepLabel(step)
                }
            }
        } else {
            HStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    stepLabel(step)
                    if index < steps.count - 1 {
                        Image(systemName: "arrow.right").foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func stepLabel(_ step: Step) -> some View {
        HStack(spacing: 6) {
            Text(step.number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(step.text).font(.callout)
        }
    }

    private var setupHint: some View {
        Text("商品がまだ登録されていません。「商品マスタ」の「編集」で登録するか、「CSV取り込み」で読み込んでください。")
            .font(.callout)
            .foregroundColor(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
    }

    private func menuButton(_ item: Item) -> some View {
        Button { item.action() } label: {
            VStack(spacing: 6) {
                Text(item.title).font(.system(size: 16, weight: .bold)).multilineTextAlignment(.center)
                if !item.note.isEmpty {
                    Text(item.note).font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96)
        }
        .buttonStyle(AppButtonStyle(primary: false))
    }
}

// MARK: - 編集（グループ・種類・商品）

struct EditView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case group = "① グループ"
        case type = "② 種類"
        case product = "③ 商品"
        var id: String { rawValue }
    }

    @EnvironmentObject var vm: AppViewModel
    @State private var tab: Tab = .product

    var body: some View {
        AdminShell("商品マスタ編集（待機中）") {
            VStack(alignment: .leading, spacing: 14) {
                structurePanel
                nextStepHint
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                switch tab {
                case .group: GroupEditor()
                case .type: TypeEditor()
                case .product: ProductEditor(onOpenTypes: { tab = .type })
                }
            }
        }
        .onAppear {
            // 種類がないと商品を登録できないので、その場合は種類タブから始める。
            if vm.types.isEmpty { tab = .type }
        }
    }

    // MARK: 説明

    private var structurePanel: some View {
        Panel(title: "商品マスタの構成（グループ → 種類 → 商品）") {
            FieldHelp("レジに並ぶ商品は、この3階層で登録します。上から順に準備してください。")
            VStack(alignment: .leading, spacing: 8) {
                structureRow("1", "グループ", "種類をまとめる見出し（任意）",
                             "例: もの製品")
                structureRow("2", "種類", "商品の分類。IDの付け方と在庫の数え方を決める",
                             "例: ステッカー / 接頭辞 ST / 3桁 / 数量管理")
                structureRow("3", "商品", "実際にレジで売る商品。名前・価格・初期在庫",
                             "例: ステッカー まる / 300円")
            }
            HStack(spacing: 16) {
                Text("登録済み: グループ \(vm.groups.count)件")
                Text("種類 \(vm.types.count)件")
                Text("商品 \(vm.inventory.count)件")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    private func structureRow(_ number: String, _ title: String,
                              _ description: String, _ example: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(title)
                .font(.callout.bold())
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(description).font(.callout)
                Text(example).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var nextStepHint: some View {
        if vm.types.isEmpty {
            hint("次にやること: 「② 種類」を作成してください。グループは任意なので、なくても商品登録に進めます。",
                 color: .orange)
        } else if vm.inventory.isEmpty {
            hint("次にやること: 「③ 商品」で、実際に売る商品を追加してください。",
                 color: .blue)
        }
    }

    private func hint(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.callout)
            .foregroundColor(color)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.1)))
    }
}

struct GroupEditor: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact
    @State private var gid = ""
    @State private var label = ""
    @State private var editing = false

    var body: some View {
        AdaptiveColumns(spacing: 16) {
            Panel(title: "グループ一覧") {
                TableRowView(cells: ["グループID", "ラベル", "使用状況"],
                             widths: [120, 180, 90],
                             header: true,
                             actionWidth: compact ? 0 : 200)
                ForEach(vm.groups) { g in
                    groupRow(g)
                }
                Text("削除: 種類または販売明細から参照されている場合は不可。ラベル変更は過去の集計表示にも反映される。")
                    .font(.caption).foregroundColor(.secondary)
            }
        } second: {
            Panel(title: editing ? "ラベル変更" : "グループを追加") {
                FieldHelp("グループは種類をまとめる見出しです（任意）。例: 「もの製品」の中に「ステッカー」「キーホルダー」を入れます。")
                LabeledField(label: "グループID（半角英数字・_。追加後変更不可）", text: $gid, required: true, disabled: editing)
                FieldHelp("グループIDは内部管理用です。画面や集計に出る名前は「ラベル」です。")
                LabeledField(label: "ラベル", text: $label, required: true)
                Button(editing ? "ラベルを保存" : "保存") { save() }
                    .buttonStyle(.appPrimary)
                if editing {
                    Button("変更をやめる") { reset() }.buttonStyle(.app)
                }
            }
            .frame(maxWidth: compact ? .infinity : 420)
        }
    }

    @ViewBuilder
    private func groupRow(_ g: ProductGroup) -> some View {
        let cells = [g.groupId, g.label, vm.isGroupInUse(g.groupId) ? "使用中" : "未使用"]
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                TableRowView(cells: cells, widths: [120, 180, 90])
                HStack(spacing: 8) {
                    editButton(g)
                    deleteButton(g)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            TableRowView(cells: cells, widths: [120, 180, 90], actionWidth: 200) {
                HStack(spacing: 8) {
                    editButton(g)
                    deleteButton(g)
                }
            }
        }
    }

    private func editButton(_ g: ProductGroup) -> some View {
        Button("ラベル変更") {
            gid = g.groupId
            label = g.label
            editing = true
        }
        .buttonStyle(.app)
        .frame(width: 104)
    }

    private func deleteButton(_ g: ProductGroup) -> some View {
        Button("削除") { vm.deleteGroup(g.groupId) }
            .buttonStyle(.app)
            .frame(width: 80)
            .disabled(vm.isGroupInUse(g.groupId))
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
    @Environment(\.isCompactWidth) private var compact
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

    private var stockModeHelp: String {
        switch mode {
        case .counted:
            return "数量管理型: 同じ商品を何個でも売れます。在庫を数えます（例: ステッカー）。"
        case .unique:
            return "一点物型: 1点だけの商品です。在庫は0か1になります（例: キーホルダー）。"
        case .none:
            return "在庫管理なし型: 在庫を持ちません（例: サービス・手数料）。"
        }
    }

    var body: some View {
        AdaptiveColumns(spacing: 16) {
            Panel(title: "種類一覧") {
                FieldHelp("行の「編集」で内容をフォームに読み込みます。種類を追加すると、その種類の商品を登録できるようになります。")
                TableRowView(cells: ["種類ID", "表示名", "接頭辞", "桁", "在庫の扱い", "グループ", "next_no"],
                             widths: [90, 140, 60, 40, 110, 110, 70],
                             header: true,
                             actionWidth: compact ? 0 : 88)
                ForEach(vm.types) { t in
                    typeRow(t)
                }
                Text("編集可（既存）: 表示名・属性ラベル・グループ。接頭辞・桁数・在庫の扱いは、商品または販売記録がある種類では変更不可。next_no は減らさない。")
                    .font(.caption).foregroundColor(.secondary)
            }
        } second: {
            Panel(title: editingId == nil ? "種類を追加" : "種類を編集") {
                FieldHelp("種類は商品の分類です。商品IDの付け方と、在庫の数え方をここで決めます。")
                LabeledField(label: "種類ID（半角英数字・_）", text: $typeId, required: true, disabled: editingId != nil)
                FieldHelp("種類IDは内部管理用です。レジのタブに出る名前は「表示名」です。グループに関わらず重複できません。")
                LabeledField(label: "表示名", text: $name, required: true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    LabeledField(label: "ID接頭辞（種類間で一意）", text: $prefix, required: true, disabled: locked)
                    LabeledField(label: "ID桁数", text: $digitsText, required: true, disabled: locked)
                }
                FieldHelp("商品IDは「接頭辞-連番」になります。例: 接頭辞 ST・3桁 → ST-001。接頭辞は、グループに関わらず重複できません。")
                VStack(alignment: .leading, spacing: 2) {
                    Text("在庫の扱い").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $mode) {
                        ForEach(StockMode.allCases, id: \.self) { m in Text(m.label).tag(m) }
                    }
                    .labelsHidden()
                    .disabled(locked)
                }
                FieldHelp(stockModeHelp)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                          alignment: .leading, spacing: 8) {
                    LabeledField(label: "属性ラベル1", text: $l1)
                    LabeledField(label: "属性ラベル2", text: $l2)
                    LabeledField(label: "属性ラベル3", text: $l3)
                }
                FieldHelp("属性ラベルは、商品ごとに色・模様などを記録する項目名です。使わない項目は空欄にします。")
                VStack(alignment: .leading, spacing: 2) {
                    Text("所属グループ").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $groupId) {
                        Text("（なし）").tag("")
                        ForEach(vm.groups) { g in Text(g.label).tag(g.groupId) }
                    }
                    .labelsHidden()
                }
                FieldHelp("グループに入れると、レジのタブ名が「グループ｜種類」になります。グループなしでも登録できます。")
                LabeledField(label: "開始番号 next_no（任意）", text: $nextNoText, disabled: editingId != nil)
                FieldHelp("次に発番する番号です。通常は1のままで問題ありません。")
                InfoBox(text: "ID形式プレビュー: \(previewID)", size: 14, tint: .yellow)
                Button("保存") { save() }.buttonStyle(.appPrimary)
                if editingId != nil {
                    Button("編集をやめる") { reset() }.buttonStyle(.app)
                }
            }
            .frame(maxWidth: compact ? .infinity : 480)
        }
    }

    @ViewBuilder
    private func typeRow(_ t: ProductType) -> some View {
        let cells = [t.typeId, t.name, t.idPrefix, "\(t.idDigits)", t.stockMode.label,
                     vm.groupLabel(t.groupId), "\(t.nextNo)"]
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                TableRowView(cells: cells, widths: [90, 140, 60, 40, 110, 110, 70])
                editButton(t)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            TableRowView(cells: cells, widths: [90, 140, 60, 40, 110, 110, 70], actionWidth: 88) {
                editButton(t)
            }
        }
    }

    private func editButton(_ t: ProductType) -> some View {
        Button("編集") { load(t) }
            .buttonStyle(.app)
            .frame(width: 80)
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
            err = vm.updateType(typeId: id, name: name, prefix: prefix, digits: Int(digitsText) ?? 0,
                                mode: mode, labels: [l1, l2, l3], groupId: groupId)
        } else {
            err = vm.createType(typeId: typeId, name: name, prefix: prefix, digits: Int(digitsText) ?? 0, mode: mode,
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
    @Environment(\.isCompactWidth) private var compact
    var onOpenTypes: (() -> Void)? = nil

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
    /// 追加成功後に「次の手順」を出すための商品。確認シートが閉じてから表示する。
    @State private var pendingAdded: Product? = nil
    @State private var addedProduct: Product? = nil
    /// 編集中に選んだ写真。確定時に ProductImageStore へ保存する。
    @State private var pendingImageData: Data? = nil
    @State private var removeImage = false
    @State private var searchText = ""
    @State private var filterTypeId = ""
    @State private var showSatsBulk = false

    init(onOpenTypes: (() -> Void)? = nil) {
        self.onOpenTypes = onOpenTypes
    }

    private var type: ProductType? { vm.types.first { $0.typeId == typeId } }
    private var currentProduct: Product? {
        editingId.flatMap { id in vm.inventory.first { $0.id == id } }
    }

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

    /// 写真の保存名。既存商品は `image_ref` を尊重し、新規は商品IDから導出する。
    private var imageFileName: String {
        if let id = editingId, let p = vm.inventory.first(where: { $0.id == id }) {
            return p.bundledImageName
        }
        return "\(idPreview).jpg"
    }

    private var isImageNameAvailable: Bool {
        idPreview != "―" && idPreview != "桁数超過"
    }

    private var idPreviewColor: Color {
        isImageNameAvailable ? .accentColor : .orange
    }

    private var currentStockText: String {
        guard let p = currentProduct, let stock = p.stock else { return "―" }
        return "\(stock)"
    }

    private var validationHint: String? {
        if type == nil { return "種類を選んでください。" }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "商品名を入力してください。"
        }
        if priceJpy == nil { return "円価格は1以上の整数で入力してください。" }
        if !satsText.isEmpty && priceSats == nil {
            return "sats価格は空欄か1以上の整数で入力してください。"
        }
        if let msg = stockValidationMessage { return msg }
        return nil
    }

    private var stockValidationMessage: String? {
        guard editingId == nil, let t = type else { return nil }
        switch t.stockMode {
        case .counted:
            guard let s = stockVal, s >= 0 else {
                return "初期在庫は0以上の整数で入力してください。"
            }
        case .unique:
            guard let s = stockVal, s == 0 || s == 1 else {
                return "一点物型の初期在庫は0または1です。"
            }
        case .none:
            break
        }
        return nil
    }

    private var canSubmit: Bool { validationHint == nil }

    private var stockLabel: String {
        switch type?.stockMode {
        case .some(.counted): return "初期在庫（0以上）"
        case .some(.unique): return "初期在庫（0または1）"
        case .some(.none): return "初期在庫（入力なし）"
        case nil: return "初期在庫"
        }
    }

    private var stockModeHelp: String {
        switch type?.stockMode {
        case .some(.counted):
            return "数量管理型: 同じ商品を何個でも販売でき、在庫を1個ずつ減らします。"
        case .some(.unique):
            return "一点物型: 1点限りの商品です。在庫は0か1で、同じ会計に2つ入れられません。"
        case .some(.none):
            return "在庫管理なし型: 在庫を持たず、販売しても在庫は減りません。"
        case nil:
            return "種類を選ぶと在庫の扱いが表示されます。"
        }
    }

    private var imageStatus: String {
        if pendingImageData != nil { return "追加・変更あり" }
        if removeImage { return "削除" }
        let exists = ProductImageStore.hasRuntimeImage(fileName: imageFileName)
            || bundledImageURL(named: imageFileName) != nil
        return exists ? "あり" : "なし"
    }

    private var filteredInventory: [Product] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return vm.inventory.filter { p in
            (filterTypeId.isEmpty || p.typeId == filterTypeId)
                && (query.isEmpty
                    || p.name.localizedCaseInsensitiveContains(query)
                    || p.id.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        AdaptiveColumns(spacing: 16) {
            listPanel
        } second: {
            formPanel.frame(maxWidth: compact ? .infinity : 560)
        }
        .onAppear {
            if typeId.isEmpty { typeId = vm.types.first?.typeId ?? "" }
        }
        .onChange(of: typeId) { _, _ in
            // 種類を変えたとき、新しい種類に存在しない属性値を残さない。
            guard editingId == nil else { return }
            if type?.attrLabel1 == nil { a1 = "" }
            if type?.attrLabel2 == nil { a2 = "" }
            if type?.attrLabel3 == nil { a3 = "" }
            if type?.stockMode == StockMode.none { stockText = "0" }
            if type?.stockMode == StockMode.unique, let s = Int(stockText), s > 1 {
                stockText = "1"
            }
        }
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
        .onChange(of: showConfirm) { _, showing in
            // 確認シートが閉じきる前に次のシートを出すと無視されることがあるため、少し待つ。
            guard !showing, let added = pendingAdded else { return }
            pendingAdded = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                addedProduct = added
            }
        }
        .sheet(item: $addedProduct) { product in
            ProductRegisteredSheet(product: product) {
                vm.qrFocusProductId = product.id
                vm.go(.qrLabels)
            }
        }
        .sheet(isPresented: $showSatsBulk) {
            SatsBulkPriceSheet(initialTypeId: typeId) { changed in
                // 編集中の商品が一括設定の対象なら、フォームのsats欄も新しい値にする。
                // 古い値のまま「更新」を押して、一括設定を上書きしないため。
                guard let id = editingId,
                      let updated = changed.first(where: { $0.id == id }) else { return }
                satsText = updated.priceSats.map { "\($0)" } ?? ""
            }
            .environmentObject(vm)
        }
    }

    // MARK: 一覧

    private var searchField: some View {
        TextField("商品名・商品IDで検索", text: $searchText)
            .textFieldStyle(.roundedBorder)
    }

    private var typeFilter: some View {
        Picker("", selection: $filterTypeId) {
            Text("すべての種類").tag("")
            ForEach(vm.types) { t in
                Text(vm.tabLabel(t)).tag(t.typeId)
            }
        }
        .labelsHidden()
        .frame(maxWidth: compact ? .infinity : 220)
    }

    private var listTitle: String {
        let total = vm.inventory.count
        if filteredInventory.count == total { return "商品一覧（\(total)件）" }
        return "商品一覧（\(filteredInventory.count) / \(total)件）"
    }

    private var listPanel: some View {
        Panel(title: listTitle) {
            FieldHelp("商品を選ぶとフォームに読み込みます。「写真 ✓」はレジに表示できる画像がある商品です。")
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    searchField
                    typeFilter
                }
            } else {
                HStack(spacing: 8) {
                    searchField
                    typeFilter
                }
            }
            if filteredInventory.isEmpty {
                Text(vm.inventory.isEmpty
                     ? "商品がまだありません。フォームから登録してください。"
                     : "条件に合う商品がありません。検索語や種類を変えてください。")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                TableRowView(cells: ["商品ID", "種類", "商品名", "円", "sats", "在庫", "公開", "写真"],
                             widths: [65, 115, 140, 55, 55, 45, 45, 40],
                             header: true,
                             actionWidth: compact ? 0 : 88)
                ForEach(filteredInventory) { p in
                    productRow(p)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                Button("sats価格を一括設定") { showSatsBulk = true }
                    .buttonStyle(.app)
                    .disabled(vm.inventory.isEmpty)
                Button("CSV取り込み") { vm.go(.csvImport) }.buttonStyle(.app)
                Button("CSV書き出し") { vm.exportMaster() }.buttonStyle(.app)
                Button("価格一覧CSV") { vm.go(.priceList) }.buttonStyle(.app)
                Button("画像なしID一覧") { vm.go(.priceList) }.buttonStyle(.app)
            }
            FieldHelp("「sats価格を一括設定」は、円価格ごとにsats価格をまとめて変更します。空欄の行は変更しません。")
            Text("既存商品の編集可: 名前・円価格・sats価格・属性・公開状態。変更不可: 商品ID・種類。在庫は手動在庫調整。商品の削除なし（非公開・在庫0で代替）。")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func productRow(_ p: Product) -> some View {
        let cells = [p.id, vm.typeName(p.typeId), p.name, "\(p.priceJpy)",
                     p.priceSats.map { "\($0)" } ?? "",
                     p.stock.map { "\($0)" } ?? "―",
                     p.isPublic ? "1" : "0",
                     p.hasDisplayImage ? "✓" : "―"]
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                TableRowView(cells: cells, widths: [65, 115, 140, 55, 55, 45, 45, 40])
                editButton(p)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            TableRowView(cells: cells, widths: [65, 115, 140, 55, 55, 45, 45, 40], actionWidth: 88) {
                editButton(p)
            }
        }
    }

    private func editButton(_ p: Product) -> some View {
        Button("編集") { load(p) }
            .buttonStyle(.app)
            .frame(width: 80)
    }

    // MARK: フォーム

    private var formPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                formHeader
                typeSection
                basicSection
                photoSection
                attributeSection
                stockSection
                submitSection
            }
        }
    }

    private var formHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(editingId == nil ? "商品を追加" : "商品を編集")
                    .font(.title3.bold())
                Spacer(minLength: 8)
                if editingId != nil {
                    Button(compact ? "新規" : "新規商品に切り替え") { reset(keepType: true) }
                        .buttonStyle(.app)
                }
            }
            HStack(spacing: 6) {
                badge(editingId ?? idPreview, color: idPreviewColor)
                if let t = type {
                    badge(t.name, color: .blue)
                }
            }
            if let t = type {
                Text("グループ: \(vm.groupLabel(t.groupId))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            FieldHelp(editingId == nil
                ? "商品IDは選んだ種類の形式で自動採番されます。登録後のID変更はできません。"
                : "商品IDと種類は登録後に変更できません。名前・価格・属性・公開状態を編集できます。")
        }
    }

    @ViewBuilder
    private var typeSection: some View {
        formSection("種類", "商品の分類・ID形式・在庫の扱い") {
            if let id = editingId {
                if let t = type {
                    VStack(alignment: .leading, spacing: 4) {
                        readOnlyRow("商品ID", id)
                        readOnlyRow("種類", t.name)
                        readOnlyRow("グループ", vm.groupLabel(t.groupId))
                    }
                    FieldHelp("商品ID・種類・グループはこの画面では変更できません。")
                } else {
                    Text("種類が見つかりません。商品マスタの整合性を確認してください。")
                        .font(.callout).foregroundColor(.red)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("種類 *").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $typeId) {
                        ForEach(vm.types) { t in
                            Text(vm.tabLabel(t)).tag(t.typeId)
                        }
                    }
                    .labelsHidden()
                    .disabled(vm.types.isEmpty)
                }
                typeSummary
            }
            if vm.types.isEmpty {
                if compact {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("種類が未登録です。先に種類を作成してください。")
                            .font(.callout).foregroundColor(.orange)
                        Button("② 種類を開く") { onOpenTypes?() }
                            .buttonStyle(.app)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text("種類が未登録です。先に種類を作成してください。")
                            .font(.callout).foregroundColor(.orange)
                        Button("② 種類を開く") { onOpenTypes?() }
                            .buttonStyle(.app)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var typeSummary: some View {
        if let t = type {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    badge("ID形式 \(idFormatExample(t))", color: .blue)
                    badge(t.stockMode.label, color: stockColor(t.stockMode))
                }
                Text("属性: \(attrLabelSummary(t))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            FieldHelp("種類を選ぶと、ID形式・在庫の扱い・属性が表示されます。")
        }
    }

    private var basicSection: some View {
        formSection("基本情報", "レジと公開サイトに表示される内容") {
            LabeledField(label: "商品名", text: $name, required: true,
                         placeholder: "例: ステッカー まる")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    LabeledField(label: "円価格", text: $priceText, required: true,
                                 placeholder: "300")
                    if !priceText.isEmpty && priceJpy == nil {
                        validationText("1以上の整数で入力してください")
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    LabeledField(label: "sats価格（任意）", text: $satsText,
                                 placeholder: "空欄可")
                    if !satsText.isEmpty && priceSats == nil {
                        validationText("空欄か1以上の整数で入力してください")
                    }
                }
            }
            FieldHelp("sats価格が空欄の商品は、sats払いでも現金で受け取ります。")
            if let jpy = priceJpy {
                HStack(spacing: 6) {
                    badge("販売価格 \(Fmt.yen(jpy))", color: .green)
                    if let sats = priceSats {
                        badge(Fmt.sats(sats), color: .orange)
                    }
                }
            }
        }
    }

    private var photoSection: some View {
        formSection("商品写真", "任意。レジの商品タイルに表示") {
            if isImageNameAvailable {
                ProductPhotoSection(fileName: imageFileName,
                                    pendingData: $pendingImageData,
                                    removeImage: $removeImage,
                                    showsTitle: false)
            } else {
                FieldHelp("種類を選ぶと、商品IDに合わせたファイル名で写真を保存できます。")
            }
        }
    }

    private var attributeSection: some View {
        formSection("属性", "種類ごとに設定された項目") {
            if let t = type {
                if t.attrLabel1 == nil && t.attrLabel2 == nil && t.attrLabel3 == nil {
                    FieldHelp("この種類には属性がありません。色・模様などを記録する場合は「② 種類」で属性ラベルを追加してください。")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)],
                              alignment: .leading, spacing: 8) {
                        if let l = t.attrLabel1 {
                            LabeledField(label: l, text: $a1, placeholder: "例: 赤")
                        }
                        if let l = t.attrLabel2 {
                            LabeledField(label: l, text: $a2, placeholder: "例: 丸")
                        }
                        if let l = t.attrLabel3 {
                            LabeledField(label: l, text: $a3, placeholder: "例: 大")
                        }
                    }
                    FieldHelp("属性は商品ごとの色・模様などです。空欄でも登録できます。")
                }
            } else {
                FieldHelp("種類を選ぶと属性項目が表示されます。")
            }
        }
    }

    private var stockSection: some View {
        formSection("在庫・公開", "販売時の在庫の扱いと公開サイトへの送信") {
            if let t = type {
                if t.stockMode == StockMode.none {
                    Text("在庫管理なし: 在庫は持ちません。")
                        .font(.callout)
                } else if editingId != nil {
                    readOnlyRow("現在庫", currentStockText)
                    FieldHelp("在庫はこの画面では変更できません。増減は「手動在庫調整」から行います。")
                } else {
                    LabeledField(label: stockLabel, text: $stockText, placeholder: "0")
                    if let msg = stockValidationMessage {
                        validationText(msg)
                    }
                }
                FieldHelp(stockModeHelp)
            }
            Toggle("公開サイトに送信する", isOn: $isPublic)
            FieldHelp("公開すると公開サイトの送信対象になります。非公開でもレジでは販売できます。")
        }
    }

    private var submitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(editingId == nil ? "商品ID（自動）" : "商品ID（変更不可）")
                    .font(.caption).foregroundColor(.secondary)
                Text(idPreview)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(idPreviewColor)
                Text("写真ファイル名: \(imageFileName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.35)))
            if let hint = validationHint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(editingId == nil ? "内容を確認して登録" : "内容を確認して更新") {
                showConfirm = true
            }
            .buttonStyle(.appPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(!canSubmit)
            if editingId != nil {
                Button("編集をやめる") { reset(keepType: true) }
                    .buttonStyle(.app)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 部品

    private func formSection<Content: View>(_ title: String, _ subtitle: String? = nil,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 16)
                    Text(title).font(.callout.bold())
                }
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 11)
                }
            }
            content()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.18)))
    }

    private func badge(_ text: String, color: Color = .gray) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundColor(color)
    }

    private func validationText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func readOnlyRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func idFormatExample(_ t: ProductType) -> String {
        "\(t.idPrefix)-" + String(repeating: "0", count: max(0, t.idDigits - 1)) + "1"
    }

    private func stockColor(_ mode: StockMode) -> Color {
        switch mode {
        case .counted: return .green
        case .unique: return .orange
        case .none: return .gray
        }
    }

    private func attrLabelSummary(_ t: ProductType) -> String {
        let labels = [t.attrLabel1, t.attrLabel2, t.attrLabel3].compactMap { $0 }
        return labels.isEmpty ? "なし" : labels.joined(separator: " / ")
    }

    // MARK: 入出力

    private var confirmRows: [(String, String)] {
        [
            ("商品ID", idPreview),
            ("種類", type?.name ?? "―"),
            ("グループ", vm.groupLabel(type?.groupId)),
            ("商品名", name),
            ("属性", attrSummary.isEmpty ? "なし" : attrSummary),
            ("初期在庫", stockRowValue),
            ("公開状態", isPublic ? "公開" : "非公開"),
            ("画像", imageStatus)
        ]
    }

    private var stockRowValue: String {
        if editingId != nil { return "変更なし（現在 \(currentStockText)）" }
        if type?.stockMode == StockMode.none { return "在庫管理なし" }
        return stockVal.map { "\($0)" } ?? "―"
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
        pendingImageData = nil
        removeImage = false
        editingId = p.id
        typeId = p.typeId
        name = p.name
        priceText = "\(p.priceJpy)"
        satsText = p.priceSats.map { "\($0)" } ?? ""
        a1 = p.attr1 ?? ""
        a2 = p.attr2 ?? ""
        a3 = p.attr3 ?? ""
        stockText = p.stock.map { "\($0)" } ?? "0"
        isPublic = p.isPublic
    }

    private func commit(continuous: Bool) {
        guard let jpy = priceJpy else { return }
        let attrs: [String?] = [a1, a2, a3].map { $0.isEmpty ? nil : $0 }
        let newId = idPreview
        let savedFileName = imageFileName
        let err: String?
        if let id = editingId {
            err = vm.updateProduct(id: id, name: name, priceJpy: jpy, priceSats: priceSats, attrs: attrs, isPublic: isPublic)
        } else {
            err = vm.createProduct(typeId: typeId, name: name, priceJpy: jpy, priceSats: priceSats,
                                attrs: attrs, stock: stockVal, isPublic: isPublic)
        }
        if let err {
            vm.message = err
            showConfirm = false
            return
        }
        vm.message = editingId == nil ? "商品を追加しました" : "商品を更新しました"
        do {
            if let data = pendingImageData {
                try ProductImageStore.save(data, fileName: savedFileName)
            } else if removeImage {
                try ProductImageStore.delete(fileName: savedFileName)
            }
        } catch {
            // 写真の保存に失敗した時は入力と画像データを残し、保存先を直して
            // 確定し直せるようにする（再確定は新規ではなく更新になるよう編集状態にする）。
            if editingId == nil { editingId = newId }
            showConfirm = false
            vm.message = "商品は保存しましたが、写真を保存できませんでした。保存先フォルダを確認して、もう一度確定してください（\(error.localizedDescription)）"
            return
        }
        if editingId == nil {
            pendingAdded = vm.inventory.first { $0.id == newId }
        }
        showConfirm = false
        reset(keepType: continuous)
    }

    private func reset(keepType: Bool) {
        pendingImageData = nil
        removeImage = false
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

// MARK: - sats価格の一括設定

/// 円価格ごとにsats価格をまとめて設定するシート。
/// 例: 100円の商品を1000sats、300円の商品を4000satsに一括で変更する。
/// 空欄の行は変更しない。適用はVM側で1トランザクション（P-02）。
struct SatsBulkPriceSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isCompactWidth) private var compact

    let initialTypeId: String
    let onApplied: ([Product]) -> Void

    @State private var typeId: String
    @State private var satsTexts: [Int: String] = [:]
    @State private var error: String? = nil

    init(initialTypeId: String, onApplied: @escaping ([Product]) -> Void) {
        self.initialTypeId = initialTypeId
        self.onApplied = onApplied
        _typeId = State(initialValue: initialTypeId)
    }

    private var scopedProducts: [Product] {
        vm.inventory.filter { typeId.isEmpty || $0.typeId == typeId }
    }

    private var priceTiers: [Int] {
        Array(Set(scopedProducts.map(\.priceJpy))).sorted()
    }

    private var assignments: [Int: Int] {
        var out: [Int: Int] = [:]
        for (price, text) in satsTexts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let sats = Int(trimmed), sats >= 1 else { continue }
            out[price] = sats
        }
        return out
    }

    private var invalidPrices: [Int] {
        satsTexts.compactMap { price, text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let sats = Int(trimmed), sats >= 1 else { return price }
            return nil
        }
        .sorted()
    }

    private var changes: [SatsPriceChange] {
        vm.previewSatsPriceBulk(assignments: assignments,
                                typeId: typeId.isEmpty ? nil : typeId)
    }

    private var canApply: Bool {
        invalidPrices.isEmpty && !changes.isEmpty && vm.saleState == .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    scopePicker
                    if priceTiers.isEmpty {
                        Text("対象の商品がありません。")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        priceTable
                    }
                    if !invalidPrices.isEmpty {
                        Text("sats価格は1以上の整数で入力してください（\(invalidPrices.map { "\($0)円" }.joined(separator: " / "))）。")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    preview
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(20)
        .frame(minWidth: 300, idealWidth: 680, maxWidth: 820,
               minHeight: 400, idealHeight: 680, maxHeight: 820)
        .onChange(of: typeId) { _, _ in
            // 種類を変えたら、前の種類で入力した値を残さない（同じ円価格の別種類へ誤適用しない）。
            satsTexts = [:]
            error = nil
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("sats価格を一括設定").font(.title3.bold())
                Text("円価格ごとにsats価格をまとめて設定します。空欄の行は変更しません。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Button("閉じる") { dismiss() }.buttonStyle(.app)
        }
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("対象の種類").font(.caption).foregroundColor(.secondary)
            Picker("", selection: $typeId) {
                Text("すべての種類").tag("")
                ForEach(vm.types) { t in
                    Text(vm.tabLabel(t)).tag(t.typeId)
                }
            }
            .labelsHidden()
            .frame(maxWidth: compact ? .infinity : 320)
        }
    }

    @ViewBuilder
    private var priceTable: some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(priceTiers, id: \.self) { price in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(Fmt.yen(price)).font(.callout.bold())
                            Text("\(products(at: price).count)件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                        Text("現在: \(currentSatsSummary(at: price))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("変更しない", text: binding(for: price))
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.18)))
                }
            }
        } else {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    tableHeader("円価格")
                    tableHeader("件数")
                    tableHeader("現在のsats")
                    tableHeader("新しいsats")
                }
                ForEach(priceTiers, id: \.self) { price in
                    GridRow {
                        Text(Fmt.yen(price)).font(.callout)
                        Text("\(products(at: price).count)件").font(.callout)
                        Text(currentSatsSummary(at: price)).font(.callout)
                        TextField("変更しない", text: binding(for: price))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("更新内容").font(.headline)
                Spacer(minLength: 8)
                Text(changes.isEmpty ? "変更なし" : "\(changes.count)件")
                    .font(.callout.bold())
                    .foregroundColor(changes.isEmpty ? .secondary : .orange)
            }
            if changes.isEmpty {
                Text(satsTexts.isEmpty
                     ? "sats価格を入力すると、更新内容がここに表示されます。"
                     : "入力したsats価格が現在値と同じか、対象の商品がありません。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(changes.prefix(50)) { change in
                        HStack(spacing: 8) {
                            Text(change.product.id)
                                .font(.system(.caption, design: .monospaced))
                            Text(change.product.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(change.oldSats.map { Fmt.sats($0) } ?? "空欄") → \(Fmt.sats(change.newSats))")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    if changes.count > 50 {
                        Text("他 \(changes.count - 50)件")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("キャンセル") { dismiss() }.buttonStyle(.app)
            Spacer(minLength: 8)
            if vm.saleState != .idle {
                Text("会計中は変更できません")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            Button(changes.isEmpty ? "更新" : "\(changes.count)件を更新") { apply() }
                .buttonStyle(.appPrimary)
                .disabled(!canApply)
        }
    }

    private func products(at price: Int) -> [Product] {
        scopedProducts.filter { $0.priceJpy == price }
    }

    private func currentSatsSummary(at price: Int) -> String {
        let items = products(at: price)
        let values = Set(items.compactMap(\.priceSats)).sorted()
        let hasEmpty = items.contains { $0.priceSats == nil }
        if values.isEmpty { return "空欄" }
        let parts = values.prefix(3).map { Fmt.sats($0) } + (hasEmpty ? ["空欄"] : [])
        if values.count > 3 || parts.count > 3 { return "混在" }
        if parts.count == 1 { return parts[0] }
        return "混在（\(parts.joined(separator: " / "))）"
    }

    private func binding(for price: Int) -> Binding<String> {
        Binding(
            get: { satsTexts[price] ?? "" },
            set: { satsTexts[price] = $0 }
        )
    }

    private func tableHeader(_ text: String) -> some View {
        Text(text).font(.caption.bold()).foregroundColor(.secondary)
    }

    private func apply() {
        error = nil
        let planned = changes
        guard !planned.isEmpty else {
            error = "変更はありません"
            return
        }
        if let message = vm.applySatsPriceBulk(assignments: assignments,
                                               typeId: typeId.isEmpty ? nil : typeId) {
            error = message
            return
        }
        let ids = Set(planned.map(\.product.id))
        onApplied(vm.inventory.filter { ids.contains($0.id) })
        dismiss()
    }
}

struct ProductConfirmSheet: View {
    @Environment(\.isCompactWidth) private var compact
    let priceJpy: Int
    let priceSats: Int?
    let rows: [(String, String)]
    let editing: Bool
    let onBack: () -> Void
    let onConfirm: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(editing ? "商品編集の確認" : "商品追加の確認").font(.headline)
                    InfoBox(text: Fmt.yen(priceJpy), size: 44)
                    InfoBox(text: priceSats.map { Fmt.sats($0) } ?? "sats単価なし", size: 22, tint: .yellow)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        TableRowView(cells: [r.0, r.1], widths: [140, 380])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if compact {
                VStack(spacing: 8) {
                    confirmButtons
                }
            } else {
                HStack(spacing: 10) {
                    confirmButtons
                }
            }
        }
        .padding(20)
        .frame(minWidth: 300, idealWidth: 560, maxWidth: 720, minHeight: 360, idealHeight: 640, maxHeight: 800)
    }

    @ViewBuilder
    private var confirmButtons: some View {
        Button("戻る") { onBack() }.buttonStyle(.app)
        Button(editing ? "確定して更新" : "確定して追加") { onConfirm(false) }.buttonStyle(.appPrimary)
        if !editing {
            Button("確定して連続追加") { onConfirm(true) }.buttonStyle(.app)
        }
    }
}

// MARK: - 商品登録直後の案内

/// 商品を追加した直後に、QR印刷 → 写真 → Web用画像のコピーの順番を案内する。
/// 写真は編集画面から登録でき、「画像の保存先」で選んだフォルダに
/// 商品IDのファイル名で保存されることを明示する。
struct ProductRegisteredSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isCompactWidth) private var compact
    let product: Product
    let onQR: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("商品を登録しました").font(.title3.bold())
            HStack(spacing: 12) {
                InfoBox(text: product.id, size: 30, tint: .green)
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name).font(.headline)
                    Text("公開サイト用の写真名: \(product.id).jpg")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Panel(title: "このあとの手順") {
                stepRow("1", "QRラベルを印刷して、この商品に貼る")
                if product.hasRuntimeImage {
                     stepRow("2", "写真は保存先フォルダに登録済みです（レジの商品タイルに表示されます）")
                } else {
                    stepRow("2", "商品を編集して「商品写真」から撮影・選択する（あとからでも追加できます）")
                }
                if product.hasRuntimeImage {
                     stepRow("3", "保存先フォルダの \(product.id).jpg を、Webの static/images へコピーする")
                     FieldHelp("Web用は、保存先フォルダの \(product.id).jpg を web/flea-inventory-view/static/images へ手動でコピーしてください。")
                 } else {
                     stepRow("3", "写真を保存したあと、保存先フォルダの \(product.id).jpg を、Webの static/images へコピーする")
                     FieldHelp("保存先フォルダに \(product.id).jpg がまだありません。先に商品編集で写真を保存してから、Web用にコピーしてください。")
                 }
            }
            Text("登録した商品IDは変更できません。QRラベルと写真のファイル名は、このIDに合わせてください。")
                .font(.caption)
                .foregroundColor(.secondary)
            if compact {
                VStack(spacing: 8) { buttons }
            } else {
                HStack(spacing: 10) { buttons }
            }
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 620, maxWidth: 760,
               minHeight: 420, idealHeight: 560, maxHeight: 700)
    }

    @ViewBuilder
    private var buttons: some View {
        Button("QRラベルを開く") {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onQR() }
        }
        .buttonStyle(.appPrimary)
        Button("続けて登録") { dismiss() }
            .buttonStyle(.app)
    }

    private func stepRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - CSV取り込み

struct CSVImportView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact
    @State private var tables: [CSVTable?] = [nil, nil, nil]
    @State private var names = ["", "", ""]
    @State private var overwriteStock = false
    @State private var errors: [CSVError] = []
    @State private var plan: CSVImportPlan?

    @State private var showImporter = false
    @State private var importSlot: Int?
    @State private var showConfirm = false

    private let titles = ["① グループ定義CSV", "② 種類定義CSV", "③ 商品マスタCSV"]
    private let hints = [
        "group_id, label",
        "type_id, name, id_prefix, id_digits, stock_mode, …",
        "product_id, type_id, name, price_jpy, stock, is_public, …"
    ]

    var body: some View {
        AdminShell("CSV取り込み") {
            VStack(alignment: .leading, spacing: 14) {
                Text("取り込み順序: グループ → 種類 → 商品").font(.headline)
                Text("列の順序は自由です。1行でもエラーがあれば、DBと画面のデータは一切変更しません。")
                    .font(.caption).foregroundColor(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14),
                                         count: compact ? 1 : 3),
                          alignment: .leading, spacing: 14) {
                    ForEach(0..<3, id: \.self) { i in
                        Panel(title: titles[i]) {
                            Text(names[i].isEmpty ? "（未選択）" : names[i])
                                .font(.callout)
                                .lineLimit(2)
                                .foregroundColor(names[i].isEmpty ? .secondary : .primary)
                            Text(hints[i])
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                            HStack(spacing: 8) {
                                Button("ファイルを選択") {
                                    importSlot = i
                                    showImporter = true
                                }
                                .buttonStyle(.app)
                                if !names[i].isEmpty {
                                    Button("クリア") { clear(i) }
                                        .buttonStyle(.app)
                                }
                            }
                        }
                    }
                }

                Toggle("既存商品の在庫をCSVの値で上書きする（明示選択時のみ。在庫管理なし型は対象外）",
                       isOn: $overwriteStock)
                    .onChange(of: overwriteStock) { _, _ in validate() }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                         count: compact ? 1 : 4),
                          alignment: .leading, spacing: 10) {
                    Button("再検証") { validate() }.buttonStyle(.app)
                    Button("取り込み実行") { showConfirm = true }
                        .buttonStyle(.appPrimary)
                        .disabled(!canImport)
                    Button("空のCSV雛形を書き出す") {
                        vm.exportCSVTemplates()
                    }.buttonStyle(.app)
                    Button("キャンセル") { vm.exitAdmin() }.buttonStyle(.app)
                }

                Text("検証結果（行番号・列名・理由）").font(.headline)
                if errors.isEmpty {
                    if let plan {
                        Text("エラーなし").foregroundColor(.green)
                        Text(summaryText(plan))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        if !plan.hasChanges {
                            Text("CSVの内容に変更はありません").foregroundColor(.secondary)
                        }
                    } else {
                        Text("CSVを選択してください").foregroundColor(.secondary)
                    }
                } else {
                    TableRowView(cells: ["行番号", "列名", "理由"],
                                 widths: [60, 140, 480], header: true)
                    ForEach(errors) { e in
                        TableRowView(cells: [e.row == 0 ? "―" : "\(e.row)", e.column, e.reason],
                                     widths: [60, 140, 480])
                    }
                }

                if overwriteStock {
                    Text("在庫上書きの差分一覧（確認ダイアログを経て adjust で記録）").font(.headline)
                    TableRowView(cells: ["商品ID", "現在庫", "CSV値", "差分"],
                                 widths: [120, 100, 100, 100], header: true)
                    let diffs = plan?.stockDiffs ?? []
                    ForEach(diffs) { d in
                        let delta = (d.delta > 0 ? "+" : "") + "\(d.delta)"
                        TableRowView(cells: [d.productId, "\(d.current)", "\(d.csv)", delta],
                                     widths: [120, 100, 100, 100])
                    }
                    if diffs.isEmpty {
                        Text("差分なし").foregroundColor(.secondary)
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText],
                      allowsMultipleSelection: false) { result in
            handleImport(result)
        }
        .alert("CSVを取り込みますか？", isPresented: $showConfirm) {
            Button("取り込む") { performImport() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(plan.map { summaryText($0) } ?? "")
        }
    }

    private var canImport: Bool {
        plan != nil && errors.isEmpty && (plan?.hasChanges ?? false)
    }

    private func summaryText(_ p: CSVImportPlan) -> String {
        var lines = [
            "グループ: 新規 \(p.newGroupCount)件 / 更新 \(p.updatedGroupCount)件",
            "種類: 新規 \(p.newTypeCount)件 / 更新 \(p.updatedTypeCount)件",
            "商品: 新規 \(p.newProductCount)件 / 更新 \(p.updatedProductCount)件",
            "在庫変動ログ: \(p.movements.count)件"
        ]
        if !p.stockDiffs.isEmpty {
            lines.append("在庫上書き: \(p.stockDiffs.count)件")
        }
        return lines.joined(separator: "\n")
    }

    private func validate() {
        guard tables.contains(where: { $0 != nil }) else {
            plan = nil
            return
        }
        for i in 0..<3 where !names[i].isEmpty && tables[i] == nil {
            errors = [CSVError(row: 0, column: "CSV",
                               reason: "\(names[i]) を読み込めません。ファイルを選び直してください")]
            plan = nil
            return
        }
        let outcome = vm.makeCSVImportPlan(groupCSV: tables[0],
                                           typeCSV: tables[1],
                                           productCSV: tables[2],
                                           overwriteStock: overwriteStock)
        errors = outcome.errors
        plan = outcome.plan
    }

    private func clear(_ slot: Int) {
        tables[slot] = nil
        names[slot] = ""
        errors = []
        plan = nil
        validate()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let slot = importSlot else { return }
        defer { importSlot = nil }

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let table = try CSVImportParser.parse(data)
                tables[slot] = table
                names[slot] = url.lastPathComponent
                errors = []
                plan = nil
                validate()
            } catch let e as CSVParseError {
                tables[slot] = nil
                names[slot] = url.lastPathComponent
                errors = [e.csvError]
                plan = nil
            } catch {
                tables[slot] = nil
                names[slot] = url.lastPathComponent
                errors = [CSVError(row: 0, column: "ファイル",
                                   reason: "読み込めません: \(error.localizedDescription)")]
                plan = nil
            }
        case .failure(let error):
            let ns = error as NSError
            if ns.code != NSUserCancelledError {
                errors = [CSVError(row: 0, column: "ファイル",
                                   reason: error.localizedDescription)]
                plan = nil
            }
        }
    }

    private func performImport() {
        guard let plan else { return }
        let result = vm.applyCSVImport(plan)
        if result.isEmpty {
            errors = []
            tables = [nil, nil, nil]
            names = ["", "", ""]
            self.plan = nil
            overwriteStock = false
        } else {
            errors = result
        }
    }
}

// MARK: - 集計

struct ReportView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact
    /// 仕様の既定は全期間（A-8）。
    @State private var allPeriod = true
    @State private var start = Date()
    @State private var end = Date()
    @State private var reconDate = Date()
    @State private var reserve = ""
    @State private var actual = ""

    private var from: Date? { allPeriod ? nil : start }
    private var to: Date? { allPeriod ? nil : end }
    private var period: PeriodSummary { vm.periodSummary(from: from, to: to) }
    private var completed: [Sale] { vm.completedSales(from: from, to: to) }
    private var cashSales: Int { period.total.cashJpy }
    private var satsSales: Int { period.total.satsAmount }
    private var mixedCount: Int { period.total.mixedSaleIDs.count }
    private var voidedCount: Int { period.total.canceledSaleIDs.count }
    private var abortedCount: Int { period.total.suspendedSaleIDs.count }
    private var abortedSats: Int { period.total.suspendedSats }

    var body: some View {
        AdminShell("集計") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("全期間（既定）", isOn: $allPeriod)
                if compact {
                    VStack(alignment: .leading, spacing: 8) {
                        DatePicker("開始日", selection: $start, displayedComponents: .date)
                        DatePicker("終了日", selection: $end, displayedComponents: .date)
                    }
                    .disabled(allPeriod)
                } else {
                    HStack(spacing: 12) {
                        DatePicker("開始日", selection: $start, displayedComponents: .date)
                        DatePicker("終了日", selection: $end, displayedComponents: .date)
                    }
                    .frame(maxWidth: 620)
                    .disabled(allPeriod)
                }
                Text("グループ別（精算単位）").font(.headline)
                TableRowView(cells: ["グループ", "区分", "種類", "paid_in", "明細数", "数量", "金額"],
                             widths: [200, 60, 140, 70, 70, 60, 120], header: true)
                let rows = vm.reportRows(from: from, to: to)
                ForEach(rows) { r in
                    TableRowView(cells: [r.groupLabel, r.kind, r.typeName, r.paidIn.rawValue, "\(r.lines)", "\(r.qty)",
                                         r.paidIn == .sats ? Fmt.sats(r.amount) : Fmt.yen(r.amount)],
                                 widths: [200, 60, 140, 70, 70, 60, 120])
                }
                if rows.isEmpty { Text("対象の売上なし").foregroundColor(.secondary) }

                Text("日次小計").font(.headline)
                TableRowView(cells: ["日", "現金", "sats", "取消", "中断sats"],
                             widths: [110, 130, 130, 70, 100], header: true)
                ForEach(period.days, id: \.day) { d in
                    TableRowView(cells: [d.day,
                                         Fmt.yen(d.summary.cashJpy),
                                         Fmt.sats(d.summary.satsAmount),
                                         "\(d.summary.canceledSaleIDs.count)件",
                                         Fmt.sats(d.summary.suspendedSats)],
                                 widths: [110, 130, 130, 70, 100])
                }
                if period.days.isEmpty { Text("対象の日なし").foregroundColor(.secondary) }

                if compact {
                    VStack(alignment: .leading, spacing: 12) {
                        salesCountPanels
                        settlementPanels
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        salesCountPanels
                        settlementPanels
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)],
                          alignment: .leading, spacing: 10) {
                    Button("sats照合一覧") { vm.go(.salesHistory) }.buttonStyle(.app)
                    Button("sats照合CSV（PIN）") {
                        vm.requirePin("sats照合CSV") {
                            vm.exportSatsReconciliation(from: exportFrom, to: exportTo)
                        }
                    }.buttonStyle(.app)
                    Button("グループ別精算CSV（PIN）") {
                        vm.requirePin("グループ別精算CSV") {
                            vm.exportSettlement(from: exportFrom, to: exportTo)
                        }
                    }.buttonStyle(.app)
                    Button("販売・在庫エクスポート（PIN）") {
                        vm.requirePin("エクスポート") { vm.exportAll() }
                    }.buttonStyle(.app)
                    Button("販売履歴・取消") { vm.go(.salesHistory) }.buttonStyle(.app)
                }
                Text("「グループなし」に売上がある場合、営業終了時に内訳（野良の品名・金額）を確認。円とsatsは合算しない。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var salesCountPanels: some View {
        Panel(title: "売上（completed）") {
            Text("会計 \(completed.count)件\n精算額に算入")
        }
        Panel(title: "販売取消（別枠）") {
            Text("\(voidedCount)件\n算入しない")
        }
        Panel(title: "sats確認済み中断（別枠）") {
            Text("\(abortedCount)件 / sats合計 \(Fmt.sats(abortedSats))\n算入しない")
        }
    }

    @ViewBuilder
    private var settlementPanels: some View {
        Panel(title: "受取方法別集計") {
            Text("現金: \(Fmt.yen(cashSales))（現金決済＋併用の現金分）")
            Text("sats: \(Fmt.sats(satsSales))")
            Text("併用会計の会計数: \(mixedCount)")
        }
        Panel(title: "現金照合（日ごと）") {
            DatePicker("照合日", selection: $reconDate, displayedComponents: .date)
            LabeledField(label: "釣銭準備金（円）", text: $reserve)
            LabeledField(label: "実残高（円）", text: $actual)
            Text("その日の現金売上: \(Fmt.yen(recon.cashSales))")
            Text("期待残高: \(Fmt.yen(recon.expected))")
            Text("差額: " + diffText)
        }
    }

    /// 全期間のときは、実際の売上がある最小日〜最大日を CSV の期間列に使う。
    private var exportFrom: Date {
        from ?? vm.sales.compactMap(saleDay).min() ?? Date()
    }

    private var exportTo: Date {
        to ?? vm.sales.compactMap(saleDay).max() ?? Date()
    }

    private var recon: CashReconciliation {
        vm.cashReconciliation(day: reconDate, float: Int(reserve) ?? 0, actual: Int(actual) ?? 0)
    }

    private var diffText: String {
        guard Int(reserve) != nil, Int(actual) != nil else { return "―" }
        return Fmt.yen(recon.difference)
    }
}

// MARK: - 販売履歴・取消

struct SalesHistoryView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact

    var body: some View {
        AdminShell("販売履歴") {
            VStack(alignment: .leading, spacing: 10) {
                TableRowView(cells: ["販売ID", "状態", "方法", "円", "sats", "完了 / 確認時刻", "返金済み"],
                             widths: [170, 90, 100, 80, 90, 170, 80],
                             header: true,
                             actionWidth: compact ? 0 : 300)
                if vm.sales.isEmpty { Text("記録なし").foregroundColor(.secondary) }
                ForEach(vm.sales.reversed()) { s in
                    saleRow(s)
                }
                Text("取消: PIN認証 → 確認ダイアログ → 在庫を戻す（completed_atあり・在庫管理ありの種類のみ）。返金済みフラグはsats分のみ。現金分の返却はシステム外。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func saleRow(_ s: Sale) -> some View {
        let cells = [s.id, s.status.rawValue, s.method.rawValue,
                     s.totalJpy.map { Fmt.num($0) } ?? "―",
                     s.totalSats.map { Fmt.num($0) } ?? "―",
                     s.completedAt == nil ? "確認 " + Fmt.time(s.confirmedAt) + "（中断）" : Fmt.time(s.completedAt),
                     s.refunded ? "済" : "―"]
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                TableRowView(cells: cells, widths: [170, 90, 100, 80, 90, 170, 80])
                actionButtons(s)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            TableRowView(cells: cells, widths: [170, 90, 100, 80, 90, 170, 80], actionWidth: 300) {
                actionButtons(s)
            }
        }
    }

    private func actionButtons(_ s: Sale) -> some View {
        HStack(spacing: 8) {
            Button("取消（PIN）") {
                vm.dialogPin = ""
                vm.dialog = .voidSale(s.id)
            }
            .buttonStyle(.app)
            .frame(width: 120)
            .disabled(s.status != .completed)

            Button("返金済み設定（PIN）") {
                vm.requirePinWithValue("返金済み設定") { entered in vm.toggleRefunded(s.id, pin: entered) }
            }
            .buttonStyle(.app)
            .frame(width: 170)
            .disabled(s.status != .voided || s.totalSats == nil)
        }
    }
}

// MARK: - 手動在庫調整

struct StockAdjustView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact
    @State private var productId = ""
    @State private var newStockText = ""
    @State private var reason = ""

    private var target: Product? { vm.inventory.first { $0.id == productId } }
    private var managed: [Product] { vm.inventory.filter { vm.managesStock($0) } }

    var body: some View {
        AdminShell("手動在庫調整") {
            AdaptiveColumns(spacing: 16) {
                Panel(title: "在庫一覧（在庫管理ありのみ）") {
                    TableRowView(cells: ["商品ID", "商品名", "在庫"], widths: [90, 200, 70], header: true)
                    ForEach(managed) { p in
                        TableRowView(cells: [p.id, p.name, p.stock.map { "\($0)" } ?? "―"], widths: [90, 200, 70])
                    }
                }
            } second: {
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
                    if compact {
                        VStack(spacing: 8) {
                            Button("キャンセル") { vm.exitAdmin() }.buttonStyle(.app)
                            Button("調整を確定（adjust記録）") { commit() }
                                .buttonStyle(.appPrimary)
                                .disabled(Int(newStockText) == nil || reason.isEmpty)
                        }
                    } else {
                        HStack(spacing: 10) {
                            Button("キャンセル") { vm.exitAdmin() }.buttonStyle(.app)
                            Button("調整を確定（adjust記録）") { commit() }
                                .buttonStyle(.appPrimary)
                                .disabled(Int(newStockText) == nil || reason.isEmpty)
                        }
                    }
                }
                .frame(maxWidth: compact ? .infinity : 480)
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
        let pid = productId
        let reasonText = reason
        vm.requirePinWithValue("在庫調整") { entered in
            if let err = vm.performStockAdjustment(productId: pid, newStock: n,
                                                   reason: reasonText, pin: entered) {
                vm.message = err
                return
            }
            vm.message = "在庫を調整しました: \(pid) → \(n)"
            newStockText = ""
            reason = ""
        }
    }
}

// MARK: - 価格一覧・画像なしID一覧

struct PriceListView: View {
    @EnvironmentObject var vm: AppViewModel

    var body: some View {
        AdminShell("価格一覧") {
            AdaptiveColumns(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("価格一覧（登録商品のみ・野良は含めない）").font(.headline)
                    TableRowView(cells: ["product_id", "type_id", "name", "price_jpy", "price_sats"],
                                 widths: [90, 100, 180, 80, 90], header: true)
                    ForEach(vm.inventory) { p in
                        TableRowView(cells: [p.id, p.typeId, p.name, "\(p.priceJpy)", p.priceSats.map { "\($0)" } ?? "（空）"],
                                     widths: [90, 100, 180, 80, 90])
                    }
                    Button("価格一覧CSV出力") {
                        vm.requirePin("価格一覧CSV") { vm.exportPriceList() }
                    }
                        .buttonStyle(.app)
                        .frame(maxWidth: 280)
                    Text("おしながきとの照合用。sats価格が空の商品を確認する。").font(.caption).foregroundColor(.secondary)
                }
            } second: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("公開サイト用の画像がない商品ID").font(.headline)
                    TableRowView(cells: ["product_id", "name"], widths: [100, 240], header: true)
                    ForEach(vm.productsWithoutImage) { p in
                        TableRowView(cells: [p.id, p.name], widths: [100, 240])
                    }
                    if vm.productsWithoutImage.isEmpty { Text("なし").foregroundColor(.secondary) }
                    Text("保存先フォルダに `<商品ID>.jpg` がない商品IDです。先に写真を保存してください。Web用は、ここに載っていない商品の `<商品ID>.jpg` を static/images へコピーしてください。")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - データ管理（初期化・リセット）

struct DataManagementView: View {
    @EnvironmentObject var vm: AppViewModel

    private var stockTotal: Int {
        vm.inventory.compactMap { $0.stock }.reduce(0, +)
    }

    private var outOfStockCount: Int {
        vm.inventory.filter {
            $0.managesStock(in: vm.types) && ($0.stock ?? 0) == 0
        }.count
    }

    var body: some View {
        AdminShell("データ管理（初期化・リセット）") {
            VStack(alignment: .leading, spacing: 16) {
                InfoBox(text: "会計・在庫・商品マスタ・送信ログを初期化します。実行時にPINを1回入力します。",
                        size: 14, bold: false)

                Panel(title: "現在のデータ") {
                    TableRowView(cells: ["グループ", "\(vm.groups.count)件"], widths: [180, 120])
                    TableRowView(cells: ["種類", "\(vm.types.count)件"], widths: [180, 120])
                    TableRowView(cells: ["商品", "\(vm.inventory.count)件"], widths: [180, 120])
                    TableRowView(cells: ["販売", "\(vm.sales.count)件"], widths: [180, 120])
                    TableRowView(cells: ["販売明細", "\(vm.saleItems.count)件"], widths: [180, 120])
                    TableRowView(cells: ["在庫変動", "\(vm.movements.count)件"], widths: [180, 120])
                    TableRowView(cells: ["送信ログ", "\(vm.syncLog.count)件"], widths: [180, 120])
                    Text("在庫合計 \(stockTotal) / 在庫切れ \(outOfStockCount)件")
                        .font(.caption).foregroundColor(.secondary)
                }

                Panel(title: "会計の初期化") {
                    Text("販売履歴を消して、同じ商品で何度でもレジを試せます。")
                    Button("会計を初期化＋在庫を初期データへ") {
                        vm.dialog = .resetAccounting(restoreStock: true)
                    }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: 420, minHeight: 52)
                    Text("販売・明細・販売に伴う在庫変動を削除し、在庫を初期登録時の数量に戻します。商品マスタと送信ログは残ります。")
                        .font(.caption).foregroundColor(.secondary)

                    Button("会計だけ初期化（在庫は販売前に戻す）") {
                        vm.dialog = .resetAccounting(restoreStock: false)
                    }
                    .buttonStyle(.app)
                    .frame(maxWidth: 420, minHeight: 52)
                    Text("手動で行った在庫調整は残したまま、販売の分だけ戻します。")
                        .font(.caption).foregroundColor(.secondary)
                }

                Panel(title: "在庫の初期化") {
                    Text("販売履歴は残したまま、在庫だけを初期データに戻します。")
                    Button("在庫を初期データへ戻す") { vm.dialog = .resetStock }
                        .buttonStyle(.app)
                        .frame(maxWidth: 420, minHeight: 52)
                    Text("初期在庫は、商品登録時・CSV取り込み時の数量です。差分は「手動調整」として在庫ログに残ります。")
                        .font(.caption).foregroundColor(.secondary)
                }

                Panel(title: "送信ログ") {
                    Button("送信ログを削除") { vm.dialog = .clearSyncLog }
                        .buttonStyle(.app)
                        .frame(maxWidth: 420, minHeight: 52)
                    Text("会計・在庫・商品マスタには影響しません。")
                        .font(.caption).foregroundColor(.secondary)
                }

                Panel(title: "動作確認用のテスト会計") {
                    Text("在庫のある商品から、現金のテスト会計を追加します。")
                    HStack(spacing: 10) {
                        Button("1件追加") { vm.addTestSales(count: 1) }
                            .buttonStyle(.app)
                        Button("5件追加") { vm.addTestSales(count: 5) }
                            .buttonStyle(.app)
                    }
                    .frame(maxWidth: 420)
                    Text("通常の会計と同じ処理なので、売上・在庫・在庫変動・集計に反映されます。")
                        .font(.caption).foregroundColor(.secondary)
                }

                Panel(title: "全データ初期化") {
                    Text("商品・種類・グループ・販売・明細・在庫変動・送信ログをすべて削除します。PIN・送信先設定・画像ファイルは残ります。")
                    Button("全データを初期化（空にする）") {
                        vm.dialog = .resetData(reseed: false)
                    }
                    .buttonStyle(.appPrimary)
                    .frame(maxWidth: 420, minHeight: 52)

                    #if DEBUG
                    Button("初期化してテスト商品を再投入") {
                        vm.dialog = .resetData(reseed: true)
                    }
                    .buttonStyle(.app)
                    .frame(maxWidth: 420, minHeight: 52)
                    Text("デバッグビルドのみ。ステッカー・キーホルダー・サービスのテスト商品を入れ直します。")
                        .font(.caption).foregroundColor(.secondary)
                    #endif
                }

                Text("実行ボタンを押したあと、確認のためPINを1回入力します。削除は元に戻せません。")
                    .font(.caption).foregroundColor(.red)
            }
            .frame(maxWidth: 680, alignment: .leading)
        }
    }
}

// MARK: - 公開サイト送信・送信ログ

struct SyncView: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.isCompactWidth) private var compact
    @State private var editingSettings = false
    @State private var endpointDraft = ""
    @State private var tokenDraft = ""
    @State private var confirmingDeleteToken = false

    var body: some View {
        AdminShell("公開サイト送信") {
            VStack(alignment: .leading, spacing: 12) {
                Panel(title: "送信先（A-14）") {
                    if editingSettings {
                        LabeledField(label: "受信エンドポイント（例: https://…/api/snapshot）",
                                     text: $endpointDraft, required: true)
                        LabeledField(label: "認証トークン（変更する場合だけ入力）",
                                     text: $tokenDraft, secure: true)
                        HStack(spacing: 8) {
                            Text(tokenStatusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 8)
                            if !vm.syncToken.isEmpty {
                                Button("トークンを削除") { confirmingDeleteToken = true }
                                    .buttonStyle(.app)
                                    .frame(width: 150)
                            }
                        }
                        HStack(spacing: 8) {
                            Button("保存") { saveSettings() }.buttonStyle(.appPrimary)
                            Button("キャンセル") { editingSettings = false }.buttonStyle(.app)
                        }
                    } else {
                        settingsSummaryRow("受信エンドポイント", value: maskedEndpoint)
                        settingsSummaryRow("認証トークン", value: vm.syncToken.isEmpty ? "未設定" : "保存済み")
                        Button("送信先を編集") { beginEditing() }.buttonStyle(.app)
                    }
                }
                Panel(title: "自動送信") {
                    Toggle("変更をまとめて自動送信する", isOn: Binding(
                        get: { vm.autoSendEnabled },
                        set: { vm.setAutoSendEnabled($0) }
                    ))
                    Text("会計・販売取消・在庫調整・商品編集などのあと、最後の変更から約10秒待って1回だけ送信します。通信できないときは、回復後に送ります。手動送信はいつでもできます。")
                        .font(.caption).foregroundColor(.secondary)
                }
                 if vm.staleRejected {
                     Text("サイト側に反映されていない変更があります。サイト側により新しいデータがあると判定されました。端末の時計を確認し、直したあとに「公開サイトへ送信」で手動送信してください。")
                         .font(.callout)
                         .foregroundColor(.orange)
                         .padding(12)
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
                 }
                if compact {
                    VStack(spacing: 10) {
                        InfoBox(text: "通信: \(vm.isOnline ? "あり" : "なし")　／　最終送信: \(Fmt.time(vm.lastSyncAt))", size: 14, bold: false)
                        Button("公開サイトへ送信") { vm.sendSnapshot() }
                            .buttonStyle(.appPrimary)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .disabled(editingSettings)
                    }
                } else {
                    HStack(spacing: 12) {
                        InfoBox(text: "通信: \(vm.isOnline ? "あり" : "なし")　／　最終送信: \(Fmt.time(vm.lastSyncAt))", size: 14, bold: false)
                        Button("公開サイトへ送信") { vm.sendSnapshot() }
                            .buttonStyle(.appPrimary)
                            .frame(maxWidth: 280, minHeight: 52)
                            .disabled(editingSettings)
                    }
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
        .alert("認証トークンを削除しますか？", isPresented: $confirmingDeleteToken) {
            Button("削除", role: .destructive) { deleteToken() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("保存済みの認証トークンを端末から削除します。")
        }
    }

    private var maskedEndpoint: String {
        let endpoint = vm.syncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return endpoint.isEmpty ? "未設定" : "設定済み（••••）"
    }

    private var tokenStatusText: String {
        if !tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "トークン: 入力あり（保存で確定）"
        }
        return vm.syncToken.isEmpty ? "トークン: 未設定" : "トークン: 保存済み"
    }

    private func settingsSummaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func beginEditing() {
        endpointDraft = vm.syncEndpoint
        tokenDraft = ""
        editingSettings = true
    }

    private func saveSettings() {
        let endpoint = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else {
            vm.message = "受信エンドポイントを入力してください"
            return
        }
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if vm.saveSyncSettings(endpoint: endpoint, newToken: token.isEmpty ? nil : token) {
            editingSettings = false
        }
    }

    private func deleteToken() {
        if vm.deleteSyncToken() {
            tokenDraft = ""
        }
    }
}