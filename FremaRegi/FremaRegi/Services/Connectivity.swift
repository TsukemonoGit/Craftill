import Foundation

// ════════════════════════════════════════════════════════════
// 通信の有無（A-10・C-6 #68/#69）
// sats払いの可否は「接続確認画面なし」で、**通信の有無そのもの**で決める。
// Network.framework でインターフェースの状態を見るだけ（パケットを送らない）。
// ════════════════════════════════════════════════════════════

#if canImport(Observation)
import Observation

@available(iOS 17.0, macOS 14.0, *)
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()

    /// 通信があるか（初期値 true：有線macなどでは常時 true に近い）
    var available: Bool = true

    private init() {}

    func startMonitoring() {
        NetworkPathMonitor.shared.start { reachable in
            Task { @MainActor in
                self.available = reachable
            }
        }
    }
}
#endif

/// `NWPathMonitor` の薄い皮。監視はバックグラウンドキューで行い、UI側は `available` を見る。
final class NetworkPathMonitor: @unchecked Sendable {
    static let shared = NetworkPathMonitor()

    private init() {}

    /// 起動時に1回だけ呼ぶ。以降、通信の有無が変わってもこの関数は戻らない（Taskで生かし続ける）。
    func start(_ onChange: @escaping @Sendable (Bool) -> Void) {
        #if canImport(Network)
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            onChange(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
        #else
        onChange(true)
        #endif
    }
}
