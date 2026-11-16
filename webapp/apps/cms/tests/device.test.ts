// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Device sign-in journeys (docs/user-journeys/cms.md): the CLI's
// `hush-cms auth login`, through the API with the admin configured as in
// production (cross-site form posts refused), against PostgreSQL.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { eq, sql } from "drizzle-orm";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createApp } from "../src/app";
import { normalizeUserCode } from "../src/auth/device";
import { createToken } from "../src/auth/tokens";
import type { AdminConfig } from "../src/config";
import { deviceAuthorizations } from "../src/db/schema";
import { LocalObjectStore } from "../src/storage/object-store";
import { createTestDatabase, serverUrl } from "./database";
import { credentials, ownerSession } from "./fixtures";

const admin: AdminConfig = {
  publicUrl: "https://cms.behu.sh",
  github: { clientId: "client-id", clientSecret: "client-secret" },
  allowedGithubIds: new Set([1]),
};

describe.skipIf(!serverUrl)("CMS device sign-in", () => {
  let database: Awaited<ReturnType<typeof createTestDatabase>>;
  let app: ReturnType<typeof createApp>;
  let owner = "";

  beforeAll(async () => {
    database = await createTestDatabase();
    app = createApp({ db: database.db, media: new LocalObjectStore(await mkdtemp(join(tmpdir(), "hush-cms-device-"))) }, { admin });
    owner = await ownerSession(database.db);
  });
  afterAll(async () => { await database?.drop(); });

  /** As the CLI sends it: JSON, no cookie and no Origin. */
  const cli = async (path: string, body?: unknown, token?: string, method = "POST") => {
    const response = await app.request(path, {
      method, body: body === undefined ? undefined : JSON.stringify(body),
      headers: { ...(body === undefined ? {} : { "content-type": "application/json" }), ...(token ? { authorization: `Bearer ${token}` } : {}) },
    });
    return { status: response.status, headers: response.headers, body: response.status === 204 ? {} : await response.json() as Record<string, any> };
  };
  /** As the admin sends it: the owner's session from the CMS's own origin. */
  const asOwner = async (method: string, path: string) => {
    const response = await app.request(path, { method, headers: { ...credentials(owner), origin: admin.publicUrl } });
    return { status: response.status, body: response.status === 204 ? {} : await response.json() as Record<string, any> };
  };
  const pollAfterWait = async (deviceCode: string) => {
    // Polls closer than the interval are answered with slow_down; move the last poll back instead of waiting.
    await database.db.execute(sql`update device_authorizations set last_polled_at = now() - interval '1 minute'`);
    return cli("/v1/auth/device/token", { deviceCode });
  };

  test("CMS-DEVICE-001 the CLI signs in once the owner approves its code, and gets its token exactly once", async () => {
    const start = await cli("/v1/auth/device", { clientName: "hush-cms on a test Mac" });
    expect(start.status).toBe(200);
    expect(start.headers.get("cache-control")).toBe("no-store");
    const { deviceCode, userCode, verificationUri, verificationUriComplete, expiresIn, interval } = start.body;
    expect(userCode).toMatch(/^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$/);
    expect(verificationUri).toBe("https://cms.behu.sh/device");
    expect(verificationUriComplete).toBe(`https://cms.behu.sh/device?code=${userCode}`);
    expect([expiresIn, interval]).toEqual([900, 5]);
    const [stored] = await database.db.select().from(deviceAuthorizations).where(eq(deviceAuthorizations.userCode, userCode));
    expect(stored!.deviceCodeHash).not.toBe(deviceCode);

    expect((await cli("/v1/auth/device/token", { deviceCode })).body.error.code).toBe("authorization_pending");
    expect((await cli("/v1/auth/device/token", { deviceCode })).body.error.code).toBe("slow_down");

    // The owner sees what asks for access, by the code typed in any form.
    const pending = await asOwner("GET", `/v1/auth/device/${userCode.toLowerCase().replace("-", " ")}`);
    expect(pending.body).toMatchObject({ userCode, clientName: "hush-cms on a test Mac", scopes: ["posts:read", "posts:write", "posts:publish"], tokenDays: 90 });
    expect((await asOwner("POST", `/v1/auth/device/${userCode}/approve`)).status).toBe(204);
    expect((await asOwner("GET", `/v1/auth/device/${userCode}`)).status).toBe(404);

    const granted = await pollAfterWait(deviceCode);
    expect(granted.status).toBe(200);
    expect(granted.headers.get("cache-control")).toBe("no-store");
    expect(granted.body.actor).toBe("token:hush-cms on a test Mac");
    const me = await cli("/v1/me", undefined, granted.body.token, "GET");
    expect(me.body).toMatchObject({ actor: "token:hush-cms on a test Mac", scopes: ["posts:read", "posts:write", "posts:publish"] });
    expect(new Date(me.body.expiresAt).getTime() - Date.now()).toBeGreaterThan(89 * 86_400_000);
    expect((await pollAfterWait(deviceCode)).body.error.code).toBe("invalid_grant");
  });

  test("CMS-DEVICE-002 a denied or expired sign-in gets no token, and only the owner decides", async () => {
    const denied = (await cli("/v1/auth/device", { clientName: "hush-cms elsewhere" })).body;
    const token = await createToken(database.db, { name: "agent", scopes: ["posts:read", "posts:write", "posts:publish"] });
    expect((await cli(`/v1/auth/device/${denied.userCode}/approve`, undefined, token)).status).toBe(403);
    // Signed out, even from the admin's own origin.
    expect((await app.request(`/v1/auth/device/${denied.userCode}/approve`, { method: "POST", headers: { origin: admin.publicUrl } })).status).toBe(401);
    expect((await asOwner("POST", `/v1/auth/device/${denied.userCode}/deny`)).status).toBe(204);
    expect((await asOwner("POST", `/v1/auth/device/${denied.userCode}/approve`)).status).toBe(404);
    expect((await pollAfterWait(denied.deviceCode)).body.error.code).toBe("access_denied");

    const late = (await cli("/v1/auth/device", { clientName: "hush-cms, too late" })).body;
    await database.db.update(deviceAuthorizations).set({ expiresAt: new Date(Date.now() - 1000) }).where(eq(deviceAuthorizations.userCode, late.userCode));
    expect((await asOwner("POST", `/v1/auth/device/${late.userCode}/approve`)).status).toBe(404);
    expect((await pollAfterWait(late.deviceCode)).body.error.code).toBe("expired_token");
    expect((await cli("/v1/auth/device/token", { deviceCode: "not-a-device-code" })).body.error.code).toBe("invalid_grant");
    expect(normalizeUserCode("bcdf-ghj")).toBeUndefined();
  });

  test("CMS-DEVICE-003 a token revokes itself when the CLI signs out", async () => {
    const token = await createToken(database.db, { name: "signing-out", scopes: ["posts:read"] });
    expect((await cli("/v1/me", undefined, token, "DELETE")).status).toBe(204);
    expect((await cli("/v1/me", undefined, token, "GET")).status).toBe(401);
    expect((await asOwner("DELETE", "/v1/me")).body.error.code).toBe("not_a_token");
  });
});
