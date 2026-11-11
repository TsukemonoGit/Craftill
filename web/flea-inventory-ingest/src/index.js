const KEY = "inventory:v1";

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

    let body;
    let parsed;
    try {
      body = await request.text();
      parsed = JSON.parse(body);
    } catch {
      return new Response("Bad Request", { status: 400 });
    }

    if (!isValidSnapshot(parsed)) {
      return new Response("Bad Request", { status: 400 });
    }

         // 保存済みより古いスナップショットでは上書きしない。
     const stored = await env.INVENTORY_KV.get(KEY);
     if (stored !== null) {
       let storedAt = NaN;
       try {
         storedAt = Date.parse(JSON.parse(stored).created_at);
       } catch {
         // 壊れた保存データは比較せず上書きする。
       }
       if (!Number.isNaN(storedAt) && storedAt > Date.parse(parsed.created_at)) {
         return new Response("Stale", { status: 409 });

       }
     }

    await env.INVENTORY_KV.put(KEY, body);
    return new Response("OK", { status: 200 });
  },
};
