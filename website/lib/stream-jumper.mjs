/**
 * The jumper, after OpenScout's: an event's livestream beside its schedule,
 * and a jump from any match to the moment it was played. Mirrored by
 * VEXRankKit's StreamJumper.swift.
 *
 * The schedule's times are not when matches were played - events run late
 * (Caution Tape's Q1, scheduled 9:00, started 9:33). Each match's `started`
 * time is: the moment the field was started. So a position in the video is
 *
 *   sync.seconds + (match.started - syncMatch.started)
 *
 * from one known point - "this match starts here" - which anyone watching can
 * set and which then places every other match on that stream. Where YouTube's
 * own start time is known (the Worker reads it when it has an API key) that is
 * the known point instead: (match.started - stream.startTime). A per-viewer
 * nudge takes up the seconds either is off by.
 */

const YOUTUBE_ID = /^[A-Za-z0-9_-]{11}$/;

/** The YouTube video id in a link, or null. Channel and playlist links have none. */
export function youtubeId(url) {
  let parsed;
  try { parsed = new URL(String(url).trim()); } catch { return null; }
  const host = parsed.hostname.replace(/^(www|m|music)\./, '');
  let id = null;
  if (host === 'youtu.be') id = parsed.pathname.split('/')[1];
  else if (host === 'youtube.com' || host === 'youtube-nocookie.com') {
    const [, kind, value] = parsed.pathname.split('/');
    id = kind === 'watch' ? parsed.searchParams.get('v') : ['live', 'embed', 'shorts', 'v'].includes(kind) ? value : null;
  }
  return id && YOUTUBE_ID.test(id) ? id : null;
}

/** Every link in a block of text (the organizer's webcast notes). */
export function linksIn(text) {
  return [...new Set((String(text ?? '').match(/https?:\/\/[^\s<>"')\]]+/g) ?? []).map(link => link.replace(/[.,;:!?]+$/, '')))];
}

/**
 * Streams an event lists: the YouTube videos in the organizer's webcast notes,
 * then any a viewer added, one entry per video. Other links (a channel page, a
 * Twitch channel) cannot be jumped in and come back separately to open as links.
 */
export function eventStreams(webcastText, added = []) {
  const streams = [], seen = new Set(), others = [];
  const push = (stream) => { if (!seen.has(stream.videoId)) { seen.add(stream.videoId); streams.push(stream); } };
  for (const url of linksIn(webcastText)) {
    const videoId = youtubeId(url);
    if (videoId) push({ videoId, url, source: 'event' });
    else others.push(url);
  }
  for (const stream of added) if (stream?.videoId && YOUTUBE_ID.test(stream.videoId)) push({ ...stream, source: stream.source ?? 'viewer' });
  return { streams, others };
}

const startedAt = (match) => { const time = Date.parse(match?.started ?? ''); return Number.isFinite(time) ? time : null; };

/** When a stream's video starts, in ms, from its sync point or YouTube's start time. */
export function streamOrigin(stream, matchesById) {
  if (stream?.sync && Number.isFinite(Number(stream.sync.seconds))) {
    const anchor = startedAt(matchesById.get(Number(stream.sync.matchId)));
    if (anchor !== null) return anchor - Number(stream.sync.seconds) * 1000;
  }
  const start = Date.parse(stream?.startTime ?? '');
  return Number.isFinite(start) ? start : null;
}

/**
 * The stream a match is on: of the timed streams for its division (or for
 * every division), the one that began most recently before the match did.
 * That is how a stream per day, or a restarted stream, is told apart.
 */
export function streamForMatch(streams, match, matchesById) {
  const time = startedAt(match);
  if (time === null) return null;
  const division = match.division?.id ?? match.divisionId ?? null;
  const timed = streams.map(stream => ({ stream, origin: streamOrigin(stream, matchesById) })).filter(entry => entry.origin !== null)
    .filter(entry => !entry.stream.divisionId || division === null || Number(entry.stream.divisionId) === Number(division));
  if (!timed.length) return null;
  const before = timed.filter(entry => entry.origin <= time);
  const pick = before.length ? before.reduce((a, b) => (b.origin > a.origin ? b : a)) : timed.reduce((a, b) => (b.origin < a.origin ? b : a));
  return pick;
}

/**
 * Where in the video `match` begins, in whole seconds, with the viewer's nudge
 * for that stream - or null when the match has not been played, no stream is
 * timed yet, or the match falls before the video does.
 */
export function matchJump(streams, match, matchesById, nudges = {}) {
  const found = streamForMatch(streams, match, matchesById);
  if (!found) return null;
  const seconds = Math.round((startedAt(match) - found.origin) / 1000 + Number(nudges[found.stream.videoId] ?? 0));
  return seconds >= 0 ? { videoId: found.stream.videoId, seconds } : null;
}

/** Every match at an event by id, with its division, for the lookups above. */
export function matchesById(divisions) {
  const map = new Map();
  for (const division of divisions ?? []) for (const match of division.matches ?? []) map.set(Number(match.id), { ...match, division: { id: division.id, name: division.name } });
  return map;
}

/** "1:02:03" / "4:05" for a video position. */
export function videoTime(seconds) {
  const s = Math.max(0, Math.round(seconds)), h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60;
  return h ? `${h}:${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}` : `${m}:${String(r).padStart(2, '0')}`;
}
