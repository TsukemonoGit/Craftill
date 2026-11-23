# flea-inventory-ingest

Craftill（macOS レジアプリ）が送信する**公開商品スナップショット**を受け取り、検証して Cloudflare KV に保存する Worker です。表示用 Web の [`flea-inventory-view`](../flea-inventory-view/) は、この Worker が書き込んだ同じ KV を読み取ります。

- 実行環境: Cloudflare Workers
- 実装: 素の JavaScript（ES Modules、ビルド不要）
- 保存先: Cloudflare KV `inventory:v1`
- 順序管理: Durable Object `InventoryStore`（単一インスタンス）

## 役割

1. `Authorization: Bearer <WRITE_SECRET>` で送信元を認証する
2. JSON スナップショットの形を検証する
3. `created_at` と `revision` で新旧を判定し、古い送信を拒否する
4. 最新のスナップショットだけを KV に保存する
5. 並行リクエストや遅延再送があっても、在庫が巻き戻らないようにする

```
Craftill (macOS)
    │  POST /ingest  (Bearer 認証 + JSON)
    ▼
flea-inventory-ingest (Worker)
    │  検証・順序判定・直列化
    ▼
Durable Object InventoryStore ── 順序 (snapshot_order)
    │  KV へ保存（失敗時は再試行／ロールバック）
    ▼
Cloudflare KV  inventory:v1
    │
    ▼
flea-inventory-view (Worker) ── GET /api/snapshot ── ブラウザ
```

## エンドポイント

| メソッド | パス      | 用途                                         |
| -------- | --------- | -------------------------------------------- |
| `POST`   | `/ingest` | 通常のスナップショット受信                   |
| `POST`   | `/init`   | 順序情報を失ったときの復旧用。通常は使わない |

上記以外のパス・メソッドは `404 Not Found` です。`/ingest` と `/init` はどちらも Bearer 認証が必要です。

### 認証

`WRITE_SECRET` 環境変数（Worker Secret）と完全に一致するトークンを要求します。

```http
Authorization: Bearer <WRITE_SECRET>
```

- 不一致・未指定: `401 Unauthorized`
- `WRITE_SECRET` が未設定・空: `500 Server Misconfigured`

## 送信されるスナップショット

```json
{
  "created_at": "2026-11-29T12:34:56.789Z",
  "revision": 42,
  "types": [
    {
      "type_id": "sticker",
      "name": "ステッカー",
      "stock_mode": "counted",
      "attr_labels": ["色", "模様"]
    }
  ],
  "products": [
    {
      "product_id": "ST-001",
      "type_id": "sticker",
      "name": "ステッカー まる",
      "price_jpy": 300,
      "price_sats": 500,
      "attrs": ["黄", "まる"],
      "stock": 10,
      "has_image": true
    }
  ]
}
```

### 検証ルール

`src/index.js` の `isValidSnapshot` で以下を検査します。1つでも外れると `400 Bad Request` です。

- `created_at`: `Date.parse` できる文字列
- `revision`: 任意。0 以上の整数。省略時は `0` として扱う（旧版のアプリを想定）
- `types`: 配列。各要素は以下を満たす
  - `type_id`, `name`: 文字列
  - `stock_mode`: `counted` / `unique` / `none` のいずれか
  - `attr_labels`: 文字列の配列
- `products`: 配列。各要素は以下を満たす
  - `product_id`, `type_id`, `name`: 文字列
  - `price_jpy`: 整数
  - `price_sats`: 任意。整数
  - `attrs`: 配列。各要素は文字列または `null`
  - `stock`: 任意。整数（`null` 可）
  - `has_image`: 真偽値
- 各商品の `type_id` が `types` に存在すること

未知のフィールドはそのまま保存されます。`type_id` / `product_id` の重複は検査していません。

### 未来の `created_at`

端末の時計が大きく進んでいると、未来の時刻が保存され、以後の正しい送信がすべて Stale になって復旧できなくなります。そのため、受信時刻より **5分を超えて未来** の `created_at` は、サーバーの受信時刻に丸めてから保存します（`MAX_FUTURE_SKEW_MS`）。

## 保存と順序管理

### KV と Durable Object

| 保存場所                          | キー             | 内容                                      |
| --------------------------------- | ---------------- | ----------------------------------------- |
| Cloudflare KV                     | `inventory:v1`   | 公開用スナップショットの JSON             |
| Durable Object の storage         | `snapshot_order` | `{ at, revision }`（判定用の順序）        |
| Durable Object の storage（旧版） | `created_at`     | 旧版が残した ISO 文字列。移行時に読み取り |

順序判定と保存は、`idFromName("inventory:v1")` で固定した**単一の Durable Object** に集約しています。さらに DO 内でも Promise チェーンでリクエストを直列化しているため、並行送信で古いスナップショットが新しいものを上書きしません。

### 新旧判定

順序は `(created_at, revision)` の辞書順で比較します。

- 保存済みより新しい: 受け付けて保存
- 保存済みより古い: `409 Stale`
- `created_at` と `revision` が完全に同じ: 再送とみなして受け付ける（冪等）

`created_at` はミリ秒付き ISO 8601 を想定していますが、文字列そのものではなく `Date.parse` したミリ秒で比較します。`revision` は同じミリ秒に複数回送った場合の識別子で、アプリ側が送信のたびに増やします。

### 初回・移行時の起点

通常の `/ingest` で DO に順序がない場合、次の順で起点を作ります。

1. 旧版の `created_at` が DO に残っていれば、それを `revision: -1` として引き継ぐ
2. なければ KV の最後の公開値を**一度だけ**読む
3. KV の値が現在より 5分を超えて古い場合は、`now - 5分` を起点にする（`MAX_SEND_AGE_MS`）

KV は反映が遅れるため、毎回の比較には使いません。古い KV 値を毎回の基準にすると、その値と実際の保存値の間のスナップショットを受け入れてしまい、新しい公開在庫を上書きするおそれがあるためです。

### KV 書き込みの失敗時

1. 先に DO の順序を更新する
2. KV へ書き込む
3. KV が失敗したら順序を元に戻し、`503 Storage Unavailable` を返す

KV 書き込みは `429` / `5xx` / 一時的な接続断のときだけ、200ms → 500ms → 1000ms 間隔で最大3回再試行します（`KV_RETRY_DELAYS_MS`）。順序を戻さないと、KV に入っていない順序だけが残り、再送が `409` になったり古い内容が採用されたりするためです。

### `/init` の違い

`/init` は運用者が明示的に呼ぶ復旧用エンドポイントです。

- 順序が**ない**場合: KV の公開値と比較し、それより古くなければ初期化する。KV に値がない、読めない、または壊れている場合は復旧を優先して受け付ける
- 順序が**ある**場合: 通常の受信と同じく、それより古いスナップショットは `409`
- `/ingest` の初回起点と違い、KV の値が古くても `now - 5分` を下限にはしない

既存の順序を強制的に上書きするものではありません。

## レスポンス

| ステータス | 本文                   | 意味                                                   |
| ---------- | ---------------------- | ------------------------------------------------------ |
| `200`      | `OK`                   | 保存した                                               |
| `400`      | `Bad Request`          | JSON が壊れている、または検証に失敗                    |
| `401`      | `Unauthorized`         | トークン不一致                                         |
| `404`      | `Not Found`            | パス・メソッドが違う                                   |
| `409`      | `Stale`                | 保存済みより古いスナップショット                       |
| `500`      | `Server Misconfigured` | `WRITE_SECRET` が未設定                                |
| `503`      | `Storage Unavailable`  | 順序の読み取り失敗、または KV 書き込みの再試行が尽きた |

レスポンスは JSON ではなくプレーンテキストです。レジアプリは `409` かつ本文が `Stale` の場合を「新しいデータがサイト側にある」と判定します。`503` や `429` などは再送可能として扱われます。

## セットアップ

必要なもの:

- Node.js / npm
- Cloudflare アカウント
- `wrangler`（`npx wrangler` で実行可能）

### 1. KV ネームスペースを用意する

```sh
cd web/flea-inventory-ingest
npx wrangler kv namespace create INVENTORY_KV
```

表示される `id` を `wrangler.jsonc` の `kv_namespaces[].id` に設定します。**`flea-inventory-view` 側も同じ ID にしてください。**

### 2. 認証トークンを設定する

```sh
npx wrangler secret put WRITE_SECRET
```

十分に長いランダムな文字列を入力します。レジアプリの「認証トークン」には同じ値を設定します。

### 3. デプロイする

```sh
npx wrangler deploy
```

`wrangler.jsonc` には Durable Object のマイグレーション（`v1`, `new_sqlite_classes: ["InventoryStore"]`）が設定済みです。初回デプロイ時に作成されます。

### ローカルで動かす

```sh
# .dev.vars にローカル用のシークレットを置く（コミットしない）
echo 'WRITE_SECRET=dev-secret' > .dev.vars

npx wrangler dev
```

別のターミナルから送信して確認できます。

```sh
curl -i -X POST http://localhost:8787/ingest \
  -H 'Authorization: Bearer dev-secret' \
  -H 'Content-Type: application/json' \
  --data-binary @snapshot.json
```

## ファイル構成

| パス             | 内容                                                              |
| ---------------- | ----------------------------------------------------------------- |
| `src/index.js`   | Worker 本体。認証、検証、順序管理、KV 書き込み                    |
| `wrangler.jsonc` | Worker 名、KV・Durable Object バインディング、マイグレーション    |
| `kv_out.txt`     | KV の内容を確認したときのスナップショットの控え（動作には未使用） |

## 運用メモ

- `WRITE_SECRET` が漏えいしたら `npx wrangler secret put WRITE_SECRET` で再発行し、レジアプリ側のトークンも更新してください。
- `/init` は通常の送信経路ではありません。順序情報を失ったときだけ、運用者が内容を確認したうえで使います。
- KV は結果整合なので、保存直後に表示 Web へ反映されないことがあります。順序判定は強整合な DO の storage で行っています。
- この Worker は CORS ヘッダーを返しません。ブラウザから直接呼ぶのではなく、レジアプリ（URLSession）から送信する前提です。

## 関連

- リポジトリ全体の説明: [`../../README.md`](../../README.md)
- 表示用 Web: [`../flea-inventory-view/`](../flea-inventory-view/)
