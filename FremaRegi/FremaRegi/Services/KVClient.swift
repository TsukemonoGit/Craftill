import Foundation

// ════════════════════════════════════════════════════════════
// KV 送信クライアント（A-14・C-2）
// Cloudflare Workers の REST API を叩く。通信が必要なのはここだけ（A-10）。
// トークンはアプリに埋め込まない（AppConfig.swift に分離し、gitignore する）。
// ════════════════════════════════════════════════════════════

/// ビルド設定から読み取るKV送信先。`AppConfig.generated.swift` が無い場合は nil（送信不可）。
struct KVEndpoint {
    let account: String
    let namespace: String
    let token: String
    var baseURL: String { "https://api.cloudflare.com/client/v4" }
}

final class KVClient {
    private let endpoint: KVEndpoint?
    private let session: URLSession

    init(endpoint: KVEndpoint?, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    var isConfigured: Bool { endpoint != nil }

    /// `regi/inventory/current` にスナップショットJSONを書く（A-14）。
    func put(snapshot: Snapshot) async throws {
        guard let ep = endpoint else { throw KVError.notConfigured }
        let enc = jsonEncoder
        enc.outputFormatting = [.sortedKeys]
        let body = try enc.encode(snapshot)

        var req = URLRequest(url: URL(string: "\(ep.baseURL)/accounts/\(ep.account)"
            + "/storage/kv/namespaces/\(ep.namespace)/values/regi%2Finventory%2Fcurrent")!)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(ep.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw KVError.http(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, detail: detail)
        }
    }

    enum KVError: LocalizedError {
        case notConfigured
        case http(status: Int, detail: String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "KV送信先がビルド設定に含まれていません（通信なし運用では不要）"
            case .http(let s, let d): return "KV送信エラー(\(s)): \(d)"
            }
        }
    }
}
