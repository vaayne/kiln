import { defineConfig } from 'vite'
import preact from '@preact/preset-vite'
export default defineConfig({ base: '/ui/assets/', plugins: [preact()], build: { outDir: 'dist', emptyOutDir: true } })
