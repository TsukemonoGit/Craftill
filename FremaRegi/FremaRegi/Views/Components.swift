import SwiftUI

// ════════════════════════════════════════════════════════════
// 共通コンポーネント（画面構成 5_画面構成.md に合わせて横画面想定）
// ════════════════════════════════════════════════════════════

/// 円表示のフォーマッタ
func jpy(_ n: Int) -> String { "¥" + n.formatted(.number.grouping(.automatic)) }
/// sats表示のフォーマッタ
func sats(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) + " sats" }

// ────────────────────────────────────────────
// トースト（store.lastMessage を1回表示して消す）
// ────────────────────────────────────────────
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.5))
                        if self.message == message { withAnimation { self.message = nil } }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

// ────────────────────────────────────────────
// PIN入力ダイアログ（A-11。編集・中断・精算など要所で見せる）
// mode: 設定 / 照合
// ────────────────────────────────────────────
struct PinSheet: View {
    enum Mode { case setup, verify(String) }   // verify: タイトルに使う理由

    let mode: Mode
    /// 確定時にPIN文字列を返す。setup はセット成功時のみ呼ぶ。
    let onDone: (String) -> Void
    let onCancel: () -> Void

    @State private var pin: String = ""
    @State private var pinConfirm: String = ""
    @State private var error: String?

    private var isSetup: Bool {
        if case .setup = mode { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.title2.bold())
            if isSetup {
                LabeledField(label: "PIN（4〜8桁の数字）") {
                    SecretInput(text: $pin).multilineTextAlignment(.center)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                }
                LabeledField(label: "PIN（もう一度）") {
                    SecretInput(text: $pinConfirm).multilineTextAlignment(.center)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                }
            } else {
                Text("この操作にはPINが必要です").foregroundStyle(.secondary)
                PinDots(count: pin.count)
                NumericKeypad { key in handleKey(key) }
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("キャンセル") { onCancel() }
                Spacer()
                Button(isSetup ? "設定" : "確定") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
        }
        .padding(24)
        .frame(minWidth: 320, maxWidth: 420)
    }

    private var title: String {
        switch mode {
        case .setup: return "PINを設定"
        case .verify(let reason): return "PIN入力（\(reason)）"
        }
    }

    private var canSubmit: Bool {
        if isSetup { return PinStore.isValidPin(pin) && pin == pinConfirm }
        return PinStore.isValidPin(pin)
    }

    private func handleKey(_ key: KeypadKey) {
        switch key {
        case .digit(let d):
            if pin.count < 8 { pin.append(d) }
        case .backspace:
            if !pin.isEmpty { pin.removeLast() }
        case .doubleZero:
            if pin.count <= 6 { pin += "00" }
        }
    }

    private func submit() {
        if isSetup {
            guard pin == pinConfirm else { error = "PINが一致しません"; return }
            onDone(pin)
        } else {
            guard PinStore.isValidPin(pin) else { error = "4〜8桁の数字で入力してください"; return }
            onDone(pin)
        }
    }
}

/// PINの丸表示（● ● ○ ○）
struct PinDots: View {
    let count: Int
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<max(4, count), id: \.self) { i in
                Circle().fill(i < count ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 12, height: 12)
            }
        }
    }
}

// ────────────────────────────────────────────
// 数値キーパッド（PIN・現金入力で共用）
// ────────────────────────────────────────────
enum KeypadKey: Equatable {
    case digit(Character)
    case doubleZero
    case backspace
}

struct NumericKeypad: View {
    let onTap: (KeypadKey) -> Void
    /// 00ボタンを出すか（現金入力のみ）
    var showDoubleZero: Bool = false

    private let rows: [[String]] = [["1","2","3"],["4","5","6"],["7","8","9"]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { s in
                        keyButton(s)
                    }
                }
            }
            HStack(spacing: 8) {
                if showDoubleZero {
                    keyButton("0"); keyButton("00"); deleteButton
                } else {
                    keyButton("0"); deleteButton
                }
            }
        }
    }

    private func keyButton(_ label: String) -> some View {
        Button {
            if label == "00" { onTap(.doubleZero) } else { onTap(.digit(Character(label))) }
        } label: {
            Text(label).font(.title2).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private var deleteButton: some View {
        Button { onTap(.backspace) } label: {
            Image(systemName: "delete.left").font(.title2).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }
}

// ────────────────────────────────────────────
// フォーム小物
// ────────────────────────────────────────────
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content.textInputItem()
        }
    }
}

extension View {
    /// macOS では .textFieldStyle(.roundedBorder) が使えないため platform 分岐
    @ViewBuilder func textInputItem() -> some View {
        #if os(macOS)
        self.padding(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        #else
        self.textFieldStyle(.roundedBorder)
        #endif
    }
}

/// SecureField の platform 分岐（macOS 14 では `SecureField("", text:)` のみ対応）
struct SecretInput: View {
    @Binding var text: String
    var body: some View {
        #if os(macOS)
        SecureField("", text: $text)
        #else
        SecureField("") { Text("PIN") } text: { $text }
        #endif
    }
}

/// オプショナル整数の入力（空 = nil）
struct OptionalIntField: View {
    let placeholder: String
    @Binding var value: Int?

    @State private var text: String = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .onAppear { text = value.map(String.init) ?? "" }
            .onChange(of: text) { _, new in
                let trimmed = new.filter { $0.isNumber }
                if trimmed != new { text = trimmed }
                value = trimmed.isEmpty ? nil : Int(trimmed)
            }
    }
}

// ────────────────────────────────────────────
// CSVインポート結果ビュー（検証問題の一覧表示・A-1）
// ────────────────────────────────────────────
struct ImportOutcomeView: View {
    let outcome: FremaRegiStore.ImportOutcome
    var body: some View {
        Group {
            if outcome.ok {
                Label(outcome.summary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("取り込みは見合わせました（\(outcome.issues.count)件の問題）。すべて修正すると0件になります",
                          systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    ForEach(Array(outcome.issues.enumerated()), id: \.offset) { _, issue in
                        Text("行\(issue.row) [\(issue.column)]: \(issue.reason)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
