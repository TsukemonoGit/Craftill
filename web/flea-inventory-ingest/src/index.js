const KEY = "inventory:v1";

const isPlainObject = (value) =>
  typeof value === "object" && value !== null && !Array.isArray(value);

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

    if (
      !isPlainObject(parsed) ||
      !Array.isArray(parsed.types) ||
      !parsed.types.every(isPlainObject)
    ) {
      return new Response("Bad Request", { status: 400 });
    }

    await env.INVENTORY_KV.put(KEY, body);
    return new Response("OK", { status: 200 });
  },
};
