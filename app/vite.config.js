import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],

  // The app lives in app/ but .env lives at the repo root, next to
  // .env.example and netlify.toml. Without this Vite would look only in app/
  // and silently find nothing — the app would build fine and fail at runtime.
  // Netlify is unaffected: it injects env vars into the process directly.
  envDir: '..',
})
