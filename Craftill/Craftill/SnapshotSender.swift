import Foundation
import Security

// ════════════════════════════════════════════════════════════
// A-14 / B: 公開サイトへのスナップショット送信
// 送信先とトークンは端末ごとに設定する。トークンは Keychain に保存する。
// ════════════════════════════════════════════════════════════

enum SyncSettings {
    private static let endpointKey = "craftill.syncEndpoint"

    static var endpoint: String {
        get { UserDefaults.standard.string(forKey: endpointKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: endpointKey) }
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

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "HTTP \(code)"
            case .emptyResponse: return "応答が空です"
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
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(SendError.badResponse(http.statusCode)))
                return
            }
            completion(.success(()))
        }.resume()
    }
}
