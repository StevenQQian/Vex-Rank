'use client';
// The jumper (lib/stream-jumper.mjs): an event's livestream in a dock that
// stays put while the schedule scrolls, and a jump from any played match to
// the moment it started. Matches are placed by when they actually started,
// never by the schedule, from one sync point anyone can set.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { Play, X } from 'lucide-react';
import { siteFetch } from '@/lib/client-fetch';
import { eventStreams, matchJump, matchesById, videoTime, youtubeId } from '@/lib/stream-jumper.mjs';

type Jump = { videoId: string; seconds: number };
type Jumper = { streams: any[]; jumpFor: (match: any) => Jump | null; jump: (match: any) => void; open: () => void };
const JumperContext = createContext<Jumper | null>(null);
export const useJumper = () => useContext(JumperContext);

const NUDGES = [-60, -30, -10, -5, 5, 10, 30, 60];
const storageKey = (event: string | number) => `vexrank-jumper-${event}`;
function readLocal(event: string | number) { try { return JSON.parse(localStorage.getItem(storageKey(event)) ?? 'null') ?? {}; } catch { return {}; } }
function writeLocal(event: string | number, value: any) { try { localStorage.setItem(storageKey(event), JSON.stringify(value)); } catch { /* private window: this visit only */ } }

// The YouTube IFrame API, loaded once and only when a stream is opened.
let youtubeReady: Promise<any> | null = null;
function loadYouTube(): Promise<any> {
  const w = window as any;
  if (w.YT?.Player) return Promise.resolve(w.YT);
  youtubeReady ??= new Promise(resolve => {
    const previous = w.onYouTubeIframeAPIReady;
    w.onYouTubeIframeAPIReady = () => { previous?.(); resolve(w.YT); };
    const script = document.createElement('script');
    script.src = 'https://www.youtube.com/iframe_api';
    document.head.appendChild(script);
  });
  return youtubeReady;
}

export function JumperProvider({ eventId, divisions, webcast, children }: { eventId: string | number; divisions: any[]; webcast?: string; children: React.ReactNode }) {
  const [shared, setShared] = useState<any[]>([]);
  const [local, setLocal] = useState<any>({});
  const [docked, setDocked] = useState(false);
  const [current, setCurrent] = useState<{ videoId: string; seconds: number; match?: any; at: number } | null>(null);
  const byId = useMemo(() => matchesById(divisions), [divisions]);
  const listed = useMemo(() => eventStreams(webcast) as any, [webcast]);

  useEffect(() => { setLocal(readLocal(eventId)); }, [eventId]);
  const refresh = useCallback(() => {
    const videos = listed.streams.map((stream: any) => stream.videoId).join(',');
    siteFetch(`/api/streams?event=${eventId}${videos ? `&videos=${videos}` : ''}`).then(response => response.ok ? response.json() : null).then((body: any) => { if (body?.streams) setShared(body.streams); }).catch(() => {});
  }, [eventId, listed]);
  useEffect(() => { refresh(); }, [refresh]);

  // The event's own links, then shared ones, each with its sync point - the
  // viewer's own unsaved one first - and their per-stream nudge.
  const streams = useMemo(() => {
    const merged = (eventStreams(webcast, [...shared, ...(local.added ?? [])]) as any).streams.map((stream: any) => {
      const saved = shared.find(entry => entry.videoId === stream.videoId);
      return { ...stream, ...saved, source: stream.source, sync: local.syncs?.[stream.videoId] ?? saved?.sync ?? null };
    });
    return merged;
  }, [webcast, shared, local]);
  const nudges = local.nudges ?? {};
  const jumpFor = useCallback((match: any) => matchJump(streams, byId.get(Number(match.id)) ?? match, byId, nudges), [streams, byId, nudges]);
  const jump = useCallback((match: any) => {
    const target = jumpFor(match);
    if (!target) return;
    setCurrent({ ...target, match, at: Date.now() });
    setDocked(true);
  }, [jumpFor]);
  const open = useCallback(() => { setDocked(true); setCurrent(previous => previous ?? (streams[0] ? { videoId: streams[0].videoId, seconds: -1, at: Date.now() } : null)); }, [streams]);
  const update = (change: (value: any) => any) => setLocal((previous: any) => { const next = change(previous); writeLocal(eventId, next); return next; });

  const value = useMemo(() => ({ streams, jumpFor, jump, open }), [streams, jumpFor, jump, open]);
  return <JumperContext.Provider value={value}>
    {children}
    {docked && <Dock eventId={eventId} streams={streams} current={current} setCurrent={setCurrent} byId={byId} nudges={nudges} onClose={() => setDocked(false)}
      onNudge={(videoId, delta) => update(value => ({ ...value, nudges: { ...value.nudges, [videoId]: (value.nudges?.[videoId] ?? 0) + delta } }))}
      onAdd={async (url, divisionId) => {
        const videoId = youtubeId(url);
        if (!videoId) return 'Paste a YouTube video or live link (a channel page cannot be jumped in).';
        const response = await siteFetch('/api/streams', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ event: Number(eventId), url, divisionId }) }).catch(() => null);
        if (response?.ok) { refresh(); } else update(value => ({ ...value, added: [...(value.added ?? []).filter((entry: any) => entry.videoId !== videoId), { videoId, url, divisionId, source: 'viewer' }] }));
        setCurrent({ videoId, seconds: -1, at: Date.now() });
        return null;
      }}
      onSync={async (videoId, matchId, seconds) => {
        // Saved for everyone; kept on this device too, so it holds even if the
        // save does not go through. A fresh sync clears this stream's nudge.
        update(value => ({ ...value, syncs: { ...value.syncs, [videoId]: { matchId, seconds } }, nudges: { ...value.nudges, [videoId]: 0 } }));
        const response = await siteFetch('/api/streams', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ event: Number(eventId), videoId, sync: { matchId, seconds } }) }).catch(() => null);
        if (response?.ok) { const body: any = await response.json().catch(() => null); if (body?.streams) { setShared(body.streams); update(value => { const syncs = { ...value.syncs }; delete syncs[videoId]; return { ...value, syncs }; }); } }
        return Boolean(response?.ok);
      }} />}
  </JumperContext.Provider>;
}

function Dock({ eventId, streams, current, setCurrent, byId, nudges, onClose, onNudge, onAdd, onSync }: {
  eventId: string | number; streams: any[]; current: any; setCurrent: (value: any) => void; byId: Map<number, any>; nudges: Record<string, number>; onClose: () => void;
  onNudge: (videoId: string, delta: number) => void; onAdd: (url: string, divisionId?: number) => Promise<string | null>; onSync: (videoId: string, matchId: number, seconds: number) => Promise<boolean>;
}) {
  const host = useRef<HTMLDivElement>(null);
  const player = useRef<any>(null);
  const loadedVideo = useRef<string | null>(null);
  const [link, setLink] = useState('');
  const [message, setMessage] = useState('');
  const [syncMatch, setSyncMatch] = useState<string>('');
  const videoId = current?.videoId ?? streams[0]?.videoId ?? null;
  const stream = streams.find(entry => entry.videoId === videoId);
  const played = useMemo(() => [...byId.values()].filter(match => match.started).sort((a, b) => Date.parse(a.started) - Date.parse(b.started)), [byId]);

  // One player for the dock's life: a new video loads into it, a jump on the
  // same video seeks. Seconds of -1 means "just open it".
  useEffect(() => {
    if (!videoId || !host.current) return;
    let cancelled = false;
    loadYouTube().then(YT => {
      if (cancelled) return;
      const start = Math.max(0, current?.seconds ?? 0);
      if (!player.current) {
        player.current = new YT.Player(host.current, { videoId, playerVars: { start, autoplay: current?.seconds >= 0 ? 1 : 0, playsinline: 1, rel: 0, modestbranding: 1 } });
        loadedVideo.current = videoId;
      } else if (loadedVideo.current !== videoId) {
        if (current?.seconds >= 0) player.current.loadVideoById({ videoId, startSeconds: start }); else player.current.cueVideoById({ videoId });
        loadedVideo.current = videoId;
      } else if (current?.seconds >= 0) { player.current.seekTo(start, true); player.current.playVideo?.(); }
    });
    return () => { cancelled = true; };
  }, [videoId, current?.at]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => () => { player.current?.destroy?.(); }, []);
  useEffect(() => { if (current?.match?.id) setSyncMatch(String(current.match.id)); }, [current?.match?.id]);

  const time = () => Number(player.current?.getCurrentTime?.() ?? 0);
  // The video's position, shown on the sync button: a sync taken before the
  // video has played (at 0:00) would misplace every match.
  const [position, setPosition] = useState(0);
  useEffect(() => { const timer = setInterval(() => setPosition(time()), 1000); return () => clearInterval(timer); }, []);
  const nudge = (delta: number) => {
    if (!videoId) return;
    onNudge(videoId, delta);
    player.current?.seekTo?.(Math.max(0, time() + delta), true);
  };
  const timed = Boolean(stream?.sync || stream?.startTime);

  return <aside aria-label="Livestream" className="fixed inset-x-0 bottom-0 z-50 border-t border-white/15 bg-[var(--c-surface)] shadow-2xl sm:inset-x-auto sm:bottom-4 sm:right-4 sm:w-[440px] sm:border">
    <div className="flex items-center gap-2 border-b border-white/10 px-3 py-2">
      <span className="text-[11px] font-semibold uppercase tracking-[.16em] text-white/50">Livestream</span>
      {current?.match && <span className="truncate text-xs text-white/70">· {current.match.name} at {videoTime(Math.max(0, current.seconds))}</span>}
      <button onClick={onClose} aria-label="Close livestream" className="ml-auto p-1 text-white/50 hover:text-white"><X className="h-4 w-4" /></button>
    </div>
    {videoId ? <div className="aspect-video w-full bg-black"><div ref={host} className="h-full w-full" /></div>
      : <p className="px-4 py-6 text-sm text-white/55">No livestream is listed for this event yet. Paste its YouTube link below to watch it here.</p>}
    <div className="space-y-2.5 px-3 py-3 text-xs">
      {streams.length > 1 && <div className="flex flex-wrap gap-1.5">{streams.map((entry, index) => <button key={entry.videoId} onClick={() => setCurrent({ videoId: entry.videoId, seconds: -1, at: Date.now() })} aria-pressed={entry.videoId === videoId} className={`border px-2.5 py-1 font-semibold ${entry.videoId === videoId ? 'border-[var(--c-accent)] bg-[var(--c-accent)] text-[var(--c-on-accent)]' : 'border-white/15 text-white/60 hover:text-white'}`}>Stream {index + 1}</button>)}</div>}
      {videoId && <>
        <div className="flex flex-wrap items-center gap-1">{NUDGES.map(delta => <button key={delta} onClick={() => nudge(delta)} className="min-w-10 border border-white/10 px-1.5 py-1 font-mono text-[11px] text-white/70 hover:border-white/30 hover:text-white">{delta < 0 ? '−' : '+'}{Math.abs(delta) >= 60 ? `${Math.abs(delta) / 60}m` : `${Math.abs(delta)}s`}</button>)}</div>
        <p className="text-white/50">{timed ? `Matches are placed by when they actually started${nudges[videoId] ? ` (nudged ${nudges[videoId] > 0 ? '+' : '−'}${Math.abs(nudges[videoId])}s)` : ''}. If a jump lands off, nudge it, or re-sync below.` : 'Not synced yet: find any match in the video, pick it below and press “Starts at”. Every match then gets a jump, for everyone.'}</p>
        <div className="flex gap-1.5">
          <select value={syncMatch} onChange={event => setSyncMatch(event.target.value)} aria-label="Match on screen" className="min-w-0 flex-1 border border-white/15 bg-black/30 px-2 py-1.5 text-xs">
            <option value="">Match on screen…</option>
            {played.map(match => <option key={match.id} value={match.id}>{match.name}{byId.size && new Set([...byId.values()].map(entry => entry.division?.id)).size > 1 ? ` · ${match.division?.name}` : ''}</option>)}
          </select>
          <button disabled={!syncMatch || position < 1} title={position < 1 ? 'Play the video to the start of a match first' : undefined} onClick={async () => { const ok = await onSync(videoId, Number(syncMatch), time()); setMessage(ok ? 'Synced for everyone.' : 'Synced on this device (could not save it for others).'); }} className="whitespace-nowrap border border-[var(--c-accent)] px-2.5 py-1.5 font-semibold text-[var(--c-accent)] disabled:opacity-40">Starts at {videoTime(position)}</button>
        </div>
      </>}
      <form onSubmit={async event => { event.preventDefault(); if (!link.trim()) return; const problem = await onAdd(link.trim()); setMessage(problem ?? 'Stream added.'); if (!problem) setLink(''); }} className="flex gap-1.5">
        <input value={link} onChange={event => setLink(event.target.value)} placeholder="Add a YouTube stream link" aria-label="Add a YouTube stream link" className="min-w-0 flex-1 border border-white/15 bg-black/30 px-2 py-1.5 text-xs placeholder:text-white/40" />
        <button className="border border-white/15 px-2.5 py-1.5 font-semibold text-white/70 hover:text-white">Add</button>
      </form>
      {message && <p className="text-white/60" role="status">{message}</p>}
    </div>
  </aside>;
}

/** ▶ beside a match: jumps the livestream to it, when it can be placed. */
export function JumpButton({ match }: { match: any }) {
  const jumper = useJumper();
  if (!jumper) return null;
  const target = jumper.jumpFor(match);
  if (!target) return null;
  return <button onClick={() => jumper.jump(match)} title={`Watch ${match.name} on the livestream (${videoTime(target.seconds)})`} aria-label={`Watch ${match.name} on the livestream`}
    className="inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-white/15 text-white/60 transition-colors hover:border-[var(--c-accent)] hover:text-[var(--c-accent)]"><Play className="h-3 w-3 fill-current" /></button>;
}

/** "Watch livestream": opens the dock, for an event that has a stream (or to add one). */
export function WatchButton({ className = '' }: { className?: string }) {
  const jumper = useJumper();
  if (!jumper) return null;
  return <button onClick={jumper.open} className={`inline-flex items-center gap-2 border border-white/15 px-3 py-2 text-xs font-semibold uppercase tracking-wider text-white/70 hover:border-[var(--c-accent)] hover:text-white ${className}`}>
    <Play className="h-3.5 w-3.5 fill-current" />{jumper.streams.length ? 'Watch livestream' : 'Add livestream'}</button>;
}
