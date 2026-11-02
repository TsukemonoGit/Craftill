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

  let snapshot = $state<Snapshot | null>(null);
  let error = $state('');
  let loading = $state(false);

  async function load() {
    loading = true;
    error = '';
    try {
      const res = await fetch('/api/snapshot', { cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      snapshot = await res.json();
    } catch (e) {
      error = `取得に失敗しました: ${e instanceof Error ? e.message : String(e)}`;
    } finally {
      loading = false;
    }
  }

  onMount(load);

  const groups = $derived(
    snapshot
      ? snapshot.types
          .map((t) => ({
            type: t,
            products: snapshot!.products
              .filter((p) => p.type_id === t.type_id)
              .sort((a, b) => a.product_id.localeCompare(b.product_id))
          }))
          .filter((g) => g.products.length > 0)
      : []
  );

  const updatedAt = $derived(
    snapshot
      ? new Date(snapshot.created_at).toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo' })
      : ''
  );

  function stockLabel(mode: SnapType['stock_mode'], stock: number | null | undefined): string {
    if (mode === 'none') return '';
    const n = stock ?? 0;
    if (n <= 0) return 'SOLD OUT';
    return mode === 'unique' ? '1点もの' : `残り ${n}個`;
  }

  function hasSats(p: SnapProduct): boolean {
    return typeof p.price_sats === 'number' && p.price_sats > 0;
  }
</script>

<h1>商品一覧</h1>

<p>
  最終更新: {updatedAt || '未取得'}
  <button onclick={load} disabled={loading}>{loading ? '取得中…' : '再読み込み'}</button>
</p>
<p>送信が遅れている間、在庫表示が古い可能性があります。</p>

{#if error}
  <p>{error}</p>
{/if}

{#each groups as g (g.type.type_id)}
  <h2>{g.type.name}</h2>
  <ul>
    {#each g.products as p (p.product_id)}
      <li>
        {p.product_id} {p.name}
        {p.price_jpy}円{#if hasSats(p)} / {p.price_sats} sats{/if}
        {stockLabel(g.type.stock_mode, p.stock)}
      </li>
    {/each}
  </ul>
{/each}