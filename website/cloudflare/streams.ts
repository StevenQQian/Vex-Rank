// The jumper's shared state: livestreams viewers added to an event, and the
// sync point that lines each video up with the matches ("this match starts
// here"). One person syncing a stream places every match for everyone.
// Kept as one small JSON row per event in api_cache - no schema change.
//
//   GET  /api/streams?event=64234[&videos=id,id]   streams + YouTube start times
//   POST /api/streams  {event, url, divisionId?}    add a YouTube link
//   POST /api/streams  {event, videoId, sync:{matchId, seconds}}
import { youtubeId } from '../lib/stream-jumper.mjs';

type Stream = { videoId: string; url?: string; divisionId?: number | null; sync?: { matchId: number; seconds: number } | null; startTime?: string | null; addedAt?: string };
interface StreamEnv { DB: D1Database; YOUTUBE_API_KEY?: string }

const MAX_STREAMS = 8;
const KEEP_FOR = 3 * 365 * 86400000;
const key = (event: number) => `streams:${event}`;
const json = (body: unknown, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });

async function load(env: StreamEnv, event: number): Promise<Stream[]> {
  const row = await env.DB.prepare('SELECT body FROM api_cache WHERE key=?').bind(key(event)).first<{ body: string }>().catch(() => null);
  try { return row ? JSON.parse(row.body).streams ?? [] : []; } catch { return []; }
}
async function save(env: StreamEnv, event: number, streams: Stream[]) {
  await env.DB.prepare('INSERT INTO api_cache(key,body,expires_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET body=excluded.body,expires_at=excluded.expires_at')
    .bind(key(event), JSON.stringify({ streams }), Date.now() + KEEP_FOR).run();
}

// When the broadcast went live, from YouTube - only with an API key, and only
// once per video (it never changes after the stream starts).
async function startTimes(env: StreamEnv, ids: string[]): Promise<Record<string, string>> {
  if (!env.YOUTUBE_API_KEY || !ids.length) return {};
  try {
    const url = `https://www.googleapis.com/youtube/v3/videos?part=liveStreamingDetails&id=${ids.slice(0, 20).join(',')}&key=${env.YOUTUBE_API_KEY}`;
    const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!response.ok) return {};
    const body = await response.json() as { items?: { id: string; liveStreamingDetails?: { actualStartTime?: string } }[] };
    return Object.fromEntries((body.items ?? []).filter(item => item.liveStreamingDetails?.actualStartTime).map(item => [item.id, item.liveStreamingDetails!.actualStartTime!]));
  } catch { return {}; }
}

export async function streamsRoute(request: Request, env: StreamEnv): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === 'GET') {
    const event = Number(url.searchParams.get('event'));
    if (!Number.isInteger(event) || event <= 0) return json({ error: 'event is required.' }, 400);
    const streams = await load(env, event);
    // Videos the page found in the event's own webcast notes are timed too.
    const listed = (url.searchParams.get('videos') ?? '').split(',').filter(id => /^[A-Za-z0-9_-]{11}$/.test(id));
    const known = new Map(streams.map(stream => [stream.videoId, stream]));
    const untimed = [...new Set([...known.keys(), ...listed])].filter(id => !known.get(id)?.startTime);
    const found = await startTimes(env, untimed);
    if (Object.keys(found).length) {
      for (const [videoId, startTime] of Object.entries(found)) {
        const stream = known.get(videoId);
        if (stream) stream.startTime = startTime;
        else if (streams.length < MAX_STREAMS * 2) { const entry = { videoId, startTime, listed: true } as Stream; streams.push(entry); known.set(videoId, entry); }
      }
      await save(env, event, streams).catch(() => {});
    }
    return json({ event, streams });
  }
  if (request.method !== 'POST') return json({ error: 'GET or POST.' }, 405);
  const text = await request.text();
  if (text.length > 2000) return json({ error: 'Too large.' }, 413);
  let body: any;
  try { body = JSON.parse(text); } catch { return json({ error: 'JSON body required.' }, 400); }
  const event = Number(body?.event);
  if (!Number.isInteger(event) || event <= 0) return json({ error: 'event is required.' }, 400);
  const streams = await load(env, event);
  if (body.url !== undefined) {
    const videoId = youtubeId(String(body.url));
    if (!videoId) return json({ error: 'Only YouTube video and live links can be jumped in.' }, 400);
    if (!streams.some(stream => stream.videoId === videoId)) {
      if (streams.filter(stream => stream.addedAt).length >= MAX_STREAMS) return json({ error: 'This event already has the most streams allowed.' }, 409);
      const divisionId = Number.isInteger(Number(body.divisionId)) && Number(body.divisionId) > 0 ? Number(body.divisionId) : null;
      streams.push({ videoId, url: `https://www.youtube.com/watch?v=${videoId}`, divisionId, addedAt: new Date().toISOString() });
    }
  } else if (body.videoId !== undefined) {
    const videoId = String(body.videoId), matchId = Number(body.sync?.matchId), seconds = Number(body.sync?.seconds);
    if (!/^[A-Za-z0-9_-]{11}$/.test(videoId) || !Number.isInteger(matchId) || matchId <= 0 || !Number.isFinite(seconds) || seconds < 0 || seconds > 7 * 86400)
      return json({ error: 'videoId and sync {matchId, seconds} are required.' }, 400);
    const stream = streams.find(entry => entry.videoId === videoId);
    const sync = { matchId, seconds: Math.round(seconds) };
    if (stream) stream.sync = sync;
    else if (streams.length < MAX_STREAMS * 2) streams.push({ videoId, sync, listed: true } as Stream);
    else return json({ error: 'Too many streams.' }, 409);
  } else return json({ error: 'url or videoId is required.' }, 400);
  await save(env, event, streams);
  return json({ event, streams });
}
