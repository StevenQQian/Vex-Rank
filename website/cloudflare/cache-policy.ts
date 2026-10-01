// How long a cached response counts as current, and how long past that it may
// still be served when official data cannot be reached at all.
export const FRESH_FOR = 900000;      // 15 minutes
export const STALE_FOR = 86400;       // 24 hours, in seconds

/// Which copy to serve, given what is in the cache.
///
/// `fresh` goes straight back. `stale` goes back immediately too, with a
/// refresh started behind it - official data takes seconds when it is working
/// and hangs when it is not, and the reader gains nothing from waiting for it
/// when we are holding the same answer a few minutes older. `miss` has to wait,
/// because there is nothing else to show.
///
/// A reader who pulled to refresh is asking whether anything has changed, so
/// they get the slow, truthful path rather than the copy they already have.
export function cacheDecision(
  saved: { expires_at: number } | null,
  now: number,
  wantsLive: boolean,
): { serve: 'fresh' | 'stale' | 'miss'; age: number } {
  if (!saved) return { serve: 'miss', age: 0 };
  const age = Math.round((now - (saved.expires_at - FRESH_FOR)) / 1000);
  if (saved.expires_at > now) return { serve: wantsLive ? 'miss' : 'fresh', age };
  if (wantsLive || age > STALE_FOR) return { serve: 'miss', age };
  return { serve: 'stale', age };
}
