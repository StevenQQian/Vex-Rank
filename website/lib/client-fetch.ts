declare const __VEX_API_BASE__: string;
declare const __VEX_ASSET_BASE__: string;

/** Separate API and asset origins for GitHub Pages; keep same-origin hosting working. */
export function siteFetch(path:string, init?:RequestInit) {
  // Build-time constants: the API can live on a Worker while assets live beneath
  // a GitHub Pages repository path. Undefined constants support same-origin dev.
  const apiBase=typeof __VEX_API_BASE__==='undefined'?'':__VEX_API_BASE__;
  const assetBase=typeof __VEX_ASSET_BASE__==='undefined'?'/':__VEX_ASSET_BASE__;
  // Versioned archives use the API origin when configured because the Worker
  // serves its archive assets there; ordinary static files use the Pages base.
  const archive=/^\/rankings-20\d{2}-\d{2}-vcr3\.json$/.test(path);
  const url=path.startsWith('/api/')||archive&&apiBase?`${apiBase}${path}`:path.startsWith('/')?`${assetBase}${path.slice(1)}`:path;
  return fetch(url,init);
}

