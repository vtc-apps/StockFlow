import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

// Builds everything (JS, CSS, icon) into one self-contained dist-single/index.html
export default defineConfig({
  base: './',
  plugins: [react(), viteSingleFile()],
  build: { outDir: 'dist-single', assetsInlineLimit: 100000000, cssCodeSplit: false, chunkSizeWarningLimit: 2000 },
});
