const pages = new Map<string, { expires:number; data:any }>();
/** Read complete official collections. A failed page must never masquerade as no results. */
export async function mapLimit<T, R>(items: T[], limit: number, mapper: (item: T) => Promise<R>): Promise<R[]> {
  const results = new Array<R>(items.length);
  let cursor = 0;
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (cursor < items.length) {
      const index = cursor++;
      results[index] = await mapper(items[index]);
    }
  }));
  return results;
}

export async function vexJson(url: string, headers: Record<string, string>): Promise<any> {
  const cached=pages.get(url);
  if(cached&&cached.expires>Date.now())return cached.data;
  let lastStatus = 0;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const response = await fetch(url, { headers, signal: AbortSignal.timeout(15000) });
      if (response.ok) {
        const data=await response.json();
        if(pages.size>=600)pages.delete(pages.keys().next().value!);
        pages.set(url,{expires:Date.now()+300000,data});
        return data;
      }
      lastStatus = response.status;
      if (response.status !== 429 && response.status < 500) throw new Error(`Event.VEX request failed (${response.status}).`);
      await response.body?.cancel();
      if(response.status===429&&attempt<2){
        const seconds=Number(response.headers.get('retry-after'));
        await new Promise(resolve=>setTimeout(resolve,Math.min(10000,Math.max(2000,Number.isFinite(seconds)?seconds*1000:2000))));
      }
    } catch (error) {
      if (attempt === 2 || (error instanceof Error && error.message.startsWith('Event.VEX request failed'))) throw error;
    }
    if (attempt < 2) await new Promise(resolve => setTimeout(resolve, 400 * 2 ** attempt));
  }
  throw new Error(`Event.VEX is temporarily unavailable (${lastStatus}). Please retry.`);
}

export async function vexCollection(url: string, headers: Record<string, string>): Promise<any[]> {
  const parsed = new URL(url);
  parsed.searchParams.set('per_page', '250');
  parsed.searchParams.set('page', '1');
  const first = await vexJson(parsed.href, headers);
  if (!Array.isArray(first.data)) throw new Error('Event.VEX returned an invalid collection.');
  const lastPage = Math.max(1, Number(first.meta?.last_page ?? 1));
  const rest = await mapLimit(Array.from({ length: lastPage - 1 }, (_, index) => index + 2), 2, async page => {
    const next = new URL(parsed);
    next.searchParams.set('page', String(page));
    const payload = await vexJson(next.href, headers);
    if (!Array.isArray(payload.data)) throw new Error('Event.VEX returned an invalid collection.');
    return payload.data;
  });
  return [...first.data, ...rest.flat()];
}
