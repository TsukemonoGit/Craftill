import Foundation

// ════════════════════════════════════════════════════════════
// PIN（A-11）— 端末内のファイルに保存する。通信不要。
// 初回起動でPINを設定できる（C-6 #76）。PIN設定前は初期投入のみ行える。
// 桁数は4〜8を許容（Q21 仮置き：4桁既定）。試行回数制限はローカルで簡易に行う。
// ════════════════════════════════════════════════════════════

struct PinStore {
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FremaRegi", isDirectory: true)
            .appendingPathComponent("pin.txt")
    }

    /// PINが設定済みか（未設定なら編集・販売確定系のPIN操作は実行できない・C-6 #76）
    var isSet: Bool {
        (try? Data(contentsOf: url)) != nil
    }

    /// 現在のPIN（呼び出し側で `correctPIN` として標準ロジックへ渡す）
    var current: String {
        get throws {
            String(data: try Data(contentsOf: url), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    /// PINを検証する。失敗しても例外は投げず false を返す。
    func verify(_ pin: String) -> Bool {
        guard let stored = try? current else { return false }
        return !stored.isEmpty && stored == pin
    }

    /// PINを設定する（初回は4〜8桁の数字のみを許容）。
    static func isValidPin(_ pin: String) -> Bool {
        pin.count >= 4 && pin.count <= 8 && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }

    mutating func set(_ pin: String) throws {
        guard PinStore.isValidPin(pin) else {
            throw PinError.invalidFormat
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try pin.data(using: .utf8)!.write(to: url, options: .atomic)
    }

    enum PinError: LocalizedError {
        case invalidFormat
        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "PINは4〜8桁の半角数字で入力してください"
            }
        }
    }
}
