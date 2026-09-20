import { fileURLToPath, URL } from "node:url";

import react from "@vitejs/plugin-react";
// vitest's defineConfig extends Vite's with the `test` key, so one file configures both.
import { defineConfig } from "vitest/config";

const API_TARGET = process.env.VITE_API_TARGET ?? "http://localhost:8000";

export default defineConfig({
  plugins: [react()],

  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },

  server: {
    port: 5173,

    // The SPA calls /api/* as a relative path and the dev server forwards it to the
    // backend. That mirrors production, where CloudFront serves the bundle and
    // forwards /api/* to the ALB from the same origin - so there is no CORS in either
    // environment, and no environment-specific base URL in the client.
    proxy: {
      "/api": { target: API_TARGET, changeOrigin: true },
      "/healthz": { target: API_TARGET, changeOrigin: true },
    },
  },

  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    css: false,
  },
});
