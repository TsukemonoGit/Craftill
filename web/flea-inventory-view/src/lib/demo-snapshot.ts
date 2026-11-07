export type StockMode = 'counted' | 'unique' | 'none';

export type SnapType = {
	type_id: string;
	name: string;
	stock_mode: StockMode;
	attr_labels: string[];
};

export type SnapProduct = {
	product_id: string;
	type_id: string;
	name: string;
	price_jpy: number;
	price_sats?: number;
	stock?: number | null;
	attrs: (string | null)[];
	has_image: boolean;
};

export type Snapshot = {
	created_at: string;
	types: SnapType[];
	products: SnapProduct[];
};

const demoTypes: SnapType[] = [
	{
		type_id: 'keyholder',
		name: 'キーホルダー',
		stock_mode: 'unique',
		attr_labels: ['カラー', '素材']
	},
	{ type_id: 'sticker', name: 'シール', stock_mode: 'counted', attr_labels: ['サイズ'] },
	{ type_id: 'strap', name: 'ストラップ', stock_mode: 'counted', attr_labels: ['カラー'] },
	{ type_id: 'misc', name: 'ちいさな雑貨', stock_mode: 'none', attr_labels: [] }
];

const demoProducts: SnapProduct[] = [
	{
		product_id: 'MNKH-01',
		type_id: 'keyholder',
		name: 'まるいおやつ キーホルダー',
		price_jpy: 800,
		price_sats: 620,
		stock: 1,
		attrs: ['レモン', 'アクリル'],
		has_image: true
	},
	{
		product_id: 'MNKH-02',
		type_id: 'keyholder',
		name: 'しあわせのたまご',
		price_jpy: 900,
		stock: 1,
		attrs: ['たまご', 'アクリル'],
		has_image: true
	},
	{
		product_id: 'MNKH-03',
		type_id: 'keyholder',
		name: 'よるのうさぎ',
		price_jpy: 1100,
		stock: 1,
		attrs: ['よる', 'アクリル'],
		has_image: true
	},
	{
		product_id: 'MNKH-04',
		type_id: 'keyholder',
		name: 'おやつ! キーホルダー',
		price_jpy: 750,
		stock: 1,
		attrs: ['ミント', 'アクリル'],
		has_image: true
	},
	{
		product_id: 'MNKH-05',
		type_id: 'keyholder',
		name: 'ギョザー! キーホルダー',
		price_jpy: 750,
		stock: 1,
		attrs: ['ブルー', 'アクリル'],
		has_image: true
	},
	{
		product_id: 'MNKH-06',
		type_id: 'keyholder',
		name: 'ぽてぽてハムスター',
		price_jpy: 850,
		stock: 1,
		attrs: ['ちゃいろ', 'アクリル'],
		has_image: true
	},
	{
		product_id: 'LYKH-01',
		type_id: 'keyholder',
		name: 'キラキラ星のチャーム',
		price_jpy: 1000,
		price_sats: 780,
		stock: 0,
		attrs: ['ミックス', 'アクリル'],
		has_image: true
	},
	{
		product_id: 'LYKH-02',
		type_id: 'keyholder',
		name: 'おおきなねこ',
		price_jpy: 1500,
		stock: 1,
		attrs: ['きいろ', 'アクリル'],
		has_image: true
	},
	{
		product_id: 'MNST-01',
		type_id: 'sticker',
		name: 'まるいおやつ シール',
		price_jpy: 300,
		stock: 12,
		attrs: ['小'],
		has_image: true
	},
	{
		product_id: 'KMST-01',
		type_id: 'sticker',
		name: 'ことばのシールセット',
		price_jpy: 500,
		price_sats: 390,
		stock: 8,
		attrs: ['大'],
		has_image: true
	},
	{
		product_id: 'KMST-02',
		type_id: 'sticker',
		name: 'ぽちぽちシール',
		price_jpy: 400,
		stock: 0,
		attrs: ['小'],
		has_image: true
	},
	{
		product_id: 'LYNKH-01',
		type_id: 'strap',
		name: 'てづくりストラップ',
		price_jpy: 1200,
		price_sats: 930,
		stock: 3,
		attrs: ['ミックス'],
		has_image: true
	},
	{
		product_id: 'MISC-01',
		type_id: 'misc',
		name: 'てづくりポストカード',
		price_jpy: 250,
		stock: null,
		attrs: [],
		has_image: false
	}
];

/**
 * 開発サーバー（`npm run dev`）では KV の在庫を取得できないため、
 * 表示確認用のテストデータを返す。本番ビルドでは使われない。
 */
export function makeDemoSnapshot(): Snapshot {
	return {
		created_at: new Date().toISOString(),
		types: demoTypes,
		products: demoProducts
	};
}
