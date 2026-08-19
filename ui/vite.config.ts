import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
export default defineConfig({ base: '/ui/assets/', plugins: [react()], build: { outDir: 'dist', emptyOutDir: true } })
