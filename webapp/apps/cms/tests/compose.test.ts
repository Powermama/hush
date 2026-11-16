// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// compose.yaml is the CMS stack in one file; compose.coolify.yaml is Coolify's
// part of it (the API runs beside it as an application). They must not drift.
import { expect, test } from "bun:test";
import { join } from "node:path";

const load = async (name: string) => Bun.YAML.parse(await Bun.file(join(import.meta.dir, "..", name)).text()) as {
  services: Record<string, Record<string, unknown>>; volumes: Record<string, unknown>;
};

test("Coolify's file runs the scheduler and PostgreSQL exactly as compose.yaml does, and the API publishes no host port", async () => {
  const stack = await load("compose.yaml");
  const coolify = await load("compose.coolify.yaml");
  expect(Object.keys(coolify.services).sort()).toEqual(["cms-postgres", "cms-scheduler"]);
  for (const name of ["cms-scheduler", "cms-postgres"]) expect(coolify.services[name]).toEqual(stack.services[name]!);
  expect(coolify.volumes).toEqual(stack.volumes);
  // A host port would stop a platform from running the old and new API side by side.
  expect(stack.services.cms!.ports).toBeUndefined();
  expect((stack.services.cms!.environment as Record<string, string>).CMS_DATABASE_URL).toContain("@cms-postgres:5432/");
});
