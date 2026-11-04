import type { RequestHandler } from './$types';
import { env } from 'cloudflare:workers';

const KEY = 'inventory:v1';

export const GET: RequestHandler = async () => {
  const value = await env.INVENTORY_KV.get(KEY);
  if (value === null) {
    return new Response('{}', {
      status: 404,
      headers: { 'content-type': 'application/json' }
    });
  }
  return new Response(value, {
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store'
    }
  });
};