import SwiftUI

// ════════════════════════════════════════════════════════════
// ルート：PIN → ホーム（5_画面構成.md の起動フロー）
// 営業中は準備画面に入れない（誤操作防止）。準備へ戻る時はPIN。
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct ContentView: View {
    @Environment(FremaRegiStore.self) private var store
    @State private var unlocked = false

    var body: some View {
        Group {
            if !store.pinSet {
                PinGate(setup: true) { pin in
                    _ = store.setPIN(pin)     // 初回PIN設定（C-6 #76）。成功すると store.pinSet が true になり解錠画面へ
                } onCancel: {}
            } else if unlocked {
                HomeView(onLock: { unlocked = false })
            } else {
                PinGate(setup: false) { _ in unlocked = true } onCancel: {}
            }
        }
        .frame(minWidth: 900, minHeight: 560)   // Neo 横画面想定（P0/Q16 で実機調整）
    }

}

/// PINゲート（ロック画面のキーパッド。● ● ○ ○ 表示）
@available(iOS 17.0, macOS 14.0, *)
struct PinGate: View {
    let setup: Bool
    let onDone: (String) -> Void
    let onCancel: () -> Void

    @State private var pin = ""
    @State private var error: String?
    @State private var attempts = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("レ ジ").font(.system(size: 44, weight: .bold))
            if setup { Text("最初の利用：PINを設定してください").foregroundStyle(.secondary) }

            PinDots(count: pin.count)

            if let error { Text(error).foregroundStyle(.red).font(.callout) }

            NumericKeypad { key in handle(key) }
                .frame(width: 280)

            HStack(spacing: 16) {
                Button("リセット") { pin = ""; error = nil }
                Button(onDoneLabel) { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pin.isEmpty)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var onDoneLabel: String { setup ? "設定して開始" : "解錠" }

    private func handle(_ key: KeypadKey) {
        error = nil
        switch key {
        case .digit(let d): if pin.count < 8 { pin.append(d) }
        case .backspace: if !pin.isEmpty { pin.removeLast() }
        case .doubleZero: break   // PINでは 00 ボタンなし
        }
    }

    private func submit() {
        guard PinStore.isValidPin(pin) else {
            error = "PINは4〜8桁の数字で入力してください"
            return
        }
        if setup {
            onDone(pin)
        } else {
            if PinStore().verify(pin) {
                onDone(pin)
            } else {
                attempts += 1
                error = attempts >= 5 ? "PINが違います（しばらく待ってから再度お試しください）" : "PINが違います"
                pin = ""
            }
        }
    }
}

// ════════════════════════════════════════════════════════════
// ホーム：「営業をはじめる」／「準備（営業前）」
// ════════════════════════════════════════════════════════════

@available(iOS 17.0, macOS 14.0, *)
struct HomeView: View {
    @Environment(FremaRegiStore.self) private var store
    let onLock: () -> Void

    @State private var showPrepGate = false     // 準備に入る前のPIN確認
    @State private var enteredPrep = false
    @State private var enteredRegister = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                bigButton(title: "営業をはじめる", systemImage: "cart.fill") {
                    enteredRegister = true
                    // 営業＝レジ画面1枚。会計状態が中途半端なら Store からそのまま復元される（A-3）
                }

                bigButton(title: "準備（営業前）", systemImage: "wrench.and.screwdriver.fill") {
                    showPrepGate = true
                }
                .disabled(!store.canEdit)   // 営業中（会計中）は準備に入れない
                .overlay(alignment: .trailing) {
                    if !store.canEdit {
                        Text("会計中は不可").font(.caption).foregroundStyle(.secondary)
                            .offset(x: 110)
                    }
                }
                Spacer()
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("レジ")
            .toolbar {
                ToolbarItem(placement: .principal) { EmptyView() }
                ToolbarItemGroup(placement: .primaryAction) {
                    ConnectivityBadge()
                    Button("終了", action: onLock)
                }
            }
            .navigationDestination(isPresented: $enteredPrep) { PrepMenuView() }
            .navigationDestination(isPresented: $enteredRegister) { RegisterView() }
            .sheet(isPresented: $showPrepGate) {
                PinSheet(mode: .verify("準備画面へ")) { pin in
                    showPrepGate = false
                    if PinStore().verify(pin) { enteredPrep = true }
                    else { store.lastMessage = "PINが違います" }
                } onCancel: { showPrepGate = false }
            }
            .toast($store.lastMessage)
        }
    }

    private func bigButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title2.bold())
                .frame(maxWidth: 420, minHeight: 90)
        }
        .buttonStyle(.borderedProminent)
    }
}

/// 通信バッジ（A-10：sats可否は通信の有無で決まる）
@available(iOS 17.0, macOS 14.0, *)
struct ConnectivityBadge: View {
    @Environment(FremaRegiStore.self) private var store
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: store.hasConnectivity ? "wifi" : "wifi.slash")
            Text(store.hasConnectivity ? "オンライン" : "オフライン（sats払い不可）")
                .font(.caption)
        }
        .foregroundStyle(store.hasConnectivity ? Color.green : Color.orange)
    }
}
