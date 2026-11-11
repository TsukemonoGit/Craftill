const KEY = "inventory:v1";
const CREATED_AT_KEY = "created_at";
// 端末の時計がこの許容幅より未来を指している場合、created_at をサーバー受信時刻に
// 丸める。未来の時刻を保存すると、以後の正しい送信がすべて Stale になり、
// 時計を直しても復旧できなくなるため。
const MAX_FUTURE_SKEW_MS = 5 * 60 * 1000;

const STOCK_MODES = new Set(["counted", "unique", "none"]);

const isPlainObject = (v) =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const isString = (v) => typeof v === "string";
const isInt = (v) => Number.isInteger(v);
const isOptional = (v, check) => v === undefined || v === null || check(v);
const isDateString = (v) => isString(v) && !Number.isNaN(Date.parse(v));

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
  if (!Array.isArray(s.types) || !s.types.every(isValidType)) return false;
  if (!Array.isArray(s.products) || !s.products.every(isValidProduct)) {
    return false;
  }
  const typeIds = new Set(s.types.map((t) => t.type_id));
  return s.products.every((p) => typeIds.has(p.type_id));
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

    // 保存時刻の比較と KV への書き込みを単一の Durable Object に集約し、
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

    const previousAt = await this.loadStoredAt(now);
    if (previousAt !== null && previousAt > storedAt) {
      return new Response("Stale", { status: 409 });
    }

    // DO の保存時刻を先に確定する。KV 書き込みに失敗しても、同じ内容の再送は
    // 同じ時刻（またはそれ以降）なので受け付けられる。
    await this.state.storage.put(CREATED_AT_KEY, new Date(storedAt).toISOString());
    await this.env.INVENTORY_KV.put(KEY, storedBody);
    return new Response("OK", { status: 200 });
  }

  async loadStoredAt(now) {
    const stored = await this.state.storage.get(CREATED_AT_KEY);
    if (typeof stored === "string") {
      const ms = Date.parse(stored);
      if (Number.isNaN(ms) || ms > now + MAX_FUTURE_SKEW_MS) return null;
      return ms;
    }

    // 初回デプロイ時は、それまでの KV の保存時刻を引き継ぐ。
    // 未来の値が既に入っている場合は、復旧できるように引き継がない。
    const kv = await this.env.INVENTORY_KV.get(KEY);
    if (kv === null) return null;
    try {
      const parsed = JSON.parse(kv);
      if (!isDateString(parsed.created_at)) return null;
      const ms = Date.parse(parsed.created_at);
      if (Number.isNaN(ms) || ms > now + MAX_FUTURE_SKEW_MS) return null;
      await this.state.storage.put(CREATED_AT_KEY, new Date(ms).toISOString());
      return ms;
    } catch {
      return null;
    }
  }
}
