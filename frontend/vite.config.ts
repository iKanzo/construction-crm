/// <reference types="vitest/config" />
import { fileURLToPath, URL } from 'node:url';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

const srcDir = fileURLToPath(new URL('./src', import.meta.url));

export default defineConfig({
  plugins: [react()],
  resolve: { alias: { '@': srcDir } },
  css: { preprocessorOptions: { scss: { api: 'modern' } } },
  server: { fs: { allow: ['..'] } },
  test: {
    environment: 'jsdom',
    css: { modules: { classNameStrategy: 'non-scoped' } },
    include: ['../tests/frontend/**/*.test.{ts,tsx}'],
    setupFiles: ['../tests/frontend/setup.ts'],
  },
});
