import { GET as events } from '../app/api/events/route';
import { GET as event } from '../app/api/events/[id]/route';
import { GET as team } from '../app/api/teams/[number]/route';
import { GET as rankings } from '../app/api/rankings/route';
import { GET as skills } from '../app/api/skills/route';

interface Env { DB: D1Database; ROBOT_EVENTS_API_TOKEN: string }

function canonicalUrl(request: Request) {
  const incoming = new URL(request.url);
  if (!/^\/api\/(events(?:\/\d{1,10})?|teams\/[0-9]{1,8}[A-Za-z0-9-]{0,12}|rankings|skills)$/.test(incoming.pathname)) return null;
  const url = new URL(incoming.pathname, incoming.origin);
  for (const key of ['season', 'teamId']) {
    const value = incoming.searchParams.get(key);
    if (value) {
      if (!/^\d{1,10}$/.test(value)) return null;
      url.searchParams.set(key, value);
    }
  }
  return url;
}

async function dispatch(url: URL) {
  const request = new Request(url);
  if (url.pathname === '/api/events') return events(request);
  if (url.pathname === '/api/rankings') return rankings(request);
  if (url.pathname === '/api/skills') return skills(request);
  if (url.pathname.startsWith('/api/events/')) return event(request, { params: Promise.resolve({ id: url.pathname.split('/').at(-1)! }) });
  return team(request, { params: Promise.resolve({ number: url.pathname.split('/').at(-1)! }) });
}

function cors(response: Response) {
  const result = new Response(response.body, response);
  result.headers.set('Access-Control-Allow-Origin', 'https://easonli29.github.io');
  result.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
  result.headers.set('X-Content-Type-Options', 'nosniff');
  return result;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (request.method === 'OPTIONS') return cors(new Response(null, { status: 204 }));
    if (request.method !== 'GET') return cors(Response.json({ error: 'Method not allowed' }, { status: 405, headers: { Allow: 'GET, OPTIONS' } }));
    if (new URL(request.url).pathname === '/api/health') {
      await env.DB.prepare('SELECT 1').first();
      return cors(Response.json({ status: 'ok', environment: 'test', database: 'D1' }));
    }
    const url = canonicalUrl(request);
    if (!url) return cors(Response.json({ error: 'Unsupported route or query' }, { status: 400 }));
    const key = url.pathname + url.search;
    try {
      const saved = await env.DB.prepare('SELECT body, expires_at FROM api_cache WHERE key=?').bind(key).first<{body:string; expires_at:number}>();
      if (saved && saved.expires_at > Date.now()) return cors(new Response(saved.body, { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public,max-age=60', 'X-VEXRank-Cache': 'hit' } }));
      const response = await dispatch(url);
      if (response.ok) {
        const body = await response.clone().text();
        // D1 limits individual strings to 2 MB. Larger results still reach the visitor.
        if (new TextEncoder().encode(body).length < 1800000) {
          ctx.waitUntil(env.DB.prepare('INSERT INTO api_cache(key,body,expires_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET body=excluded.body,expires_at=excluded.expires_at').bind(key, body, Date.now() + 900000).run());
        }
      }
      return cors(response);
    } catch (error) {
      console.error('API request failed', error instanceof Error ? error.message : 'unknown');
      return cors(Response.json({ error: 'Official data is temporarily unavailable. Please retry.' }, { status: 502, headers: { 'Cache-Control': 'no-store' } }));
    }
  },
};
