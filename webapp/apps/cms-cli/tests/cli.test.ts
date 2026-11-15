// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// CLI journeys (apps/cms/docs/user-journeys/cms.md): the real hush-cms command
// against the real CMS, started as its own process on a fresh PostgreSQL
// database, as an agent on a Mac uses it.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import postgres from "postgres";

const serverUrl = process.env.HUSH_TEST_DATABASE_URL;
// CI provides PostgreSQL; never let the CLI journeys skip there.
if (process.env.CI && !serverUrl) throw new Error("HUSH_TEST_DATABASE_URL is required in CI");

const cmsDir = join(import.meta.dir, "../../cms");
const fixtures = join(import.meta.dir, "fixtures");
const article = "en/dictate-from-the-terminal.md";

describe.skipIf(!serverUrl)("hush-cms CLI", () => {
  const databaseName = `hush_cms_cli_test_${crypto.randomUUID().replaceAll("-", "")}`;
  const admin = serverUrl ? postgres(serverUrl, { max: 1, onnotice: () => {} }) : undefined;
  let cms: ReturnType<typeof Bun.spawn> | undefined;
  let url = "";
  let work = "";
  const tokens = { agent: "", owner: "" };
  const databaseUrl = () => Object.assign(new URL(serverUrl!), { pathname: `/${databaseName}` }).toString();

  beforeAll(async () => {
    await admin!.unsafe(`create database ${databaseName}`);
    work = await mkdtemp(join(tmpdir(), "hush-cms-cli-"));
    await cp(fixtures, join(work, "content"), { recursive: true });
    const environment = {
      ...process.env, NODE_ENV: "test", CMS_DATABASE_URL: databaseUrl(), PORT: "0",
      CMS_MEDIA_DIR: join(work, "media"), CMS_BACKUP_DIR: join(work, "backups"), CMS_ADMIN_DIR: join(work, "no-admin"),
      CMS_SHUTDOWN_DRAIN_MS: "0",
    };
    cms = Bun.spawn(["bun", "src/index.ts"], { cwd: cmsDir, env: environment, stdout: "pipe", stderr: "inherit" });
    // The CMS migrates, then logs the port it listens on.
    const reader = (cms.stdout as ReadableStream<Uint8Array>).getReader();
    let log = "";
    while (!/"port":\d+/.test(log)) {
      const { value, done } = await reader.read();
      if (done) throw new Error(`The CMS stopped before listening:\n${log}`);
      log += new TextDecoder().decode(value);
    }
    reader.releaseLock();
    url = `http://127.0.0.1:${/"port":(\d+)/.exec(log)![1]}`;
    const token = (name: string, scopes: string) => {
      const created = Bun.spawnSync(["bun", "src/commands/create-token.ts", "--name", name, "--scopes", scopes], { cwd: cmsDir, env: environment });
      if (created.exitCode !== 0) throw new Error(created.stderr.toString());
      return created.stdout.toString().trim();
    };
    tokens.agent = token("hush-seo", "posts:read,posts:write");
    tokens.owner = token("owner", "posts:read,posts:write,posts:publish");
  }, 60_000);

  afterAll(async () => {
    cms?.kill();
    await cms?.exited;
    await admin?.unsafe(`drop database if exists ${databaseName} with (force)`);
    await admin?.end({ timeout: 5 });
    if (work) await rm(work, { recursive: true, force: true });
  });

  /** Runs hush-cms in the work directory as the given token. */
  async function cli(args: string[], options: { token?: string | null; stdin?: string } = {}) {
    const token = options.token === undefined ? tokens.agent : options.token;
    const environment: Record<string, string | undefined> = { ...process.env, HUSH_CMS_URL: url, HUSH_CMS_TOKEN: token ?? undefined };
    if (token === null) delete environment.HUSH_CMS_TOKEN;
    const child = Bun.spawn(["bun", join(import.meta.dir, "../src/main.ts"), ...args], {
      cwd: work, env: environment, stdin: options.stdin === undefined ? "ignore" : new TextEncoder().encode(options.stdin), stdout: "pipe", stderr: "pipe",
    });
    const [stdout, stderr, exitCode] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited]);
    return { stdout, stderr, exitCode, json: () => JSON.parse(stdout) };
  }
  const file = (path: string) => join(work, "content", path);

  test("CMS-CLI-001 pushes an article file as a draft with its images, and again only when it changed", async () => {
    const created = await cli(["posts", "push", file(article)]);
    expect(created.stderr).toBe("");
    expect(created.exitCode).toBe(0);
    expect(created.stdout).toContain("Created draft en/dictate-from-the-terminal");
    expect(created.stdout).toContain("Uploaded terminal.png.");
    expect(created.stdout).toContain("It meets the article contract.");

    // The file says draft: false, yet a push never makes anything live.
    const post = (await cli(["posts", "get", "dictate-from-the-terminal", "--json"])).json();
    expect(post).toMatchObject({ status: "draft", publishedAt: null, keyword: "dictate in the terminal", secondaryKeywords: ["terminal dictation mac", "voice commands terminal"] });

    const again = await cli(["posts", "push", file(article), "--json"]);
    expect(again.json()).toMatchObject({ action: "unchanged", media: { uploaded: [], unchanged: ["terminal.png"] }, problems: [] });

    const source = await readFile(file(article), "utf8");
    await writeFile(file(article), source.replace("Only to download the model once.", "Only once, to download the model."));
    expect((await cli(["posts", "push", file(article)])).stdout).toContain("Updated draft en/dictate-from-the-terminal");
    const revisions = (await cli(["posts", "revisions", "dictate-from-the-terminal", "--json"])).json().revisions;
    expect(revisions.map((revision: { actor: string }) => revision.actor)).toEqual(["token:hush-seo", "token:hush-seo"]);
  });

  test("CMS-CLI-002 saves an incomplete draft and lists what the contract still refuses", async () => {
    await writeFile(file("en/work-in-progress.md"), "---\nslug: \"work-in-progress\"\ntitle: \"Too short\"\n---\n# Work in progress\n");
    const pushed = await cli(["posts", "push", file("en/work-in-progress.md")]);
    expect(pushed.exitCode).toBe(0);
    expect(pushed.stdout).toContain("Created draft en/work-in-progress");
    expect(pushed.stdout).toContain("The article contract still refuses:");

    const check = await cli(["posts", "check", "work-in-progress"]);
    expect(check.exitCode).toBe(1);
    expect(check.stdout).toContain("does not meet the article contract");

    await writeFile(file("en/typo.md"), "---\ntitel: \"Typo\"\n---\nBody\n");
    const refused = await cli(["posts", "push", file("en/typo.md")]);
    expect(refused.exitCode).toBe(1);
    expect(refused.stderr).toContain("front matter titel: unknown field");
  });

  test("CMS-CLI-003 finds posts by slug and asks for the language when both have it", async () => {
    await mkdir(file("de"), { recursive: true });
    await writeFile(file("de/work-in-progress.md"), "---\nslug: \"work-in-progress\"\nlang: \"de\"\n---\n# In Arbeit\n");
    expect((await cli(["posts", "push", file("de/work-in-progress.md")])).exitCode).toBe(0);

    const ambiguous = await cli(["posts", "get", "work-in-progress"]);
    expect(ambiguous.exitCode).toBe(2);
    expect(ambiguous.stderr).toContain('"work-in-progress" exists in');
    expect((await cli(["posts", "get", "work-in-progress", "--lang", "de", "--json"])).json()).toMatchObject({ lang: "de", status: "draft" });

    const list = await cli(["posts", "list", "--lang", "en", "--status", "draft"]);
    expect(list.stdout.split("\n")[0]).toMatch(/^STATUS\s+LANG\s+SLUG\s+GOES LIVE\s+TITLE$/);
    expect(list.stdout).toContain("dictate-from-the-terminal");
    expect(list.stdout).not.toContain("In Arbeit");
    expect((await cli(["posts", "delete", "work-in-progress", "--lang", "de"])).stdout).toContain("Deleted de/work-in-progress.");
  });

  test("CMS-CLI-004 schedules and publishes only with posts:publish, and changes a live post only with --live", async () => {
    const refused = await cli(["posts", "schedule", "dictate-from-the-terminal", "--at", "2099-12-01T08:00Z"]);
    expect(refused.exitCode).toBe(1);
    expect(refused.stderr).toContain("The token lacks the posts:publish scope.");

    const owner = { token: tokens.owner };
    const scheduled = await cli(["posts", "schedule", "dictate-from-the-terminal", "--at", "2099-12-01T08:00Z"], owner);
    expect(scheduled.stdout).toBe("Scheduled /blog/dictate-from-the-terminal for 2099-12-01 08:00 UTC.\n");
    expect((await cli(["posts", "publish", "dictate-from-the-terminal"], owner)).stdout).toBe("Published /blog/dictate-from-the-terminal.\n");

    const source = await readFile(file(article), "utf8");
    await writeFile(file(article), source.replace("Only once, to download the model.", "Once, to download the model."));
    const guarded = await cli(["posts", "push", file(article)]);
    expect(guarded.exitCode).toBe(1);
    expect(guarded.stderr).toContain("is published; push --live to change the live post.");
    expect((await cli(["posts", "push", file(article), "--live"])).stdout).toContain("Updated published en/dictate-from-the-terminal");

    // A live post stays valid: an edit that breaks the contract is refused with its problems.
    await writeFile(file(article), source.replace("## Frequently asked questions", "## Questions"));
    const invalid = await cli(["posts", "push", file(article), "--live"]);
    expect(invalid.exitCode).toBe(1);
    expect(invalid.stderr).toContain("  - ");
    expect((await cli(["posts", "get", "dictate-from-the-terminal", "--json"])).json().markdown).toContain("Once, to download the model.");
  });

  test("CMS-CLI-005 pulls a post as an article file with its images that pushes back unchanged", async () => {
    const pulled = await cli(["posts", "pull", "dictate-from-the-terminal", "--out", "pulled"]);
    expect(pulled.stdout).toBe("Wrote pulled/en/dictate-from-the-terminal.md and 1 image.\n");
    const source = await readFile(join(work, "pulled/en/dictate-from-the-terminal.md"), "utf8");
    expect(source).toContain('draft: false');
    expect(source).toContain('keyword: "dictate in the terminal"');
    expect(await Bun.file(join(work, "pulled/en/media/dictate-from-the-terminal/terminal.png")).bytes())
      .toEqual(await Bun.file(file("en/media/dictate-from-the-terminal/terminal.png")).bytes());
    expect((await cli(["posts", "push", "pulled/en/dictate-from-the-terminal.md", "--live", "--json"])).json())
      .toMatchObject({ action: "unchanged", media: { uploaded: [] } });
  });

  test("CMS-CLI-006 reports refusals on stderr, or as the CMS's JSON with --json, and wrong usage with exit 2", async () => {
    const missing = await cli(["posts", "get", "no-such-post"]);
    expect([missing.exitCode, missing.stderr]).toEqual([1, 'hush-cms: No post has the slug "no-such-post".\n']);
    const forbidden = await cli(["posts", "publish", "dictate-from-the-terminal", "--json"]);
    expect(forbidden.exitCode).toBe(1);
    expect(forbidden.json()).toEqual({ error: { code: "forbidden", message: "The token lacks the posts:publish scope." } });
    expect((await cli(["posts", "schedule", "dictate-from-the-terminal", "--at", "tomorrow"])).exitCode).toBe(2);
    expect((await cli(["posts", "list", "--colour"])).exitCode).toBe(2);
    expect((await cli(["posts", "list"], { token: "hcms_unknownunknownunknownunknown" })).stderr).toContain("The token is unknown, expired or revoked.");
  });

  test("CMS-CLI-007 shows the token's name, scopes and expiry, and keeps a token in the Keychain without echoing it", async () => {
    const status = await cli(["auth", "status"]);
    expect(status.stdout).toBe(`token:hush-seo on ${url}, from the environment: posts:read, posts:write; does not expire.\n`);

    if (process.platform !== "darwin") {
      const login = await cli(["auth", "login"], { token: null, stdin: `${tokens.agent}\n` });
      expect([login.exitCode, login.stderr]).toEqual([1, "hush-cms: Only macOS has a Keychain here; set HUSH_CMS_TOKEN instead.\n"]);
      return;
    }
    // A Keychain item for this test's own origin, removed again below.
    try {
      const login = await cli(["auth", "login"], { token: null, stdin: `${tokens.agent}\n` });
      expect(login.stdout).toBe(`Saved token:hush-seo for ${url} in the Keychain (posts:read, posts:write).\n`);
      expect(login.stdout + login.stderr).not.toContain(tokens.agent);
      expect((await cli(["auth", "status"], { token: null })).stdout).toContain("from the keychain");
      expect((await cli(["posts", "get", "dictate-from-the-terminal"], { token: null })).exitCode).toBe(0);
    } finally {
      expect((await cli(["auth", "logout"], { token: null })).stdout).toBe(`Removed the token for ${url} from the Keychain.\n`);
    }
    expect((await cli(["posts", "list"], { token: null })).stderr).toContain("Run hush-cms auth login");
    expect((await cli(["auth", "login"], { token: null, stdin: "hcms_unknownunknownunknownunknown\n" })).exitCode).toBe(1);
  });
});
