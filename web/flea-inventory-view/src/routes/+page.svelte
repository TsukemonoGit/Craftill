<script lang="ts">
	import { onMount } from 'svelte';

	type SnapType = {
		type_id: string;
		name: string;
		stock_mode: 'counted' | 'unique' | 'none';
		attr_labels: string[];
	};
	type SnapProduct = {
		product_id: string;
		type_id: string;
		name: string;
		price_jpy: number;
		price_sats?: number;
		stock?: number | null;
		attrs: (string | null)[];
		has_image: boolean;
	};
	type Snapshot = {
		created_at: string;
		types: SnapType[];
		products: SnapProduct[];
	};
	type StockDisplay = { label: string; soldOut: boolean; mode: SnapType['stock_mode'] };
	type StockFilter = 'all' | 'in_stock' | 'sold_out';

	const yenFormatter = new Intl.NumberFormat('ja-JP');
	const skeletonItems = Array.from({ length: 8 }, (_, i) => i);
	const RELOAD_COOLDOWN_MS = 60_000;

	let snapshot = $state<Snapshot | null>(null);
	let error = $state('');
	let loading = $state(false);
	let imageVersion = $state('');
	let failedImages = $state<Record<string, boolean>>({});
	let stockFilter = $state<StockFilter>('all');
	let coolingDown = $state(false);
	let cooldownTimer: ReturnType<typeof setTimeout> | undefined;

	const reloadDisabled = $derived(loading || coolingDown);

	async function load() {
		if (reloadDisabled) return;
		coolingDown = true;
		cooldownTimer = setTimeout(() => {
			coolingDown = false;
		}, RELOAD_COOLDOWN_MS);
		loading = true;
		error = '';
		try {
			const res = await fetch('/api/snapshot', { cache: 'no-store' });
			if (!res.ok) throw new Error(`HTTP ${res.status}`);
			snapshot = await res.json();
			failedImages = {};
		} catch (e) {
			error = `取得に失敗しました: ${e instanceof Error ? e.message : String(e)}`;
		} finally {
			loading = false;
		}
	}

	async function loadImageVersion() {
		try {
			const res = await fetch('/images/version.txt', { cache: 'no-store' });
			if (!res.ok) return;
			const text = (await res.text()).trim();
			if (text) imageVersion = text;
		} catch {
			// 版識別子は任意。取得できなくても表示に影響させない。
		}
	}

	onMount(() => {
		load();
		loadImageVersion();
		return () => {
			if (cooldownTimer) clearTimeout(cooldownTimer);
		};
	});

	const typeById = $derived(new Map((snapshot?.types ?? []).map((t) => [t.type_id, t] as const)));

	const filterCounts = $derived.by(() => {
		let inStock = 0;
		let soldOut = 0;
		for (const p of snapshot?.products ?? []) {
			const t = typeById.get(p.type_id);
			if (!t) continue;
			if (isSoldOut(t.stock_mode, p.stock)) soldOut++;
			else inStock++;
		}
		return { all: inStock + soldOut, inStock, soldOut };
	});

	const groups = $derived(
		snapshot
			? snapshot.types
					.map((t) => ({
						type: t,
						products: snapshot!.products
							.filter((p) => p.type_id === t.type_id && matchesStockFilter(t, p))
							.sort((a, b) => a.product_id.localeCompare(b.product_id))
					}))
					.filter((g) => g.products.length > 0)
			: []
	);

	const totalCount = $derived(snapshot ? snapshot.products.length : 0);
	const shownCount = $derived(groups.reduce((sum, g) => sum + g.products.length, 0));

	const updatedAt = $derived(
		snapshot
			? new Date(snapshot.created_at).toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo' })
			: ''
	);

	function isSoldOut(mode: SnapType['stock_mode'], stock: number | null | undefined): boolean {
		if (mode === 'none') return false;
		return (stock ?? 0) <= 0;
	}

	function matchesStockFilter(type: SnapType, product: SnapProduct): boolean {
		if (stockFilter === 'all') return true;
		const soldOut = isSoldOut(type.stock_mode, product.stock);
		return stockFilter === 'sold_out' ? soldOut : !soldOut;
	}

	function filterButtonClass(value: StockFilter): string {
		return value === stockFilter
			? 'bg-stone-900 text-white shadow-sm'
			: 'text-stone-600 hover:bg-stone-100';
	}

	function stockDisplay(
		mode: SnapType['stock_mode'],
		stock: number | null | undefined
	): StockDisplay | null {
		if (mode === 'none') return null;
		const n = stock ?? 0;
		if (n <= 0) return { label: 'SOLD OUT', soldOut: true, mode };
		if (mode === 'unique') return { label: '1点もの', soldOut: false, mode };
		return { label: `残り ${n}個`, soldOut: false, mode };
	}

	function hasSats(p: SnapProduct): boolean {
		return typeof p.price_sats === 'number' && p.price_sats > 0;
	}

	function attributePairs(type: SnapType, p: SnapProduct) {
		return p.attrs
			.map((value, i) => ({ label: type.attr_labels[i] ?? '', value }))
			.filter(
				(a): a is { label: string; value: string } =>
					typeof a.value === 'string' && a.value.trim() !== ''
			);
	}

	function imageUrl(productId: string): string {
		return `/images/${encodeURIComponent(productId)}.jpg`;
	}

	function showImage(p: SnapProduct): boolean {
		return p.has_image && !failedImages[p.product_id];
	}

	function markImageFailed(productId: string) {
		if (!failedImages[productId]) {
			failedImages = { ...failedImages, [productId]: true };
		}
	}

	function stockBadgeClass(stock: StockDisplay): string {
		return stock.mode === 'unique'
			? 'border-amber-200 bg-amber-50 text-amber-800'
			: 'border-emerald-200 bg-emerald-50 text-emerald-800';
	}
</script>

<svelte:head>
	<title>商品一覧</title>
	<meta name="description" content="Craftill の公開商品と在庫の一覧です。" />
</svelte:head>

<div class="min-h-screen bg-stone-50 text-stone-900">
	<header class="sticky top-0 z-10 border-b border-stone-200 bg-white/85 backdrop-blur">
		<div
			class="mx-auto flex max-w-6xl flex-col gap-3 px-4 py-4 sm:flex-row sm:items-end sm:justify-between"
		>
			<div>
				<h1 class="text-xl font-bold tracking-tight">商品一覧</h1>
				<p class="mt-1 text-xs text-stone-500">
					最終更新: {updatedAt || '未取得'}{#if snapshot}<span class="ml-2">全 {totalCount} 点</span
						>{/if}
				</p>
			</div>
			<div class="flex items-center gap-3">
				{#if imageVersion}
					<span class="text-[11px] text-stone-400">画像版 {imageVersion}</span>
				{/if}
				<button
					type="button"
					onclick={load}
					disabled={reloadDisabled}
					class="rounded-lg border border-stone-300 bg-white px-3 py-1.5 text-sm font-medium text-stone-700 shadow-sm transition hover:border-stone-400 hover:bg-stone-50 disabled:cursor-not-allowed disabled:opacity-60"
				>
					{loading ? '取得中…' : '再読み込み'}
				</button>
			</div>
		</div>
	</header>

	<main class="mx-auto max-w-6xl px-4 py-6">
		<p class="mb-6 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">
			送信が遅れている間、在庫表示が古い可能性があります。
		</p>

		{#if snapshot}
			<div class="mb-6 flex flex-wrap items-center justify-between gap-3">
				<div
					class="inline-flex rounded-lg border border-stone-200 bg-white p-1 shadow-sm"
					role="group"
					aria-label="在庫で絞り込み"
				>
					<button
						type="button"
						aria-pressed={stockFilter === 'all'}
						onclick={() => (stockFilter = 'all')}
						class="rounded-md px-3 py-1.5 text-sm font-medium transition {filterButtonClass('all')}"
					>
						全体 <span class="ml-0.5 text-xs opacity-70">{filterCounts.all}</span>
					</button>
					<button
						type="button"
						aria-pressed={stockFilter === 'in_stock'}
						onclick={() => (stockFilter = 'in_stock')}
						class="rounded-md px-3 py-1.5 text-sm font-medium transition {filterButtonClass(
							'in_stock'
						)}"
					>
						在庫あり <span class="ml-0.5 text-xs opacity-70">{filterCounts.inStock}</span>
					</button>
					<button
						type="button"
						aria-pressed={stockFilter === 'sold_out'}
						onclick={() => (stockFilter = 'sold_out')}
						class="rounded-md px-3 py-1.5 text-sm font-medium transition {filterButtonClass(
							'sold_out'
						)}"
					>
						在庫なし <span class="ml-0.5 text-xs opacity-70">{filterCounts.soldOut}</span>
					</button>
				</div>
				<p class="text-xs text-stone-500">{shownCount} 点を表示中</p>
			</div>
		{/if}

		{#if error}
			<div class="mb-6 rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
				<p>{error}</p>
				<button
					type="button"
					onclick={load}
					disabled={reloadDisabled}
					class="mt-3 rounded-md border border-red-300 bg-white px-3 py-1.5 text-sm font-medium text-red-800 transition hover:bg-red-100 disabled:cursor-not-allowed disabled:opacity-60"
				>
					再試行
				</button>
			</div>
		{/if}

		{#if loading && !snapshot}
			<div
				class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5"
				aria-hidden="true"
			>
				{#each skeletonItems as item (item)}
					<div class="overflow-hidden rounded-xl border border-stone-200 bg-white shadow-sm">
						<div class="aspect-square animate-pulse bg-stone-200"></div>
						<div class="space-y-2 p-3">
							<div class="h-2.5 w-1/3 animate-pulse rounded bg-stone-200"></div>
							<div class="h-3.5 w-4/5 animate-pulse rounded bg-stone-200"></div>
							<div class="h-4 w-2/5 animate-pulse rounded bg-stone-200"></div>
						</div>
					</div>
				{/each}
			</div>
		{:else if snapshot && snapshot.products.length === 0}
			<p class="py-16 text-center text-sm text-stone-500">公開中の商品はありません。</p>
		{:else if snapshot && groups.length === 0}
			<p class="py-16 text-center text-sm text-stone-500">条件に一致する商品はありません。</p>
		{:else}
			<div class="space-y-10">
				{#each groups as g (g.type.type_id)}
					<section>
						<div class="mb-4 flex items-end justify-between border-b border-stone-200 pb-2">
							<h2 class="text-lg font-semibold tracking-tight">{g.type.name}</h2>
							<span class="text-xs text-stone-500">{g.products.length} 点</span>
						</div>

						<ul class="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
							{#each g.products as p (p.product_id)}
								{@const stock = stockDisplay(g.type.stock_mode, p.stock)}
								{@const attrs = attributePairs(g.type, p)}
								<li>
									<article
										class="group flex h-full flex-col overflow-hidden rounded-xl border border-stone-200 bg-white shadow-sm transition hover:shadow-md {stock?.soldOut
											? 'opacity-80'
											: ''}"
									>
										<div class="relative aspect-square overflow-hidden bg-stone-100">
											{#if showImage(p)}
												<img
													src={imageUrl(p.product_id)}
													alt={p.name}
													loading="lazy"
													decoding="async"
													class="h-full w-full object-cover transition duration-300 group-hover:scale-105"
													onerror={() => markImageFailed(p.product_id)}
												/>
											{:else}
												<div
													class="flex h-full flex-col items-center justify-center gap-2 bg-gradient-to-br from-stone-100 to-stone-200 p-4 text-center"
												>
													<svg
														xmlns="http://www.w3.org/2000/svg"
														viewBox="0 0 24 24"
														fill="none"
														stroke="currentColor"
														stroke-width="1.5"
														class="h-7 w-7 text-stone-400"
														aria-hidden="true"
													>
														<path
															stroke-linecap="round"
															stroke-linejoin="round"
															d="m2.25 15.75 5.159-5.159a2.25 2.25 0 0 1 3.182 0l5.159 5.159m-1.5-1.5 1.409-1.409a2.25 2.25 0 0 1 3.182 0l2.909 2.909M3.75 21h16.5A1.5 1.5 0 0 0 21.75 19.5V4.5A1.5 1.5 0 0 0 20.25 3H3.75A1.5 1.5 0 0 0 2.25 4.5v15A1.5 1.5 0 0 0 3.75 21Z"
														/>
													</svg>
													<p class="line-clamp-3 text-sm font-semibold text-stone-600">
														{p.name}
													</p>
													{#if attrs.length > 0}
														<p class="line-clamp-2 text-xs text-stone-500">
															{attrs.map((a) => a.value).join(' / ')}
														</p>
													{/if}
												</div>
											{/if}

											{#if stock?.soldOut}
												<div
													class="absolute inset-0 flex items-center justify-center bg-stone-900/45"
												>
													<span
														class="rounded-full bg-stone-900/90 px-4 py-1.5 text-sm font-semibold tracking-widest text-white"
													>
														SOLD OUT
													</span>
												</div>
											{/if}
										</div>

										<div class="flex flex-1 flex-col gap-1.5 p-3">
											<p class="text-[11px] font-medium tracking-wide text-stone-400">
												{p.product_id}
											</p>
											<h3 class="text-sm leading-snug font-semibold text-stone-900">{p.name}</h3>

											{#if attrs.length > 0}
												<ul class="flex flex-wrap gap-1">
													{#each attrs as a, i (i)}
														<li
															class="rounded bg-stone-100 px-1.5 py-0.5 text-[11px] text-stone-600"
														>
															{#if a.label}<span class="text-stone-400">{a.label}:</span>{/if}
															{a.value}
														</li>
													{/each}
												</ul>
											{/if}

											<div class="mt-auto flex items-end justify-between gap-2 pt-2">
												<div>
													<p class="text-base font-bold text-stone-900">
														{yenFormatter.format(p.price_jpy)}円
													</p>
													{#if hasSats(p)}
														<p class="text-xs text-stone-500">
															{yenFormatter.format(p.price_sats ?? 0)} sats
														</p>
													{/if}
												</div>
												{#if stock && !stock.soldOut}
													<span
														class="shrink-0 rounded-full border px-2 py-0.5 text-[11px] font-medium {stockBadgeClass(
															stock
														)}"
													>
														{stock.label}
													</span>
												{/if}
											</div>
										</div>
									</article>
								</li>
							{/each}
						</ul>
					</section>
				{/each}
			</div>
		{/if}
	</main>

	<footer class="mx-auto max-w-6xl px-4 pb-8 text-[11px] text-stone-400">
		画像がない商品は、商品名と属性を表示しています。
	</footer>
</div>
