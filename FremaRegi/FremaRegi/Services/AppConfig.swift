import Foundation

// ════════════════════════════════════════════════════════════
// KV送信先のビルド設定（A-14）
// トークンはアプリに埋め込まない。`AppConfig.generated.swift` に定義し、
// このファイルは git にコミットしない（テンプレート: AppConfig.example.swift）。
// 未設定のままでもアプリは動く（送信ボタンだけエラーメッセージになる・C-6 #72）。
// ════════════════════════════════════════════════════════════

enum AppKVConfig {
    /// `AppConfig.generated.swift` の `appKVEndpoint` を使う。無ければ nil。
    static var endpoint: KVEndpoint? { appKVEndpoint }
}
