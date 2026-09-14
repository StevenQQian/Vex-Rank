import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/postcss';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  root:fileURLToPath(new URL('./pages',import.meta.url)),
  base:'/Vex-Rank/',
  publicDir:fileURLToPath(new URL('./public',import.meta.url)),
  resolve:{alias:{'@':fileURLToPath(new URL('.',import.meta.url))}},
  plugins:[react()],
  css:{postcss:{plugins:[tailwindcss()]}},
  define:{
    __VEX_API_BASE__:JSON.stringify(process.env.VEX_API_BASE || 'https://us-central1-vexrank-test.cloudfunctions.net/api'),
    __VEX_ASSET_BASE__:JSON.stringify('/Vex-Rank/'),
  },
  build:{outDir:'../dist-pages',emptyOutDir:true},
});
