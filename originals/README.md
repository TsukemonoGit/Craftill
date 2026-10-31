# originals（画像の原本）

A-17 の画像ビルド用に、商品IDと同名の画像をここへ置きます（例: `MK-008.jpg`）。

1. アプリで商品を登録し、商品マスタ CSV を書き出す。
2. 原本を `originals/<商品ID>.<拡張子>` で置く。
3. リポジトリ直下で実行する。

```sh
python3 scripts/build_images.py --csv ~/Downloads/products.csv
```

`Craftill/Craftill/Images/` にレジ用、`web/public/images/` に Web 用の画像と
対応一覧・版識別子が生成されます。原本と生成物はコミットしません（原本は別の場所へ
バックアップしてください）。生成物の詳細は `scripts/build_images.py` を参照してください。
