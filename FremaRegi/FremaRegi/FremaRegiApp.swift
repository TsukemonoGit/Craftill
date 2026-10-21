import SwiftUI

// ════════════════════════════════════════════════════════════
// FremaRegi — フリーマーケット用レジ（マルチプラットフォーム）
// iOS / iPadOS / macOS で同じコードを動かす（SwiftUI・共有コード方式）。
// 通信が必要なのは KV 送信（A-14）だけ。会計は通信なしで完結する（A-10）。
// ════════════════════════════════════════════════════════════

@main
struct FremaRegiApp: App {
    // @Observable ストア（iOS 17 / macOS 14 以上でビルドすること）
    @State private var store = FremaRegiStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task { Connectivity.shared.startMonitoring() }   // A-10 のsats可否
        }
    }
}
