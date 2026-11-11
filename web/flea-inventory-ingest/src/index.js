const KEY = "inventory:v1";
// 新しい保存順序のキー。旧版は created_at を文字列で保存していたため、
// 初回はそちらから引き継ぐ。
const ORDER_KEY = "snapshot_order";
const LEGACY_CREATED_AT_KEY = "created_at";

// 端末の時計がこの許容幅より未来を指している場合、created_at をサーバー受信時刻に
// 丸める。未来の時刻を保存すると、以後の正しい送信がすべて Stale になり、
// 時計を直しても復旧できなくなるため。
const MAX_FUTURE_SKEW_MS = 5 * 60 * 1000;

// KV 書き込みが 429・5xx などで失敗したときの再試行間隔。
// Durable Object 内で待つので、リクエストはその間ブロックされる（直列化は維持される）。
const KV_RETRY_DELAYS_MS = [200, 500, 1000];

const STOCK_MODES = new Set(["counted", "unique", "none"]);

const isPlainObject = (v) =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const isString = (v) => typeof v === "string";
const isInt = (v) => Number.isInteger(v);
const isOptional = (v, check) => v === undefined || v === null || check(v);
const isDateString = (v) => isString(v) && !Number.isNaN(Date.parse(v));
const isRevision = (v) => isInt(v) && v >= 0;

const isValidType = (t) =>
  isPlainObject(t) &&
  isString(t.type_id) &&
  isString(t.name) &&
  STOCK_MODES.has(t.stock_mode) &&
  Array.isArray(t.attr_labels) &&
  t.attr_labels.every(isString);

const isValidProduct = (p) =>
  isPlainObject(p) &&
  isString(p.product_id) &&
  isString(p.type_id) &&
  isString(p.name) &&
  isInt(p.price_jpy) &&
  isOptional(p.price_sats, isInt) &&
  Array.isArray(p.attrs) &&
  p.attrs.every((a) => a === null || isString(a)) &&
  isOptional(p.stock, isInt) &&
  typeof p.has_image === "boolean";

const isValidSnapshot = (s) => {
  if (!isPlainObject(s)) return false;
  if (!isDateString(s.created_at)) return false;
  // revision は旧版の端末が送らないため任意。無い場合は 0 として扱う。
  if (!isOptional(s.revision, isRevision)) return false;
  if (!Array.isArray(s.types) || !s.types.every(isValidType)) return false;
  if (!Array.isArray(s.products) || !s.products.every(isValidProduct)) {
    return false;
  }
  const typeIds = new Set(s.types.map((t) => t.type_id));
  return s.products.every((p) => typeIds.has(p.type_id));
};

const revisionOf = (s) => (isRevision(s.revision) ? s.revision : 0);

// 保存済みの順序が受信した順序より新しいか。
// 同じ (時刻, revision) は再送とみなして受け付ける。
const isStoredNewer = (stored, incoming) =>
  stored.at > incoming.at ||
  (stored.at === incoming.at && stored.revision > incoming.revision);

// 待機は scheduler.wait を使う（Workers/DO の公式API）。
// ローカルテストなど scheduler が無い環境では、あれば setTimeout、無ければ即時解決。
const sleep = (ms) => {
  if (typeof scheduler !== "undefined" && typeof scheduler.wait === "function") {
    return scheduler.wait(ms);
  }
  return new Promise((resolve) => {
    if (typeof setTimeout === "function") setTimeout(resolve, ms);
    else resolve();
  });
};

// KV バインディングのエラーが一時的か。429 と 5xx だけ再試行する。
const isRetryableKvError = (error) => {
  const status = error && (error.status || error.statusCode);
  if (typeof status === "number") return status === 429 || status >= 500;
  const message = String((error && error.message) || error || "");
  return (
    /\b(429|5\d\d)\b/.test(message) ||
    /rate limit|too many requests|timeout|timed out|unavailable|internal error/i.test(
      message
    )
  );
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/ingest" || request.method !== "POST") {
      return new Response("Not Found", { status: 404 });
    }

    const secret = env.WRITE_SECRET;
    if (typeof secret !== "string" || secret === "") {
      return new Response("Server Misconfigured", { status: 500 });
    }

    const auth = request.headers.get("Authorization") || "";
    if (auth !== `Bearer ${secret}`) {
      return new Response("Unauthorized", { status: 401 });
    }

    // 保存順序の比較と KV への書き込みを単一の Durable Object に集約し、
    // 並行リクエストで古いスナップショットが新しいものを上書きしないようにする。
    const id = env.INVENTORY_STORE.idFromName(KEY);
    return env.INVENTORY_STORE.get(id).fetch(request);
  },
};

export class InventoryStore {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    // Durable Object 内でも await をまたぐとリクエストが interleave するため、
    // 比較・保存・KV 書き込みを Promise チェーンで直列化する。
    this.tail = Promise.resolve();
  }

  async fetch(request) {
    const body = await request.text();
    const result = this.tail.then(() => this.ingest(body));
    this.tail = result.then(
      () => undefined,
      () => undefined
    );
    return result;
  }

  async ingest(body) {
    let parsed;
    try {
      parsed = JSON.parse(body);
    } catch {
      return new Response("Bad Request", { status: 400 });
    }

    if (!isValidSnapshot(parsed)) {
      return new Response("Bad Request", { status: 400 });
    }

    const now = Date.now();
    const receivedAt = Date.parse(parsed.created_at);
    let storedBody = body;
    let storedAt = receivedAt;

    if (receivedAt > now + MAX_FUTURE_SKEW_MS) {
      parsed.created_at = new Date(now).toISOString();
      storedBody = JSON.stringify(parsed);
      storedAt = now;
    }

    const incoming = { at: storedAt, revision: revisionOf(parsed) };
    const previous = await this.loadStoredOrder(now);
    if (previous !== null && isStoredNewer(previous, incoming)) {
      return new Response("Stale", { status: 409 });
    }

    // 先に順序を確定してから KV を書く。KV が失敗したら順序を元に戻す。
    // 戻さないと、KV に入っていない順序が保存済みとして残り、再送が
    // 409 になったり、古い内容が採用されたりする。
    await this.state.storage.put(ORDER_KEY, incoming);
    try {
      await this.putKvWithRetry(storedBody);
    } catch {
      try {
        if (previous === null) {
          await this.state.storage.delete(ORDER_KEY);
        } else {
          await this.state.storage.put(ORDER_KEY, previous);
        }
      } catch {
        // ロールバックにも失敗した場合でも KV は変わっていない。
        // 同じスナップショットの再送は同じ順序なので受け付けられる。
      }
      return new Response("Storage Unavailable", { status: 503 });
    }
    return new Response("OK", { status: 200 });
  }

  async putKvWithRetry(body) {
    for (let attempt = 0; ; attempt += 1) {
      try {
        await this.env.INVENTORY_KV.put(KEY, body);
        return;
      } catch (error) {
        if (attempt >= KV_RETRY_DELAYS_MS.length || !isRetryableKvError(error)) {
          throw error;
        }
        await sleep(KV_RETRY_DELAYS_MS[attempt]);
      }
    }
  }

  async kvGetWithRetry() {
    for (let attempt = 0; ; attempt += 1) {
      try {
        return await this.env.INVENTORY_KV.get(KEY);
      } catch (error) {
        if (attempt >= KV_RETRY_DELAYS_MS.length || !isRetryableKvError(error)) {
          throw error;
        }
        await sleep(KV_RETRY_DELAYS_MS[attempt]);
      }
    }
  }

  // 保存済みの順序を返す。無ければ DO の旧キー → KV の順に引き継ぐ。
  async loadStoredOrder(now) {
    const stored = await this.state.storage.get(ORDER_KEY);
    const order = this.toOrder(stored, now);
    if (order !== null) return order;
    if (stored !== undefined && stored !== null) {
      // 未来時刻など引き継げない値は捨てて、下の経路で復旧する。
      await this.state.storage.delete(ORDER_KEY);
    }

    // 旧版の DO 保存値（created_at の文字列）。revision が無いので -1 とする。
    const legacy = await this.state.storage.get(LEGACY_CREATED_AT_KEY);
    if (typeof legacy === "string") {
      const ms = Date.parse(legacy);
      if (!Number.isNaN(ms) && ms <= now + MAX_FUTURE_SKEW_MS) {
        return { at: ms, revision: -1 };
      }
    }

    // 初回デプロイ時は、それまでの KV の保存内容を引き継ぐ。
    // 未来の値が既に入っている場合は、復旧できるように引き継がない。
    const kv = await this.kvGetWithRetry();
    if (kv === null) return null;
    try {
      const snapshot = JSON.parse(kv);
      if (!isDateString(snapshot.created_at)) return null;
      const ms = Date.parse(snapshot.created_at);
      if (Number.isNaN(ms) || ms > now + MAX_FUTURE_SKEW_MS) return null;
      return { at: ms, revision: isRevision(snapshot.revision) ? snapshot.revision : -1 };
    } catch {
      return null;
    }
  }

  toOrder(value, now) {
    if (!isPlainObject(value)) return null;
    const at = typeof value.at === "number" ? value.at : Date.parse(value.at);
    if (!Number.isFinite(at) || at > now + MAX_FUTURE_SKEW_MS) return null;
    return { at, revision: isRevision(value.revision) ? value.revision : -1 };
  }
}
