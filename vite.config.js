import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// GitHub Pages serves a project repository from https://<user>.github.io/<repo>/.
// The app uses hash-based routing (#/inventory), so a relative base ('./') works
// at any sub-path without extra config. To pin an absolute base instead, set
// VITE_BASE=/your-repo-name/ when building.
export default defineConfig({
  base: process.env.VITE_BASE || './',
  plugins: [react()],
  build: {
    outDir: 'dist',
    sourcemap: false,
    chunkSizeWarningLimit: 900,
    rollupOptions: {
      output: {
        manualChunks: {
          charts: ['recharts'],
        },
      },
    },
  },
});
