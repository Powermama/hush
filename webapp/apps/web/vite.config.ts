import { paraglideVitePlugin } from "@inlang/paraglide-js";
import paraglideConfig from "./project.inlang/paraglide.config.ts";
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { sitePages, privatePageMetadata } from "./shared/site.ts";
import { renderPageHead } from "./shared/site-head.ts";

export default defineConfig({
  plugins: [paraglideVitePlugin({ project: "./project.inlang", ...paraglideConfig }), react(), tailwindcss(), {
    name: "hush-page-metadata",
    transformIndexHtml(html, context) {
      const page = sitePages[context.path === "/index.html" ? "/" : context.path] ?? privatePageMetadata;
      return html.replace("<!--hush-head-start--><!--hush-head-end-->", `<!--hush-head-start-->${renderPageHead(page)}<!--hush-head-end-->`);
    },
  }],
  // Dev server only: pre-bundle three.js with the add-ons the scenes use, so they
  // share one instance. Otherwise late-discovered add-ons bring their own copy and
  // the rose falls back to its 2D drawing.
  optimizeDeps: {
    include: [
      "three",
      "three/addons/loaders/GLTFLoader.js",
      "three/addons/environments/RoomEnvironment.js",
      "three/addons/utils/BufferGeometryUtils.js",
    ],
  },
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
    // scripts/prerender.ts reads it to preload the landing scene on first visits.
    manifest: true,
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
