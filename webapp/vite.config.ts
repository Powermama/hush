import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { sitePages, privatePageMetadata } from "./shared/site.ts";
import { renderPageHead } from "./shared/site-head.ts";

export default defineConfig({
  plugins: [react(), tailwindcss(), {
    name: "hush-page-metadata",
    transformIndexHtml(html, context) {
      const page = sitePages[context.path === "/index.html" ? "/" : context.path] ?? privatePageMetadata;
      return html.replace("<!--hush-head-start--><!--hush-head-end-->", `<!--hush-head-start-->${renderPageHead(page)}<!--hush-head-end-->`);
    },
  }],
  server: {
    proxy: {
      "/v1": "http://127.0.0.1:3000",
      "/health": "http://127.0.0.1:3000",
      "/openapi.json": "http://127.0.0.1:3000",
    },
  },
  build: {
    target: "es2022",
    cssMinify: "lightningcss",
    rolldownOptions: {
      output: {
        codeSplitting: {
          // Cache the deferred 3D engine independently of the small scene module.
          groups: [{ name: "three", test: /node_modules\/three\//, maxSize: 400_000 }],
        },
      },
    },
  },
});
