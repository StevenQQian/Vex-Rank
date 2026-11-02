/**
 * Official rulings on qualification matches: which team, in which match, had
 * its result changed from what the scores say - only where the data makes it
 * certain. Mirrored by VEXRankKit's Rulings.swift.
 *
 * VEX IQ: explicit. Both stations of a teamwork match carry the one shared
 * score; when they differ, the lower station's team was disqualified (or did
 * not show). The same rule OpenScout uses (iqMatchResult).
 *
 * V5: match records carry no DQ flag, and the official standings are not
 * always reproducible from the scores (on 2026-27 Override results some teams
 * gain more official wins than any disqualification rule allows), so a cause
 * is never claimed. What can be read with certainty is the result: a team
 * whose official record has k fewer wins than its scores give, and that won
 * exactly k matches on score, had each of those counted as a loss ("ruled
 * loss"); the same reasoning finds a "ruled win". When a gap could sit in more
 * than one match, no match is marked and the team is listed as unresolved.
 */
import { allianceNumbers, isPlayed, isQualification } from './team-event.mjs';

const upper = value => String(value ?? '').toUpperCase();
const outcome = (own, other) => (own > other ? 'won' : own < other ? 'lost' : 'tied');

/**
 * @returns {{ byMatch: Map<number, { team: string, ruling: 'dq'|'ruled-loss'|'ruled-win' }[]>, unresolved: string[] }}
 */
export function officialRulings(division, { iq = false } = {}) {
  const byMatch = new Map();
  const add = (matchId, team, ruling) => { const list = byMatch.get(matchId) ?? []; list.push({ team, ruling }); byMatch.set(matchId, list); };
  const played = (division?.matches ?? []).filter(match => isQualification(match) && isPlayed(match) && (match.alliances ?? []).length === 2);

  if (iq) {
    for (const match of played) {
      const [a, b] = match.alliances.map(alliance => Number(alliance.score));
      if (!Number.isFinite(a) || !Number.isFinite(b) || a === b) continue;
      for (const team of allianceNumbers(match.alliances[a < b ? 0 : 1])) add(match.id, team, 'dq');
    }
    return { byMatch, unresolved: [] };
  }

  const results = new Map();
  for (const match of played) {
    const [a, b] = match.alliances;
    for (const [own, other] of [[a, b], [b, a]]) for (const team of allianceNumbers(own)) {
      const key = upper(team);
      if (!results.has(key)) results.set(key, { name: team, won: [], lost: [], tied: [] });
      results.get(key)[outcome(Number(own.score), Number(other.score))].push(match.id);
    }
  }
  const unresolved = [];
  for (const row of division?.rankings ?? []) {
    const key = upper(row.team?.name ?? row.team?.number);
    const mine = results.get(key);
    if (!mine) continue;
    const fewer = mine.won.length - Number(row.wins ?? 0);
    const more = Number(row.wins ?? 0) - mine.won.length;
    if (fewer > 0) {
      // Every win on score was overturned: certain which matches.
      if (fewer === mine.won.length && Number(row.ties ?? 0) === mine.tied.length) for (const id of mine.won) add(id, mine.name, 'ruled-loss');
      else unresolved.push(mine.name);
    } else if (more > 0) {
      const notWon = [...mine.lost, ...mine.tied];
      if (more === notWon.length) for (const id of notWon) add(id, mine.name, 'ruled-win');
      else unresolved.push(mine.name);
    } else if (Number(row.losses ?? 0) !== mine.lost.length || Number(row.ties ?? 0) !== mine.tied.length) {
      unresolved.push(mine.name);
    }
  }
  return { byMatch, unresolved };
}

/** `team`'s ruling in `match`, if any. */
export function rulingFor(rulings, match, team) {
  return (rulings?.byMatch?.get(match?.id) ?? []).find(entry => upper(entry.team) === upper(team))?.ruling ?? null;
}

export const RULING_LABELS = Object.freeze({ dq: 'DQ', 'ruled-loss': 'Ruled loss', 'ruled-win': 'Ruled win' });
