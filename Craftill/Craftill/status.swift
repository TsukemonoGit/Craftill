import Foundation

/// 確認ダイアログに出すもの
struct ConfirmReason: Equatable {
    let title: String
    let message: String
}

/// 遷移の要求。**まだ遷移していない**。UI はこの返り値に従って動くだけ。
enum Move: Equatable {
    case allowed(SaleState)                       // このまま遷移してよい
    case needsConfirm(ConfirmReason, SaleState)   // 確認が済んだら `nextState` へ
    case needsPIN(ConfirmReason, SaleState)       // PIN ＋ 確認が済んだら `nextState` へ
    case rejected(String)                         // 遷移できない。理由をそのまま表示する

    var nextState: SaleState? {
        switch self {
        case .allowed(let s): return s
        case .needsConfirm(_, let s), .needsPIN(_, let s): return s
        case .rejected: return nil
        }
    }
    var reason: ConfirmReason? {
        switch self {
        case .allowed: return nil
        case .needsConfirm(let r, _), .needsPIN(let r, _): return r
        case .rejected(let m): return ConfirmReason(title: "操作できません", message: m)
        }
    }
}


/// 状態以外に必要な値だけをまとめたもの。
/// これを1つ保存・復元すれば、会計の状態がまるごと復元できる（C-6 #2・#78、`19_lesson` の担当）
struct SaleContext: Codable, Equatable {
    var state: SaleState = .idle
    var cart: [CartLine] = []
    /// sats の入金が確認された時刻。**nil なら未確認**（A-19-2 の判別）
    var satsConfirmedAt: Date?
    /// 済ボタンで承認した請求sats額。承認後に復元しても変化しない（C-6 #78）
    var confirmedSats: Int?
}


enum SaleEvent: Equatable {
    case addFirstItem          // 待機中の最初の商品追加
    case addItem               // 以降の商品追加
    case removeItem            // 商品取消
    case toPaymentSelection    // 会計へ進む
    case backToScan            // 戻る（支払方法選択 → スキャン中）
    case chooseCash            // 現金
    case chooseSats            // sats払い
    case tapDone               // 済ボタン（sats待ち・承認前）
    case changeMethod          // 方法選び直し
    case suspend               // 会計中断
    case confirmCash(Int)      // 受取額確定（現金入力中）
    case confirmMixedCash(Int) // 受取額確定（併用現金入力中）
    case backToIdle            // 完了／中断のあと
}



/// 遷移を1つ判断する。**状態は書き換えない**（返り値の `nextState` を使う）
func move(_ e: SaleEvent, in ctx: SaleContext) -> Move {
    switch ctx.state {

    case .idle:
        switch e {
        case .addFirstItem: return .allowed(.scanning)
        case .addItem:      return .rejected("待機中は「スキャン中」です。商品をスキャンしてください")
        case .suspend:      return .rejected("中断できません（カートが空です）")   // A-4 の表
        default:            return .rejected("この状態ではできません")
        }

    case .scanning:
        switch e {
        case .addItem:  return .allowed(.scanning)
        // カートが空になったら待機中へ（A-4）
        case .removeItem: return .allowed(ctx.cart.count <= 1 ? .idle : .scanning)
        case .toPaymentSelection: return .allowed(.choosingPayment)
        case .suspend:  return .needsConfirm(suspendReason(in: ctx), .suspended)
        default:        return .rejected("この状態ではできません")
        }

    case .choosingPayment:
        switch e {
        case .backToScan: return .allowed(.scanning)
        case .chooseCash: return .allowed(.cashInput)
        case .chooseSats:
            // 遷移の条件「sats単価のある行が1行以上」（A-4、A-6-1）
            // ★ 判定は `canPayBySats()` 1 か所だけ（base/2）。ここで書き直さない
            guard ctx.cart.canPayBySats() else {
                return .rejected("sats単価のある商品がありません。現金でお支払いください")
            }
            return .allowed(.satsWaiting)
        case .suspend: return .needsConfirm(suspendReason(in: ctx), .suspended)
        default:       return .rejected("この状態では商品追加・取消はできません")   // A-4 の表
        }

    case .cashInput:
        switch e {
        case .confirmCash(let received):
            let due = ctx.cashDueJpy                         // 全行の円合計（§7）
            guard received >= due else {
                return .rejected("受取額が請求額（\(due)円）未満です")
            }
            return .allowed(.done)
        case .suspend: return .needsConfirm(suspendReason(in: ctx), .suspended)
        default:       return .rejected("この状態ではできません")
        }

    case .satsWaiting:
        switch e {
        case .tapDone:
            // 現金分の有無で遷移先が変わる（A-4、C-6 #23・#77）
            let t = ctx.cart.totals()
            return t.cashForSats == 0
                ? .needsConfirm(tapDoneReason(in: ctx), .done)
                : .needsConfirm(tapDoneReason(in: ctx), .mixedCashInput)
        case .changeMethod: return .allowed(.choosingPayment)   // A-19-8：2段の1つ目
        case .suspend:      return .needsConfirm(cancelReason(in: ctx), .suspended)
        default:            return .rejected("請求額が決まったので、方法や商品は変えられません")
        }

    case .mixedCashInput:
        switch e {
        case .confirmMixedCash(let received):
            let due = ctx.cashDueJpy                         // ★ 現金分だけ（§7）
            guard received >= due else {
                return .rejected("受取額が現金分（\(due)円）未満です")
            }
            return .allowed(.done)
        case .suspend:
            // sats確認済みなので PIN 必須・記録を残す（A-4、A-19-2）
            return .needsPIN(pinReason(), .suspended)
        default: return .rejected("請求額が決まったので、方法や商品は変えられません")
        }

    case .done:
        switch e {
        case .backToIdle: return .allowed(.idle)
        default:          return .rejected("完了した会計は中断できません")   // A-4 の表
        }

    case .suspended:
        switch e {
        case .backToIdle: return .allowed(.idle)
        default:          return .rejected("中断しました。待機中に戻ってください")
        }
    }
}



/// 中断の確認（A-4「中断時はカートの内容が破棄されるため、確認ダイアログを経る」）
func suspendReason(in ctx: SaleContext) -> ConfirmReason {
    let t = totalLines(ctx.cart)
    return ConfirmReason(
        title: "会計を中断しますか",
        message: "カートの内容が破棄されます。\n\(t.satsLine)\n\(t.cashLine)")
}

/// sats待ちのキャンセル（A-4「sats待ち → 中断: キャンセル（確認あり）」。PIN不要）
func cancelReason(in ctx: SaleContext) -> ConfirmReason {
    ConfirmReason(title: "sats払いをやめますか",
                  message: "カートの内容はそのまま残ります（中断すると破棄されます）。")
}

/// 済ボタンの確認（C-6 #23「確認ダイアログを経ずに完了しない」）
func tapDoneReason(in ctx: SaleContext) -> ConfirmReason {
    let t = ctx.cart.totals()
    var msg = "請求sats額 \(t.sats)sats。WoS で入金を確認してから押してください。"
    if t.cashForSats > 0 { msg += "\nこのあとに現金 \(t.cashForSats)円 を受け取ります。" }
    return ConfirmReason(title: "入金を確認しましたか", message: msg)
}

/// sats確認済みの中断（A-19-2：PIN必須・記録を残す）
func pinReason() -> ConfirmReason {
    ConfirmReason(title: "会計を中断しますか",
                  message: "sats の入金が確認済みのため、PIN が必要です。\n記録が残ります。")
}



/// 確認・PIN が済んだ遷移を適用する。**`nextState` が nil のときは何もしない**
func apply(_ m: Move, to ctx: inout SaleContext) {
    guard let to = m.nextState else { return }
    ctx.state = to
}

/// 済ボタン承認時。**請求sats額をこのときだけ確定させる**（C-6 #78）
func markSatsConfirmed(_ ctx: inout SaleContext, at: Date) {
    ctx.satsConfirmedAt = at
    ctx.confirmedSats = ctx.cart.totals().sats
}



extension SaleContext {
    /// 会計全体の受取方法（A-13 の `method`）。まだ選んでいなければ nil。
    var method: PaymentMethod? {
        switch state {
        case .cashInput:      return .cash
        case .satsWaiting:    return cart.totals().cashForSats == 0 ? .lightning : .mixed
        case .mixedCashInput: return .mixed
        // 待機中〜支払方法選択はまだ選んでいない。
        // 中断・完了は復元しないので、判定しない（A-3、完了時は保存を消す）
        case .idle, .scanning, .choosingPayment, .suspended, .done: return nil
        }
    }

    /// この会計で**現金で受け取る額**。A-6-1 の決め대로決まる。
    /// - `sats待ち` / `併用現金入力中`: **現金分だけ**（sats分は WoS で受ける）
    /// - それ以外: 全行の円合計（全額現金）
    var cashDueJpy: Int {
        switch state {
        case .satsWaiting, .mixedCashInput: return cart.totals().cashForSats
        default:                            return cart.totals().cash
        }
    }
}



/// 会計の文脈をファイルへ保存・復元する。**失敗は `throws` で外へ出す**（黙って捨てない）
struct SaleContextStore {
    let url: URL
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    init(url: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                          .appendingPathComponent("saleContext.json")) {
        self.url = url
    }

    /// 更新のたびに呼ぶ
    func save(_ ctx: SaleContext) throws {
        let data = try encoder.encode(ctx)      // base/2 の encoder（ISO 8601）
        try data.write(to: url, options: .atomic)   // ← 途中で落ちても壊れない
    }

    /// 起動時に呼ぶ。**「無い」は nil、「壊れている」は throw** で区別する
    func load() throws -> SaleContext? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(SaleContext.self, from: data)
    }

    /// 完了・記録に残らない中断のあと（A-3）
    func clear() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
