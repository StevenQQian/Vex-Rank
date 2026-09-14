import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';
const here=fileURLToPath(new URL('.',import.meta.url));
await build({entryPoints:[`${here}src/index.ts`],outfile:`${here}lib/index.js`,bundle:true,platform:'node',format:'esm',target:'node22',packages:'external',alias:{'@':fileURLToPath(new URL('../../',import.meta.url)),'cloudflare:workers':`${here}src/cloudflare-adapter.ts`}});
