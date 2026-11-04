const KEY = "inventory:v1";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/ingest" || request.method !== "POST") {
      return new Response("Not Found", { status: 404 });
    }
    const auth = request.headers.get("Authorization") || "";
    if (!env.WRITE_SECRET || auth !== `Bearer ${env.WRITE_SECRET}`) {
      return new Response("Unauthorized", { status: 401 });
    }
    let body;
    try {
      body = await request.text();
      JSON.parse(body);
    } catch {
      return new Response("Bad Request", { status: 400 });
    }
    await env.INVENTORY_KV.put(KEY, body);
    return new Response("OK", { status: 200 });
  },
};
