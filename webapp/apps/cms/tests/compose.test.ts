// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// compose.yaml is the CMS stack in one file, which any Docker host runs and
// other platforms map (docs/reference/deploy-anywhere.md).
import { expect, test } from "bun:test";
import { join } from "node:path";

test("the API publishes no host port, so a platform can roll it over, and reaches PostgreSQL by service name", async () => {
  const stack = Bun.YAML.parse(await Bun.file(join(import.meta.dir, "..", "compose.yaml")).text()) as {
    services: Record<string, Record<string, unknown>>;
  };
  // A host port would stop a platform from running the old and new API side by side.
  expect(stack.services.cms!.ports).toBeUndefined();
  expect((stack.services.cms!.environment as Record<string, string>).CMS_DATABASE_URL).toContain("@cms-postgres:5432/");
  expect(stack.services["cms-scheduler"]!.command).toEqual(["bun", "run", "cms:scheduler"]);
});
