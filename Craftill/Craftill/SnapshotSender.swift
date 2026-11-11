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

    static var endpoint: String {
        get { UserDefaults.standard.string(forKey: endpointKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: endpointKey) }
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

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "HTTP \(code)"
            case .emptyResponse: return "応答が空です"
            case .stale: return "サイト側により新しいデータがあります（端末の時計のずれの可能性）"

            }
        }
    }

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
            encoder.dateEncodingStrategy = .iso8601
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(snapshot)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(SendError.emptyResponse))
                return
            }
            if http.statusCode == 409 {
                 completion(.failure(SendError.stale))
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
