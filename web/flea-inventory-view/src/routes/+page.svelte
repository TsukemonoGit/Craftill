<script lang="ts">
	import { onMount } from 'svelte';
	import { dev } from '$app/env';
	import {
		makeDemoSnapshot,
		type Snapshot,
		type SnapType,
		type SnapProduct
	} from '../lib/demo-snapshot';

	type StockDisplay = { label: string; soldOut: boolean; mode: SnapType['stock_mode'] };
	type StockFilter = 'all' | 'in_stock' | 'sold_out';

	const yenFormatter = new Intl.NumberFormat('ja-JP');
	const skeletonItems = Array.from({ length: 8 }, (_, i) => i);
	const RELOAD_COOLDOWN_MS = 60_000;

	const marqueeBase = [
		'NOSTRASIA 2026',
		'Nostr Conference in Asia',
		'FLEA MARKET',
		'ものや',
		'#nostrasia2026'
	];
	const marqueeItems = [...marqueeBase, ...marqueeBase];

	let snapshot = $state<Snapshot | null>(null);
	let error = $state('');
	let loading = $state(false);
	let imageVersion = $state('');
	let failedImages = $state<Record<string, boolean>>({});
	let stockFilter = $state<StockFilter>('all');
	let coolingDown = $state(false);
	let demoMode = $state(false);
	let cooldownTimer: ReturnType<typeof setTimeout> | undefined;

	const reloadDisabled = $derived(loading || coolingDown);

	function endCooldown() {
		if (cooldownTimer) {
			clearTimeout(cooldownTimer);
			cooldownTimer = undefined;
		}
		coolingDown = false;
	}

	async function load() {
		if (reloadDisabled) return;
		coolingDown = true;
		cooldownTimer = setTimeout(() => {
			coolingDown = false;
			cooldownTimer = undefined;
		}, RELOAD_COOLDOWN_MS);
		loading = true;
		error = '';
		try {
			const res = await fetch('/api/snapshot', { cache: 'no-store' });
			if (!res.ok) throw new Error(`HTTP ${res.status}`);
			snapshot = await res.json();
			failedImages = {};
			demoMode = false;
		} catch (e) {
			if (dev) {
				// 開発サーバーでは KV が無いので、表示確認用のテストデータを使う。
				snapshot = makeDemoSnapshot();
				failedImages = {};
				demoMode = true;
				error = '';
				endCooldown();
			} else {
				error = `取得に失敗しました: ${e instanceof Error ? e.message : String(e)}`;
				endCooldown();
			}
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
			? 'bg-ink text-lemon shadow-[2px_2px_0_0_#fffdf6]'
			: 'text-ink hover:bg-lemon-soft';
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
		return stock.mode === 'unique' ? 'bg-lemon text-ink' : 'bg-paper text-ink';
	}
</script>

<svelte:head>
	<title>ものや | NOSTRASIA 2026 Flea Market</title>
	<meta
		name="description"
		content="NOSTRASIA 2026（Nostr Conference in Asia）のフリーマーケットに出店する「ものや」の商品と在庫の一覧です。"
	/>
	<link rel="preconnect" href="https://fonts.googleapis.com" />
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
	<link
		href="https://fonts.googleapis.com/css2?family=Baloo+2:wght@600;700;800&family=Mochiy+Pop+One&family=Yusei+Magic&family=Zen+Maru+Gothic:wght@400;500;700;900&display=swap"
		rel="stylesheet"
	/>
</svelte:head>

<div class="relative min-h-screen overflow-x-hidden bg-lemon font-round text-ink">
	<div class="dot-grid pointer-events-none fixed inset-0 z-0 opacity-60" aria-hidden="true"></div>

	<div class="relative z-10">
		<!-- 上部マーキー -->
		<div class="overflow-hidden border-b-[3px] border-ink bg-ink py-2 text-lemon">
			<div class="marquee-track flex w-max">
				{#each marqueeItems as word, i (i)}
					<span
						class="flex items-center gap-4 px-4 text-[11px] font-bold tracking-[0.22em] whitespace-nowrap"
					>
						<span class="font-latin font-extrabold">{word}</span>
						<span class="text-lemon/60" aria-hidden="true">✦</span>
					</span>
				{/each}
			</div>
		</div>

		<header class="mx-auto max-w-6xl px-4 pt-6">
			<div class="flex items-center justify-between gap-3">
				<div class="flex flex-wrap items-center gap-2">
					<p
						class="inline-flex items-center gap-2 rounded-full border-2 border-ink bg-paper px-3 py-1 text-[11px] font-bold shadow-[2px_2px_0_0_#131313]"
					>
						<span class="h-2 w-2 rounded-full bg-ink" aria-hidden="true"></span>
						<span>ものや<span class="hidden sm:inline"> @ NOSTRASIA 2026</span></span>
					</p>
					{#if demoMode}
						<span
							class="inline-flex items-center gap-1.5 rounded-full border-2 border-dashed border-ink bg-lemon-soft px-3 py-1 text-[10px] font-bold"
							title="npm run dev の表示確認用テストデータです"
						>
							<span class="h-1.5 w-1.5 animate-pulse rounded-full bg-ink" aria-hidden="true"></span>
							DEV / テストデータ
						</span>
					{/if}
				</div>
				<div class="flex items-center gap-2">
					{#if imageVersion}
						<span class="hidden text-[10px] font-bold text-ink/45 sm:inline"
							>画像版 {imageVersion}</span
						>
					{/if}
					<button
						type="button"
						onclick={load}
						disabled={reloadDisabled}
						class="shrink-0 rounded-full border-2 border-ink bg-paper px-4 py-2 text-xs font-bold whitespace-nowrap shadow-[3px_3px_0_0_#131313] transition hover:-translate-y-0.5 hover:bg-lemon-soft active:translate-x-0.5 active:translate-y-0.5 active:shadow-[1px_1px_0_0_#131313] disabled:cursor-not-allowed disabled:bg-lemon-soft disabled:text-ink/40 disabled:shadow-[2px_2px_0_0_#131313] disabled:hover:translate-y-0"
					>
						{loading ? '取得中…' : '再読み込み'}
					</button>
				</div>
			</div>

			<!-- ヒーローパネル -->
			<section
				class="relative mt-5 rounded-[2rem] border-[3px] border-ink bg-paper px-5 pt-9 pb-6 shadow-[7px_7px_0_0_#131313] sm:px-9 sm:pt-11 sm:pb-8"
			>
				<span
					class="absolute -top-3 left-1/2 -translate-x-1/2 rotate-[-2deg] rounded-sm border-2 border-ink bg-lemon px-4 py-0.5 text-[10px] font-bold tracking-[0.28em] whitespace-nowrap"
				>
					NOSTRASIA 2026 FLEA MARKET
				</span>

				<div class="flex flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
					<div>
						<p class="inline-flex flex-wrap items-center gap-2">
							<span
								class="rounded-full border-2 border-ink bg-ink px-3 py-1 font-latin text-[11px] font-extrabold tracking-[0.12em] text-lemon"
							>
								NOSTRASIA 2026
							</span>
							<span class="text-xs font-bold tracking-wide">Flea Market</span>
							<span class="text-[10px] font-bold tracking-[0.12em] text-ink/45"
								>NOSTR CONFERENCE IN ASIA</span
							>
						</p>

						<h1
							class="mt-3 font-display text-[clamp(3.4rem,15vw,7.5rem)] leading-[0.95] tracking-tight"
						>
							ものや
						</h1>

						<p class="mt-3 font-hand text-base leading-relaxed sm:text-lg">
							Nostrの祭典のすみっこで、<br class="sm:hidden" />
							てづくりのものを並べています。
						</p>

						{#if snapshot}
							<div class="mt-5 flex flex-wrap items-center gap-2">
								<span
									class="rounded-full border-2 border-ink bg-ink px-3 py-1 text-[11px] font-bold text-lemon"
								>
									ぜんぶ {totalCount} 点
								</span>
								<span
									class="rounded-full border-2 border-ink bg-paper px-3 py-1 text-[11px] font-bold"
								>
									まだある {filterCounts.inStock} 点
								</span>
								<span
									class="rounded-full border-2 border-dashed border-ink/40 px-3 py-1 text-[11px] font-bold text-ink/60"
								>
									SOLD OUT {filterCounts.soldOut} 点
								</span>
							</div>
						{/if}
					</div>

					<!-- スタンプ -->
					<div class="hidden shrink-0 sm:block" aria-hidden="true">
						<div
							class="stamp-rotate grid h-32 w-32 place-items-center rounded-full border-[3px] border-dashed border-ink/70 text-center"
						>
							<div>
								<p class="font-latin text-2xl leading-none font-extrabold">2026</p>
								<p class="mt-1.5 text-[9px] font-bold tracking-[0.3em]">NOSTRASIA</p>
								<p class="text-[9px] tracking-[0.28em]">FLEA MARKET</p>
								<p class="mt-1.5 text-[10px] font-bold">✦ ものや ✦</p>
							</div>
						</div>
					</div>
				</div>
			</section>

			<!-- イベント情報 -->
			<div
				class="mt-4 flex flex-wrap items-center gap-x-3 gap-y-1.5 rounded-2xl border-2 border-dashed border-ink/40 bg-paper/50 px-4 py-3 text-[11px] font-bold"
			>
				<span class="font-latin text-xs font-extrabold">2026.11.29 SUN</span>
				<span class="text-ink/25" aria-hidden="true">/</span>
				<span>13:00–20:00</span>
				<span class="text-ink/25" aria-hidden="true">/</span>
				<span>GOX Tokyo（新宿・歌舞伎町）</span>
				<span
					class="ml-auto rounded-full border border-ink/30 px-2 py-0.5 font-latin text-[10px] font-bold"
					>#nostrasia2026</span
				>
			</div>

			<div
				class="mt-3 flex flex-wrap items-center justify-between gap-2 px-1 text-[10px] font-bold text-ink/55"
			>
				<p>最終更新: {updatedAt || '未取得'}</p>
				{#if imageVersion}
					<p class="sm:hidden">画像版 {imageVersion}</p>
				{/if}
			</div>
		</header>

		<main class="mx-auto max-w-6xl px-4 pt-8 pb-4">
			<!-- 注意書き -->
			<p
				class="mb-6 flex items-start gap-2 rounded-2xl border-2 border-ink bg-ink px-4 py-3 text-[11px] leading-relaxed font-bold text-lemon"
			>
				<span
					class="mt-px grid h-4 w-4 shrink-0 place-items-center rounded-full bg-lemon text-[10px] font-black text-ink"
					aria-hidden="true">!</span
				>
				送信が遅れている間は、在庫表示が古いことがあります。気になるものはお早めにどうぞ。
			</p>

			{#if snapshot}
				<div class="mb-7 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
					<div
						class="inline-flex w-fit flex-wrap items-center gap-1 rounded-full border-2 border-ink bg-paper p-1 shadow-[3px_3px_0_0_#131313]"
						role="group"
						aria-label="在庫で絞り込み"
					>
						<button
							type="button"
							aria-pressed={stockFilter === 'all'}
							onclick={() => (stockFilter = 'all')}
							class="rounded-full px-3.5 py-1.5 text-xs font-bold transition {filterButtonClass(
								'all'
							)}"
						>
							すべて <span class="ml-0.5 font-latin text-[10px] opacity-70">{filterCounts.all}</span
							>
						</button>
						<button
							type="button"
							aria-pressed={stockFilter === 'in_stock'}
							onclick={() => (stockFilter = 'in_stock')}
							class="rounded-full px-3.5 py-1.5 text-xs font-bold transition {filterButtonClass(
								'in_stock'
							)}"
						>
							在庫あり <span class="ml-0.5 font-latin text-[10px] opacity-70"
								>{filterCounts.inStock}</span
							>
						</button>
						<button
							type="button"
							aria-pressed={stockFilter === 'sold_out'}
							onclick={() => (stockFilter = 'sold_out')}
							class="rounded-full px-3.5 py-1.5 text-xs font-bold transition {filterButtonClass(
								'sold_out'
							)}"
						>
							SOLD OUT <span class="ml-0.5 font-latin text-[10px] opacity-70"
								>{filterCounts.soldOut}</span
							>
						</button>
					</div>
					<p class="text-xs font-bold">
						<span class="font-latin text-base">{shownCount}</span> 点 ならんでいます
					</p>
				</div>
			{/if}

			{#if error}
				<div class="mb-6 rounded-2xl border-2 border-ink bg-paper p-5 shadow-[4px_4px_0_0_#131313]">
					<p class="text-sm font-bold">{error}</p>
					<button
						type="button"
						onclick={load}
						disabled={reloadDisabled}
						class="mt-3 rounded-full border-2 border-ink bg-lemon px-4 py-1.5 text-xs font-bold transition hover:bg-lemon-soft disabled:cursor-not-allowed disabled:opacity-50"
					>
						もういちど試す
					</button>
				</div>
			{/if}

			{#if loading && !snapshot}
				<div
					class="grid grid-cols-2 gap-3 sm:grid-cols-3 sm:gap-4 lg:grid-cols-4 xl:grid-cols-5"
					aria-hidden="true"
				>
					{#each skeletonItems as item (item)}
						<div
							class="overflow-hidden rounded-2xl border-2 border-ink bg-paper shadow-[4px_4px_0_0_#131313]"
						>
							<div class="aspect-4/3 animate-pulse border-b-2 border-ink bg-lemon-soft"></div>
							<div class="space-y-2 p-3">
								<div class="h-2 w-1/3 animate-pulse rounded-full bg-ink/10"></div>
								<div class="h-3.5 w-4/5 animate-pulse rounded-full bg-ink/10"></div>
								<div class="h-5 w-2/5 animate-pulse rounded-full bg-ink/10"></div>
							</div>
						</div>
					{/each}
				</div>
			{:else if snapshot && snapshot.products.length === 0}
				<div
					class="rounded-[2rem] border-[3px] border-dashed border-ink/50 bg-paper/60 px-6 py-16 text-center"
				>
					<p class="text-3xl" aria-hidden="true">☺</p>
					<p class="mt-3 font-display text-lg">いまは、ならんでいるものがありません。</p>
					<p class="mt-1 text-xs font-bold text-ink/50">またのぞいてみてください。</p>
				</div>
			{:else if snapshot && groups.length === 0}
				<div
					class="rounded-[2rem] border-[3px] border-dashed border-ink/50 bg-paper/60 px-6 py-16 text-center"
				>
					<p class="text-3xl" aria-hidden="true">☺</p>
					<p class="mt-3 font-display text-lg">この条件のものは、いまありません。</p>
					<p class="mt-1 text-xs font-bold text-ink/50">「すべて」に戻してみてください。</p>
				</div>
			{:else}
				<div class="space-y-12">
					{#each groups as g, gi (g.type.type_id)}
						<section>
							<div class="mb-4 flex items-center gap-3">
								<span
									class="grid h-9 min-w-9 place-items-center rounded-full border-2 border-ink bg-ink px-2 font-latin text-sm font-extrabold text-lemon"
								>
									{String(gi + 1).padStart(2, '0')}
								</span>
								<div
									class="flex flex-1 items-end justify-between gap-3 border-b-[3px] border-dashed border-ink/40 pb-2"
								>
									<h2 class="font-display text-xl leading-none sm:text-2xl">{g.type.name}</h2>
									<span class="text-xs font-bold whitespace-nowrap">{g.products.length} 点</span>
								</div>
							</div>

							<ul
								class="grid grid-cols-2 gap-3 sm:grid-cols-3 sm:gap-4 lg:grid-cols-4 xl:grid-cols-5"
							>
								{#each g.products as p (p.product_id)}
									{@const stock = stockDisplay(g.type.stock_mode, p.stock)}
									{@const attrs = attributePairs(g.type, p)}
									<li>
										<article
											class="group flex h-full flex-col overflow-hidden rounded-2xl border-2 border-ink bg-paper shadow-[4px_4px_0_0_#131313] transition duration-200 hover:-translate-y-1 hover:shadow-[6px_6px_0_0_#131313]"
										>
											<div
												class="relative aspect-4/3 overflow-hidden border-b-2 border-ink bg-lemon-soft"
											>
												{#if showImage(p)}
													<img
														src={imageUrl(p.product_id)}
														alt={p.name}
														loading="lazy"
														decoding="async"
														class="h-full w-full object-cover transition duration-500 group-hover:scale-105"
														onerror={() => markImageFailed(p.product_id)}
													/>
												{:else}
													<div
														class="flex h-full flex-col items-center justify-center gap-2 bg-lemon-soft p-4 text-center"
													>
														<svg
															xmlns="http://www.w3.org/2000/svg"
															viewBox="0 0 24 24"
															fill="none"
															stroke="currentColor"
															stroke-width="1.5"
															class="h-7 w-7 text-ink/30"
															aria-hidden="true"
														>
															<path
																stroke-linecap="round"
																stroke-linejoin="round"
																d="m2.25 15.75 5.159-5.159a2.25 2.25 0 0 1 3.182 0l5.159 5.159m-1.5-1.5 1.409-1.409a2.25 2.25 0 0 1 3.182 0l2.909 2.909M3.75 21h16.5A1.5 1.5 0 0 0 21.75 19.5V4.5A1.5 1.5 0 0 0 20.25 3H3.75A1.5 1.5 0 0 0 2.25 4.5v15A1.5 1.5 0 0 0 3.75 21Z"
															/>
														</svg>
														<p class="line-clamp-3 font-display text-sm leading-snug">
															{p.name}
														</p>
														{#if attrs.length > 0}
															<p class="line-clamp-2 text-[10px] font-bold text-ink/50">
																{attrs.map((a) => a.value).join(' / ')}
															</p>
														{/if}
													</div>
												{/if}

												{#if stock?.soldOut}
													<div class="absolute inset-0 grid place-items-center bg-ink/35">
														<span
															class="rotate-[-8deg] rounded-md border-[3px] border-ink bg-lemon px-3 py-1 font-latin text-xs font-extrabold tracking-[0.18em] text-ink shadow-[3px_3px_0_0_#131313]"
														>
															SOLD OUT
														</span>
													</div>
												{:else if stock}
													<span
														class="absolute top-2 left-2 z-10 rounded-full border-2 border-ink px-2 py-0.5 text-[10px] font-bold shadow-[2px_2px_0_0_#131313] {stockBadgeClass(
															stock
														)}"
													>
														{stock.label}
													</span>
												{/if}
											</div>

											<div class="flex flex-1 flex-col gap-1.5 p-3">
												<p class="font-latin text-[10px] font-bold tracking-[0.14em] text-ink/35">
													{p.product_id}
												</p>
												<h3 class="font-display text-sm leading-snug text-ink sm:text-[15px]">
													{p.name}
												</h3>

												{#if attrs.length > 0}
													<ul class="flex flex-wrap gap-1">
														{#each attrs as a, i (i)}
															<li
																class="rounded-md border border-ink/15 bg-lemon-soft/70 px-1.5 py-0.5 text-[10px] font-bold text-ink/70"
															>
																{#if a.label}<span class="text-ink/40">{a.label}:</span>{/if}
																{a.value}
															</li>
														{/each}
													</ul>
												{/if}

												<div
													class="mt-auto flex items-end justify-between gap-2 border-t-2 border-dotted border-ink/15 pt-2"
												>
													<div>
														<p class="font-latin text-xl leading-none font-extrabold">
															{yenFormatter.format(p.price_jpy)}<span
																class="ml-0.5 font-round text-xs">円</span
															>
														</p>
														{#if hasSats(p)}
															<p class="mt-1 font-latin text-[10px] font-bold text-ink/50">
																₿ {yenFormatter.format(p.price_sats ?? 0)} sats
															</p>
														{/if}
													</div>
													{#if stock?.soldOut}
														<span class="text-[10px] font-bold text-ink/40">完売御礼</span>
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

		<footer class="mt-12 border-t-[3px] border-ink bg-ink px-4 py-10 text-lemon">
			<div
				class="mx-auto flex max-w-6xl flex-col gap-6 sm:flex-row sm:items-end sm:justify-between"
			>
				<div>
					<p class="font-latin text-[10px] font-extrabold tracking-[0.32em] text-lemon/60">
						NOSTRASIA 2026 FLEA MARKET
					</p>
					<p class="mt-1 font-display text-4xl">ものや</p>
					<p class="mt-1.5 text-xs font-bold">2026.11.29 SUN 13:00–20:00 / GOX Tokyo</p>
				</div>
				<p class="max-w-xs text-[11px] leading-relaxed font-bold text-lemon/60">
					画像がない商品は、商品名と属性を表示しています。<br />
					お支払いは Lightning と現金に対応しています。
				</p>
			</div>
		</footer>
	</div>
</div>
