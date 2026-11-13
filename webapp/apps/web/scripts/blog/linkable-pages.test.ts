// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { expect, test } from "bun:test";
import { linkableSitePaths } from "@hush/article/taxonomy";
import { sitePages } from "../../shared/site";

// Articles are validated against @hush/article's list of linkable pages, in the
// static build and in the CMS. Every page on it must exist on the website.
test("every page articles may link to exists", () => {
  for (const path of linkableSitePaths) expect(sitePages[path], path).toBeDefined();
});
