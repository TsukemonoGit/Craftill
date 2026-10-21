# 実装用の設計図

### 1. データモデル (ER図)
`product_types` テーブルが `next_no`（高水位）を保持し、採番のソースとなる点を明示しています。

```mermaid
erDiagram
    PRODUCT_GROUPS ||--o{ PRODUCT_TYPES : "has"
    PRODUCT_TYPES ||--o{ PRODUCTS : "defines"
    PRODUCTS ||--o{ SALE_ITEMS : "included_in"
    SALES ||--o{ SALE_ITEMS : "contains"
    PRODUCTS ||--o{ STOCK_MOVEMENTS : "tracks"
    SALES ||--o| STOCK_MOVEMENTS : "triggers"

    PRODUCT_GROUPS {
        string group_id PK
        string label
    }
    PRODUCT_TYPES {
        string type_id PK
        string name
        string id_prefix
        int id_digits
        string stock_mode
        string group_id FK
        int next_no "High Water Mark (採番ソース)"
    }
    PRODUCTS {
        string product_id PK
        string type_id FK
        string name
        int price_jpy
        int price_sats
        int stock
        boolean is_public
    }
    SALES {
        string sale_id PK
        string status
        string method
        int total_jpy
        int total_sats
        datetime completed_at
        datetime confirmed_at
    }
    SALE_ITEMS {
        string item_id PK
        string sale_id FK
        string product_id FK
        string item_type
        int qty
        int unit_price_jpy
        int unit_price_sats
        string paid_in
    }
    STOCK_MOVEMENTS {
        int id PK
        string product_id FK
        int delta
        string reason
        string sale_id FK
    }
```

### 2. 商品追加・採番シーケンス
`next_no` を読み取り、商品を挿入し、`next_no` をインクリメントする一連の処理が**単一トランザクション**で行われることを示しています。これにより、競合や欠番の不正利用を防ぎます。

```mermaid
sequenceDiagram
    participant User as 店主
    participant UI as アプリ画面
    participant DB as SQLite

    User->>UI: 商品追加 (種類: mono_kh)
    
    rect rgb(240, 248, 255)
        Note over UI,DB: トランザクション開始 (BEGIN IMMEDIATE)
        UI->>DB: SELECT next_no FROM product_types WHERE type_id='mono_kh'
        DB-->>UI: current_no (例: 8)
        
        UI->>UI: ID生成 ("MK-008")
        UI->>DB: INSERT INTO products (id="MK-008", ...)
        
        UI->>DB: UPDATE product_types SET next_no = 9 WHERE type_id='mono_kh'
        UI->>DB: COMMIT
    end
    
    DB-->>UI: 成功
    UI-->>User: 登録完了 (ID: MK-008)
```

### 3. システム構成図
MacBook Neo内で完結する領域と、手動連携（WoS）、非同期連携（Cloudflare）の境界を定義します。

```mermaid
flowchart TB
    subgraph Neo[MacBook Neo (Offline First)]
        App[レジアプリ]
        DB[(SQLite\nnext_no管理)]
        Cam[内蔵カメラ]
        UI[タッチ-less UI]
        File[画像リソース\n(ビルド時同梱)]
    end

    subgraph External[外部連携]
        WoS[WoS App\n(自己管理型)]
        CF[Cloudflare KV\n(公開用)]
        DevMac[開発用Mac\n(画像ビルド)]
    end

    User((店主))
    Customer((客))

    User -- "操作/QRスキャン" --> Neo
    Customer -- "現金/sats支払い" --> User
    
    App -- "Read/Write" --> DB
    App -- "スキャン" --> Cam
    App -- "表示" --> UI
    
    App -. "クリップボード\n(sats額)" .-> WoS
    App -. "目視確認\n(Invoice/入金)" .-> WoS
    
    App -- "スナップショット送信\n(HTTPS/Secret)" --> CF
    DevMac -- "画像デプロイ\n(手動)" --> CF
    
    DevMac -- "原本画像" --> File
```

### 4. 会計状態遷移図
仕様書 A-4 に基づく状態遷移です。`sats確認済み` という状態が、中断時の挙動（記録を残す）にどう影響するかを構造化しています。

```mermaid
stateDiagram-v2
    [*] --> 待機中
    待機中 --> スキャン中: 初回の商品追加
    スキャン中 --> スキャン中: 商品追加・取消
    スキャン中 --> 待機中: カートが空
    スキャン中 --> 中断: 会計中断（確認あり）
    スキャン中 --> 支払方法選択: 会計へ進む
    支払方法選択 --> スキャン中: 戻る
    支払方法選択 --> 中断: 会計中断（確認あり）
    支払方法選択 --> 現金入力中: 現金
    支払方法選択 --> sats待ち: sats払い
    現金入力中 --> 完了: 受取額が請求額以上で確定
    現金入力中 --> 中断: 会計中断（確認あり）
    sats待ち --> 完了: 済ボタン確認後（現金分なし）
    sats待ち --> 併用現金入力中: 済ボタン確認後（現金分あり）
    sats待ち --> 支払方法選択: 方法選び直し
    sats待ち --> 中断: キャンセル（確認あり）
    併用現金入力中 --> 完了: 受取額が現金分以上で確定
    併用現金入力中 --> 中断: 会計中断（PIN必須・記録あり）
    完了 --> 待機中
    中断 --> 待機中
```
