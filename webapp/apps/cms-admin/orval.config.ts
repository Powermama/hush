// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Typed TanStack Query hooks from the CMS's OpenAPI document. The output is
// generated (bun run api:client) and checked for drift in CI; never edit it.
import { defineConfig } from "orval";

export default defineConfig({
  cms: {
    input: { target: "../cms/openapi/hush-cms.json" },
    output: {
      mode: "single",
      target: "src/api/cms.generated.ts",
      client: "react-query",
      httpClient: "fetch",
      baseUrl: "",
      override: {
        mutator: { path: "src/api/fetcher.ts", name: "cmsFetch" },
      },
    },
  },
});
