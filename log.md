前回セッション ses_eb2cb62e4ffeGpT7Q3BOwQEh8S（レート制限で中断）の続き。
作業ディレクトリ: docs/使い方講座/
目的: AIが作った講座教材（レッスン md 群）の品質向上。仕様書 docs/siyou.md を正とし、型・ロジックを base/ に集約して、各レッスンを「base/ を参照する差分レッスン」に作り直している。

## 作業ルール（前セッションから継続）
- 1レッスン1トピック。他レッスンが担当する内容は再説明せず参照に回す。
- コピペ教材にしない。「わざと間違う」版（```swift NG）で壊れ方を見せ、「考えてみる」で思考の手順を示し、直し方を段階的に示す。
- 各レッスンは base/ の型・関数を使い、独自の型定義を持たない（例外: 01-1〜03 の入門、独立領域）。
- 1本ごとに必ず: swiftc -typecheck → swift 実行 → 「できた合図」の期待出力と1行ずつ照合（python3 verify.py）。
- 検証中に base/ や仕様の穴を見つけたら、レッスン側で回避せず、siyou.md（A-19 追記）と base/ を先に直す。
- JSONEncoder のキー順は実行ごとに変わるため、期待出力に JSON 全文を書かない。
- Optional<StockMode> の .none と StockMode.none は衝突する。if let で取り出してから switch する。
- 用語は「sats確認済み」で統一（「sats受領済み」は使わない）。
- 02_練習メニュー.md は指示がない限り変更しない。
- 変更はコミットしない（ユーザーが git diff を確認してコミットする）。

## 現状（完了済み）
### siyou.md
A-19（実装上の決定事項）を追記済み:
- A-19-1 現在庫の正は products.stock、stock_movements は差分ログ。Σdelta == stock が不変条件
- A-19-2 中断は「sats確認済みか」で決定（未確認=PIN不要・記録なし／確認済み=PIN必須・voided で記録）
- A-19-3 在庫を戻す条件は completed_at がある場合のみ
- A-19-4 ID採番: S-YYYYMMDD-NNN / {sale_id}-{n:02} / M-{連番:06}。採番は完了時のみ
- A-19-5 日時は ISO 8601（TEXT、Swift は Date）。日次集計はローカル日付
- A-19-6 PIN は Keychain
- A-19-7 集計で販売取消と sats確認済み中断を分離
- A-19-8 方法選び直しは2段（sats待ち → 支払方法選択 → 現金入力中）ほか
- A-19-9 stockMode は ProductType のみが持つ
- A-19-10 野良ID は ADHOC-{連番:02}、追加時に採番
- A-19-11 集計対象日は completed_at ?? confirmed_at

### base/
00_README.md / 1_仕様調査.md / 2_型定義.md / 3_標準ロジック.md / 4_受け入れテスト対応.md / 5_カート編集.md / 6_会計の状態機械.md / Types.swift / verify.py
- CartLine は平坦形（id, typeId, name, unitPriceJpy, unitPriceSats, qty, isAdhoc）。在庫を持たない。
- SaleState は8状態（中断を含む）。Move = allowed / needsConfirm / needsPIN / rejected。
- Sale は CodingKeys で sale_id 等の列名に対応済み。

### レッスン（base 参照の差分レッスン化済み）
07 08 09 10 11 12 15 16 17 18 19 20 22 28 29 30 31 38 40 41 47 56 57 58
新設: 61_画面遷移とモーダルを使う.md（56 から分離）
部分対応: 03_レッスン.md（レッスン2・4・6・8 を base 参照に。NO_VERIFY）
verify.py は直近 42/42 OK（登録24レッスン）。

### 直した既存バグ（参考）
49 のコンパイルエラーと期待出力の不一致／58 の検証なし減算／57-5 と 59 の対象判定重複／
ID採番の仕様違反（41 38 47 57）／20 の属性位置ずれ／02 のリンク切れ4件。

## 中断時点
24_IDを採番する.md を書き始めた直後。
- base/ に products.product_id の採番（siyou.md A-18 で規定済み）が無いことを発見した。
- 24 が書きかけか未作成かは未確認。まずファイルの有無と内容を確認すること。

## 次にやること（この順で）
1. base/2_型定義.md に product_id 採番を追加し、Types.swift を再生成して検証。
2. 24 を IdSequencer（採番5種: sale / item / movement / adhoc / product）の差分レッスンとして書く。verify.py に登録。
3. 34（base/6 §7 cashDueJpy、11 との差分）。
4. 42（base/3 §7 と TypeTotal、種類別の内訳）。
5. 25（PaidIn）／32（attrLabel1..3）／33（base/3 §1、16 と重複注意）／35（resolveMethod）。
6. SwiftUI の型差し替え: 14 / 54 / 55 / 61（ロジック差分なし。型宣言を base に合わせる）。
7. 全レッスンで旧命名の残存を再スキャン: Sale.saleId、StockMovement.productID / saleID、priceJpy（CartLine 側）、M-%03d など。
8. base/4_受け入れテスト対応.md を更新（解消した C-6 項目の反映）。残る穴: 確認ダイアログ SwiftUI 側（#49 #50 #51）。
9. lesson/08.swift（手書き作業ファイル、旧 CartLine のまま）の扱いをユーザーに確認。
10. 最後に verify.py 全体と、非日本語文字の混入スキャンを実行し、結果を報告。

## 触らない方針（base 化しない）
01-1〜03（Swift入門）／13 23 26 39（CSV）／43〜46 48（写真）／49〜53 59 60（Swift言語）／21 27 37。
理由: base の型に依存しない独立領域。ただし、命名の旧表記が残っていれば修正対象。

## 報告形式
1本完了するごとに、(a) 何を変えたか (b) 検証で見つけた問題 (c) verify.py の結果 を簡潔に報告し、止まらず次へ進むこと。