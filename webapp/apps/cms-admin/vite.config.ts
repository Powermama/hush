// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { fileURLToPath } from "node:url";
import tailwindcss from "@tailwindcss/vite";
import { tanstackRouter } from "@tanstack/router-plugin/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// The CMS serves the built admin on its own origin (apps/cms/src/app.ts). In
// development, Vite serves the admin with hot reload on http://localhost:5174
// and forwards the API to the local CMS of bun run dev (apps/cms
// admin:server, HTTPS with a throwaway certificate).
const cms = { target: process.env.HUSH_CMS_DEV_URL ?? "https://localhost:4310", changeOrigin: true, secure: false };

export default defineConfig({
  // File-based routes (src/routes); the plugin must come before React's.
  plugins: [tanstackRouter({ target: "react", autoCodeSplitting: true }), react(), tailwindcss()],
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  server: { port: 5174, strictPort: true, proxy: { "/v1": cms, "/auth": cms, "/blog/media": cms, "/__e2e": cms } },
  build: {
    rolldownOptions: {
      output: {
        // CodeMirror loads only with the editor and changes rarely: its own chunk caches apart from the app.
        codeSplitting: { groups: [{ name: "codemirror", test: /node_modules[\\/].*(@codemirror|@lezer|crelt|style-mod|w3c-keyname)/ }] },
      },
    },
  },
});
