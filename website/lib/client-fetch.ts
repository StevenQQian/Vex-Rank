declare const __VEX_API_BASE__: string;
declare const __VEX_ASSET_BASE__: string;

/** Separate API and asset origins for GitHub Pages; keep same-origin hosting working. */
export function siteFetch(path:string, init?:RequestInit) {
  const apiBase=typeof __VEX_API_BASE__==='undefined'?'':__VEX_API_BASE__;
  const assetBase=typeof __VEX_ASSET_BASE__==='undefined'?'/':__VEX_ASSET_BASE__;
  const archive=/^\/rankings-20\d{2}-\d{2}-vcr3\.json$/.test(path);
  const url=path.startsWith('/api/')||archive&&apiBase?`${apiBase}${path}`:path.startsWith('/')?`${assetBase}${path.slice(1)}`:path;
  return fetch(url,init);
}

