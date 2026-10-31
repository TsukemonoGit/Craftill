# originals（画像の原本）

A-17 の画像ビルド用に、商品IDと同名の画像をここへ置きます（例: `MK-008.jpg`）。

## アプリから直接保存する

アプリの「機能メニュー → 商品マスタ → 画像の保存先」で、この `originals/` フォルダを
選んでください。商品編集画面の「商品写真」から撮影・選択した写真が、
`originals/<商品ID>.jpg` に保存されます。カメラ撮影もファイル選択も同じフォルダです。

- アプリ内にも表示用のコピーを保存するため、フォルダを外してもレジには表示されます。
- アプリが保存する写真は JPEG（長辺1600px）にそろえます。
- フォルダを変更しても既存の写真は自動では移動しません。「画像の保存先」画面の
  「既存の写真をこのフォルダへ書き出す」でまとめて書き出せます。

## 手動で置く場合

1. アプリで商品を登録し、商品マスタ CSV を書き出す。
2. 原本を `originals/<商品ID>.<拡張子>` で置く。
3. リポジトリ直下で実行する。

```sh
python3 scripts/build_images.py --csv ~/Downloads/products.csv
```

`Craftill/Craftill/Images/` にレジ用、`web/public/images/` に Web 用の画像と
対応一覧・版識別子が生成されます。原本と生成物はコミットしません（原本は別の場所へ
バックアップしてください）。生成物の詳細は `scripts/build_images.py` を参照してください。

別のフォルダを保存先にした場合は、`--originals` にそのフォルダを指定します。

```sh
python3 scripts/build_images.py --csv ~/Downloads/products.csv --originals "/path/to/images"
```
