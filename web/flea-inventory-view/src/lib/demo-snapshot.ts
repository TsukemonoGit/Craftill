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
	{ type_id: 'sticker', name: 'ステッカー', stock_mode: 'counted', attr_labels: ['サイズ'] },
	{ type_id: 'magnet', name: 'マグネット', stock_mode: 'counted', attr_labels: ['カラー'] },
	{ type_id: 'seal', name: 'シール', stock_mode: 'counted', attr_labels: ['種類'] },
	{ type_id: 'misc', name: 'ちいさな雑貨', stock_mode: 'none', attr_labels: [] }
];

const demoProducts: SnapProduct[] = [
	{
		product_id: 'MNST-01',
		type_id: 'sticker',
		name: 'お手製 反射ステッカー',
		price_jpy: 500,
		price_sats: 3333,
		stock: 3,
		attrs: ['小'],
		has_image: true
	},
	{
		product_id: 'KMST-01',
		type_id: 'sticker',
		name: 'Kedama Maze ステッカー',
		price_jpy: 100,
		price_sats: 667,
		stock: 20,
		attrs: ['小'],
		has_image: true
	},
	{
		product_id: 'KMST-02',
		type_id: 'sticker',
		name: 'ステッカー（別柄）',
		price_jpy: 100,
		stock: 0,
		attrs: ['小'],
		has_image: true
	},
	{
		product_id: 'MNKH-01',
		type_id: 'keyholder',
		name: 'お手製キーホルダー まるいおやつ',
		price_jpy: 300,
		price_sats: 2000,
		stock: 1,
		attrs: ['レモン', 'レジン'],
		has_image: true
	},
	{
		product_id: 'MNKH-02',
		type_id: 'keyholder',
		name: 'お手製キーホルダー しあわせのたまご',
		price_jpy: 300,
		stock: 1,
		attrs: ['たまご', 'レジン'],
		has_image: true
	},
	{
		product_id: 'MNKH-03',
		type_id: 'keyholder',
		name: 'お手製キーホルダー よるのうさぎ',
		price_jpy: 300,
		stock: 1,
		attrs: ['よる', 'レジン'],
		has_image: true
	},
	{
		product_id: 'MNKH-04',
		type_id: 'keyholder',
		name: 'お手製キーホルダー おやつ!',
		price_jpy: 300,
		stock: 1,
		attrs: ['ミント', 'レジン'],
		has_image: true
	},
	{
		product_id: 'MNKH-05',
		type_id: 'keyholder',
		name: 'お手製キーホルダー ギョザー!',
		price_jpy: 300,
		stock: 1,
		attrs: ['ブルー', 'レジン'],
		has_image: true
	},
	{
		product_id: 'LYKH-01',
		type_id: 'keyholder',
		name: 'NOSTRASIA 2026 アクリルキーホルダー',
		price_jpy: 300,
		stock: 0,
		attrs: ['ミックス', 'アクリル'],
		has_image: true
	},
	{
		product_id: 'LYKH-02',
		type_id: 'keyholder',
		name: 'NOSTRASIA 2026 アクリルキーホルダー（別柄）',
		price_jpy: 300,
		stock: 1,
		attrs: ['ミックス', 'アクリル'],
		has_image: true
	},
	{
		product_id: 'LYNKH-01',
		type_id: 'magnet',
		name: 'NOSTRASIA 2026 マグネット',
		price_jpy: 100,
		price_sats: 667,
		stock: 8,
		attrs: ['ミックス'],
		has_image: true
	},
	{
		product_id: 'MNKH-06',
		type_id: 'magnet',
		name: 'まるいおやつ マグネット',
		price_jpy: 100,
		stock: 5,
		attrs: ['きいろ'],
		has_image: true
	},
	{
		product_id: 'MIS-01',
		type_id: 'seal',
		name: 'シール',
		price_jpy: 50,
		price_sats: 333,
		stock: 30,
		attrs: ['小'],
		has_image: false
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
