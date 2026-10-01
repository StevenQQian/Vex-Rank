import { GET as events } from '../app/api/events/route';
import { GET as event } from '../app/api/events/[id]/route';
import { GET as team } from '../app/api/teams/[number]/route';
import { GET as rankings } from '../app/api/rankings/route';
import { GET as skills } from '../app/api/skills/route';
import { VCR_VERSION } from '../lib/vcr3.mjs';
import { archiveSource } from './archive-source';
import { cacheDecision, FRESH_FOR, STALE_FOR } from './cache-policy';

interface Env { DB: D1Database; ROBOT_EVENTS_API_TOKEN: string; ARCHIVES: Fetcher }

// Settings the apps read at launch, so that things which change on someone
// else's schedule - the season id, cache lifetimes, a note to readers - do not
// need a new binary and an App Store release. These are the defaults; a row in
// `app_config` overrides any of them without a deploy. Clients validate every
// field and fall back to what they were built with, so a mistake here costs one
// setting rather than the app. Native code is never delivered this way.
const APP_CONFIG_DEFAULTS = {
  currentSeason: 204,
  program: 'V5RC',
  eventCacheSeconds: 30,
  directoryCacheSeconds: 3600,
  defaultCacheSeconds: 120,
  flags: {} as Record<string, boolean>,
  // Zero means "nothing to say about builds". The version, url and notes that
  // drive the update banner come from the override row, which is written when
  // a build actually exists to point at.
  update: { latestBuild: 0, minimumBuild: 0 },
};

async function appConfig(env: Env, platform: string) {
  let stored: Record<string, unknown> = {};
  try {
    // Missing table or row is the normal state, not an error: it means nothing
    // has been overridden yet.
    const row = await env.DB.prepare('SELECT value FROM app_config WHERE key=?').bind(platform).first<{ value: string }>();
    if (row?.value) stored = JSON.parse(row.value);
  } catch { /* fall through to defaults */ }
  const merged = { ...APP_CONFIG_DEFAULTS, ...stored };
  // max-age is short because it is the floor on how fast a change reaches a
  // reader, and stale-while-revalidate keeps that from costing a round trip.
  return cors(Response.json(merged, { headers: { 'Cache-Control': 'public,max-age=300,stale-while-revalidate=3600' } }));
}

// Allowlist routes and query fields before constructing a stable shared-cache key.
// Unknown query fields are dropped. Add new data-affecting parameters here as well
// as in their route, or distinct requests can incorrectly share cached responses.
function canonicalUrl(request: Request) {
  const incoming = new URL(request.url);
  if (!/^\/api\/(archive-source(?:\/\d{1,10})?|events(?:\/\d{1,10})?|teams\/[0-9]{1,8}[A-Za-z0-9-]{0,12}|rankings|skills)$/.test(incoming.pathname)) return null;
  const url = new URL(incoming.pathname, incoming.origin);
  for (const key of ['season', 'teamId', 'division', 'page']) {
    const value = incoming.searchParams.get(key);
    if (value) {
      if (!/^\d{1,10}$/.test(value)) return null;
      url.searchParams.set(key, value);
    }
  }
  const mode=incoming.searchParams.get('mode');
  if(mode){if(!['metadata','teams','matches'].includes(mode))return null;url.searchParams.set('mode',mode)}
  // Model-version namespace prevents a new rating model from reusing old responses.
  if (url.pathname === '/api/rankings' || url.pathname.startsWith('/api/teams/')) url.searchParams.set('model', VCR_VERSION);
  return url;
}

async function dispatch(url: URL) {
  if (url.pathname.startsWith('/api/archive-source')) return archiveSource(url);
  const request = new Request(url);
  if (url.pathname === '/api/events') return events(request);
  if (url.pathname === '/api/rankings') return rankings(request);
  if (url.pathname === '/api/skills') return skills(request);
  if (url.pathname.startsWith('/api/events/')) return event(request, { params: Promise.resolve({ id: url.pathname.split('/').at(-1)! }) });
  return team(request, { params: Promise.resolve({ number: url.pathname.split('/').at(-1)! }) });
}

// Carries the caller's validators through to the asset store. Building the
// asset request from scratch drops them, and without them every launch
// re-downloads a file the reader already has.
function assetRequest(path: string, incoming: URL, request: Request) {
  const headers = new Headers();
  for (const name of ['If-None-Match', 'If-Modified-Since']) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }
  return new Request(new URL(path, incoming.origin), { headers });
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
    const archiveSeasons:Record<string,string>={'197':'2025-26','190':'2024-25','181':'2023-24','173':'2022-23'};
    const incoming=new URL(request.url),archiveSeason=incoming.searchParams.get('season');
    if(incoming.pathname==='/api/app-config'){
      const platform=incoming.searchParams.get('platform');
      return appConfig(env, platform&&/^[a-z]{1,16}$/.test(platform)?platform:'ios');
    }
    if(incoming.pathname==='/api/archive-manifest')return cors(await env.ARCHIVES.fetch(new Request(new URL('/manifest.json',incoming.origin))));
    if(incoming.pathname==='/api/team-directory'){
      const asset=await env.ARCHIVES.fetch(assetRequest('/team-directory.json',incoming,request));
      // 304 is a success, and the valuable one: the directory is 11 MB of JSON
      // that changes once a day, so a reader who already has it should be told
      // "still yours" rather than sent it again. Treating it as a failure - which
      // `asset.ok` does, since ok is 200-299 - would turn that into a 503.
      if(asset.status===304)return cors(asset);
      if(!asset.ok)return cors(Response.json({error:'Team directory is temporarily unavailable.'},{status:503}));
      const response=cors(asset);response.headers.set('Cache-Control','public,max-age=3600');return response;
    }
    // Historical rankings come only from published static archives. A missing asset
    // is a 503, not a fallback to the live route's partial event sample.
    const archivePath=/^\/rankings-20\d{2}-\d{2}-vcr3\.json$/.test(incoming.pathname)?incoming.pathname:incoming.pathname==='/api/rankings'&&archiveSeason&&archiveSeasons[archiveSeason]?`/rankings-${archiveSeasons[archiveSeason]}-vcr3.json`:null;
    if(archivePath){
      const asset=await env.ARCHIVES.fetch(assetRequest(archivePath,incoming,request));
      if(asset.status===304)return cors(asset);
      if(!asset.ok)return cors(Response.json({error:'This historical archive is not published yet.'},{status:503,headers:{'Cache-Control':'no-store'}}));
      return cors(asset);
    }
    if (new URL(request.url).pathname === '/api/health') {
      await env.DB.prepare('SELECT 1').first();
      return cors(Response.json({ status: 'ok', environment: 'test', database: 'D1', modelVersion: VCR_VERSION }));
    }
    const url = canonicalUrl(request);
    if (!url) return cors(Response.json({ error: 'Unsupported route or query' }, { status: 400 }));
    const key = url.pathname + url.search;
    const saved = await env.DB.prepare('SELECT body, expires_at FROM api_cache WHERE key=?').bind(key).first<{body:string; expires_at:number}>().catch(()=>null);
    const wantsLive = request.headers.get('X-VEXRank-Refresh') === '1';
    const decision = cacheDecision(saved, Date.now(), wantsLive);
    const staleAge = decision.age;
    if (decision.serve === 'fresh') return cors(new Response(saved!.body, { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public,max-age=60', 'X-VEXRank-Cache': 'hit' } }));
    // An expired row is still worth more than an error page. Official data goes
    // down and it hangs, and when it does, the reader who opened an event a
    // minute ago is better served by standings that are twenty minutes old than
    // by a spinner that turns into "please retry" after twenty seconds. Bounded,
    // and labelled, so neither the app nor a reader can mistake it for live.
    const stale = (why: string) => {
      if (!saved || staleAge > STALE_FOR) return null;
      return cors(new Response(saved.body, { headers: {
        'Content-Type': 'application/json', 'Cache-Control': 'no-store',
        'X-VEXRank-Cache': 'stale', 'X-VEXRank-Stale-Reason': why, 'Age': String(staleAge),
      } }));
    };

    // Hand back the expired copy now and refresh behind it. Official data is
    // slow when it is working and hangs for twenty seconds when it is not, and
    // making the reader wait for it buys them nothing they can see: the row we
    // already hold is the same answer, minutes older.
    //
    // A reader who pulled to refresh is asking a different question, and gets
    // the slow, truthful path instead.
    if (decision.serve === 'stale') {
      ctx.waitUntil((async () => {
        try {
          const response = await dispatch(url);
          if (!response.ok) return;
          const body = await response.text();
          if (new TextEncoder().encode(body).length < 1800000) {
            await env.DB.prepare('INSERT INTO api_cache(key,body,expires_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET body=excluded.body,expires_at=excluded.expires_at').bind(key, body, Date.now() + FRESH_FOR).run();
          }
        } catch { /* the copy we just served is still the best answer */ }
      })());
      return stale('revalidating')!;
    }

    try {
      const response = await dispatch(url);
      if (response.ok) {
        const body = await response.clone().text();
        // D1 limits individual strings to 2 MB. Larger results still reach the visitor.
        if (new TextEncoder().encode(body).length < 1800000) {
          ctx.waitUntil(env.DB.prepare('INSERT INTO api_cache(key,body,expires_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET body=excluded.body,expires_at=excluded.expires_at').bind(key, body, Date.now() + FRESH_FOR).run());
        }
        return cors(response);
      }
      return stale(`upstream-${response.status}`) ?? cors(response);
    } catch (error) {
      console.error('API request failed', error instanceof Error ? error.message : 'unknown');
      const limited=error instanceof Error&&/\(429\)/.test(error.message);
      const served = stale(limited ? 'upstream-429' : 'upstream-error');
      if (served) return served;
      const expired=error instanceof Error&&/credentials/i.test(error.message);
      return cors(Response.json({ error: limited?'Official data rate limit reached. Resume the archive rebuild later.':expired?'The official data credentials were rejected. The API token needs renewing.':'Official data is temporarily unavailable. Please retry.' }, { status: limited?429:502, headers: { 'Cache-Control': 'no-store',...(limited?{'Retry-After':'300'}:{}) } }));
    }
  },
};

