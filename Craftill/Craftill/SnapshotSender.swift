import Foundation
import Security

// ════════════════════════════════════════════════════════════
// A-14 / B: 公開サイトへのスナップショット送信
// 送信先とトークンは端末ごとに設定する。トークンは Keychain に保存する。
// ════════════════════════════════════════════════════════════

enum SyncSettings {
    private static let endpointKey = "craftill.syncEndpoint"
    private static let autoSendKey = "craftill.syncAutoSend"
    private static let pendingAutoSendKey = "craftill.syncPendingAutoSend"
    private static let staleRejectedKey = "craftill.syncStaleRejected"
    private static let revisionKey = "craftill.syncRevision"

    static var endpoint: String {
        get { UserDefaults.standard.string(forKey: endpointKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: endpointKey) }
    }

    /// スナップショットの順序を識別する単調増加の番号。
    /// 同じミリ秒に複数送っても新しい方を判別できるよう、送信のたびに増やす。
    /// アプリを再起動しても続きから採番する。
    static func nextRevision() -> Int {
        let defaults = UserDefaults.standard
        let next = defaults.integer(forKey: revisionKey) + 1
        defaults.set(next, forKey: revisionKey)
        return next
    }

    /// 会計・在庫・商品などの変更後に、自動でスナップショットを送るか（全体設定）。
    static var autoSend: Bool {
        get {
            UserDefaults.standard.object(forKey: autoSendKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: autoSendKey) }
    }

     /// 未送信の変更があるか。アプリ終了後も保持し、次回起動時に送る。
     static var pendingAutoSend: Bool {
         get { UserDefaults.standard.bool(forKey: pendingAutoSendKey) }
         set { UserDefaults.standard.set(newValue, forKey: pendingAutoSendKey) }
     }
     /// 時計のずれ等で、サイト側に拒否された変更があるか。手動送信が成功するまで保持する。
     static var staleRejected: Bool {
         get { UserDefaults.standard.bool(forKey: staleRejectedKey) }
         set { UserDefaults.standard.set(newValue, forKey: staleRejectedKey) }
     }

    static var token: String {
        get { SyncTokenStore.load() ?? "" }
        set { _ = SyncTokenStore.save(newValue) }
    }

    /// Keychain への保存結果を呼び出し側で確認したいとき用。
    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        SyncTokenStore.save(token)
    }
}

enum SyncTokenStore {
    private static let service = "dev.craftill.sync"
    private static let account = "token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load() -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        if token.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        SecItemDelete(baseQuery as CFDictionary)
        var q = baseQuery
        q[kSecValueData as String] = Data(token.utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}

struct SnapshotSender {
    let endpoint: URL
    let token: String

    enum SendError: LocalizedError {
        case badResponse(Int)
        case emptyResponse
        case stale
        case notInitialized

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "HTTP \(code)"
            case .emptyResponse: return "応答が空です"
            case .stale: return "サイト側により新しいデータがあります（端末の時計のずれの可能性）"
            case .notInitialized: return "受信側が初期化されていません（移行手順を確認してください）"

            }
        }

        /// 待ってから再送すれば成功する可能性があるか。
        /// 4xx の多く（認証・URL・競合）は再送しても同じ結果になるため含めない。
        var isRetryable: Bool {
            switch self {
            case .badResponse(let code):
                return code == 408 || code == 425 || code == 429 || code >= 500
            case .emptyResponse:
                return true
            case .stale:
                return false
            case .notInitialized:
                // 受信側の初期化作業が終われば成功する。
                return true
            }
        }
    }

    /// ミリ秒付きの ISO 8601。同じ秒に複数送っても `created_at` で新旧を判別できる。
    private static let iso8601WithMilliseconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 認証付きで JSON を POST する。成功時だけ戻る（失敗は throw）。
    func send(_ snapshot: Snapshot, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(Self.iso8601WithMilliseconds.string(from: date))
            }
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(snapshot)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(SendError.emptyResponse))
                return
            }
            if http.statusCode == 409 {
                 if let data, String(data: data, encoding: .utf8) == "Stale" {
                     completion(.failure(SendError.stale))
                     return
                 }
             }
            if http.statusCode == 503,
               let data,
               String(data: data, encoding: .utf8) == "Not Initialized" {
                completion(.failure(SendError.notInitialized))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(SendError.badResponse(http.statusCode)))
                return
            }
            completion(.success(()))
        }.resume()
    }
}
