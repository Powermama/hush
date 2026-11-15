// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// hush-cms: the blog CMS for agents and scripts. Every command is one or a few
// calls of the generated client; the CMS decides what is allowed (token scopes,
// the owner's approval, the article contract), the CLI only reports it. Exit
// codes: 0 done, 1 refused or failed, 2 wrong usage.
import { formatArticle, readDraftContent, type FrontMatter } from "@hush/article/file";
import { blogPath, type BlogLanguage } from "@hush/article/taxonomy";
import { createHash } from "node:crypto";
import { mkdir, readdir } from "node:fs/promises";
import { hostname } from "node:os";
import { basename, dirname, extname, join } from "node:path";
import { parseArgs } from "node:util";
import {
  createDraft, deletePost, getCaller, getMediaOriginal, getPost, listMedia, listPosts, listRevisions, pollDeviceSignIn, previewPost, publishPost,
  restoreRevision, revokeCaller, schedulePost, startDeviceSignIn, unpublishPost, updatePost, uploadMedia,
  type CreateDraftBody, type ListPostsLang, type ListPostsStatus, type Post,
} from "./api/cms.generated";
import { connect } from "./api/fetcher";
import { CredentialError, deleteToken, promptToken, readToken, saveToken, storedToken } from "./credentials";

export const defaultUrl = "https://cms.behu.sh";

const usage = `hush-cms: the hush blog CMS from the command line

Usage: hush-cms <command> [options]

Posts
  posts list [--lang en|de] [--status draft|scheduled|published]
  posts get <post>                   Fields, status, dates and the owner's approval
  posts push <file.md>               Saves an article file as a draft, or updates the draft with
                                     its language and slug; uploads the images in media/<slug>/
                                     beside it
  posts pull <post> [--out <dir>]    Writes <dir>/<lang>/<slug>.md and its images (default dir: .)
  posts check <post>                 What the article contract refuses; exit 1 if anything
  posts schedule <post> --at <time>  Goes live at an ISO 8601 time, such as 2026-12-01T08:00Z
  posts publish <post>
  posts unpublish <post>             Back to draft (the owner only)
  posts delete <post>                Drafts only
  posts revisions <post>
  posts restore <post> <revision-id>

Access
  auth login [--no-browser]          Signs in through the browser, as gh auth login: approve the
                                     code shown here at cms.behu.sh/device; the token goes to the
                                     macOS Keychain
  auth login --with-token            Reads a token from stdin instead, for scripts
  auth status                        The token's name, scopes and expiry
  auth logout                        Revokes the stored token and removes it from the Keychain

<post> is a post's id or its slug; add --lang when both languages use the slug.

A token is an agent's: it schedules or publishes a post only once the owner has
approved it as it is now, in the admin, and it changes drafts only.

Options
  --json                             Prints the CMS's JSON answer, errors included
  --url <url>                        The CMS (default: HUSH_CMS_URL, else ${defaultUrl})
  -h, --help

HUSH_CMS_TOKEN, when set, is used instead of the stored token.
`;

class Failure extends Error {
  constructor(message: string, readonly problems: string[] = [], readonly exitCode = 1, readonly body?: unknown) {
    super(message);
  }
}
const usageError = (message: string) => new Failure(`${message}\nRun hush-cms --help for the commands.`, [], 2);

type Answer = { status: number; data: unknown };
type Success<R extends Answer> = Extract<R, { status: 200 | 201 | 204 }>["data"];

/** The answer's data when the CMS accepted the call, else a Failure with its message and problems. */
function ok<R extends Answer>(answer: R): Success<R> {
  if (answer.status >= 200 && answer.status < 300) return answer.data as Success<R>;
  const error = (answer.data as { error?: { code?: string; message?: string; problems?: string[] } } | undefined)?.error;
  if (error?.message) throw new Failure(error.message, error.problems ?? [], 1, answer.data);
  throw new Failure(`The CMS answered ${answer.status}.`);
}

const imageTypes: Record<string, string> = { ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp" };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const day = (iso: string) => iso.slice(0, 10);
const when = (iso: string | null) => iso ? `${iso.slice(0, 16).replace("T", " ")} UTC` : "";
const address = (post: Post) => blogPath(post.lang as BlogLanguage, post.slug);
const languages = ["en", "de"] as const;
const statuses = ["draft", "scheduled", "published"] as const;

function table(rows: string[][]) {
  const widths = rows[0]!.map((_, column) => Math.max(...rows.map((row) => row[column]!.length)));
  return rows.map((row) => row.map((cell, column) => column === row.length - 1 ? cell : cell.padEnd(widths[column]!)).join("  ")).join("\n");
}

/** A post by id, or by slug within --lang (or the only language that has it). */
async function findPost(reference: string | undefined, lang: string | undefined): Promise<Post> {
  if (!reference) throw usageError("Name a post by its id or slug.");
  if (uuid.test(reference)) return ok(await getPost(reference));
  const { posts } = ok(await listPosts(lang ? { lang: lang as ListPostsLang } : {}));
  const matches = posts.filter((post) => post.slug === reference);
  if (!matches.length) throw new Failure(`No post has the slug "${reference}"${lang ? ` in ${lang}` : ""}.`);
  if (matches.length > 1) throw usageError(`"${reference}" exists in ${matches.map((post) => post.lang).join(" and ")}; add --lang.`);
  return matches[0]!;
}

/** Uploads the images in media/<slug>/ beside the article that the CMS does not already hold, byte for byte. */
async function pushMedia(post: Post, file: string) {
  const directory = join(dirname(file), "media", post.slug);
  const names = (await readdir(directory).catch(() => [] as string[])).filter((name) => imageTypes[extname(name).toLowerCase()]).sort();
  if (!names.length) return { uploaded: [] as string[], unchanged: [] as string[] };
  const { media } = ok(await listMedia(post.id));
  const uploaded: string[] = [];
  const unchanged: string[] = [];
  for (const name of names) {
    const bytes = new Uint8Array(await Bun.file(join(directory, name)).arrayBuffer());
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    if (media.some((stored) => stored.name === name && stored.sha256 === sha256)) { unchanged.push(name); continue; }
    ok(await uploadMedia(post.id, name, new Blob([bytes]), { headers: { "content-type": imageTypes[extname(name).toLowerCase()]! } }));
    uploaded.push(name);
  }
  return { uploaded, unchanged };
}

async function push(file: string | undefined) {
  if (!file) throw usageError("Name the article file to push.");
  const source = Bun.file(file);
  if (!await source.exists()) throw new Failure(`${file} does not exist.`);
  const { content, problems: fileProblems } = readDraftContent(await source.text());
  if (!content) throw new Failure(`${file} is not an article file.`, fileProblems);
  const fields = content as CreateDraftBody;
  const lang = fields.lang ?? "en";
  const existing = typeof fields.slug === "string"
    ? ok(await listPosts({ lang: lang as ListPostsLang })).posts.find((post) => post.slug === fields.slug)
    : undefined;
  let post = existing ?? ok(await createDraft(fields));
  // Images first: the CMS checks the post with its images, and a live one refuses an agent's change before anything is written.
  const media = await pushMedia(post, file);
  const changed = existing && (Object.keys(fields) as Array<keyof CreateDraftBody>)
    .some((key) => JSON.stringify(fields[key]) !== JSON.stringify(existing[key]));
  if (changed) post = ok(await updatePost(post.id, fields));
  const { problems } = ok(await previewPost(post.id, {}));
  return { action: existing ? (changed ? "updated" : "unchanged") : "created", post, media, problems };
}

async function pull(post: Post, outDir: string) {
  const published = post.publishedAt ? day(post.publishedAt) : day(new Date().toISOString());
  const front: FrontMatter = {
    title: post.title, description: post.description, slug: post.slug, lang: post.lang, keyword: post.keyword,
    secondaryKeywords: post.secondaryKeywords, type: post.type, cluster: post.cluster, author: post.author,
    published, updated: [published, day(post.updatedAt)].sort().at(-1)!,
    imageAlt: post.imageAlt, schema: ["BlogPosting"], draft: post.status !== "published",
  };
  const file = join(outDir, post.lang, `${post.slug}.md`);
  await Bun.write(file, formatArticle({ front, body: post.markdown }));
  const { media } = ok(await listMedia(post.id));
  for (const image of media) {
    await mkdir(join(outDir, post.lang, "media", post.slug), { recursive: true });
    await Bun.write(join(outDir, post.lang, "media", post.slug, basename(image.name)), ok(await getMediaOriginal(image.sha256)) as unknown as Uint8Array);
  }
  return { file, images: media.map((image) => image.name) };
}

type Output = { json: unknown; text: string; exitCode?: number };

async function postsCommand(action: string | undefined, args: string[], values: Record<string, string | boolean | undefined>): Promise<Output> {
  const lang = values.lang as string | undefined;
  if (lang && !languages.includes(lang as never)) throw usageError(`--lang is en or de, not ${lang}.`);
  switch (action) {
    case "list": {
      const status = values.status as string | undefined;
      if (status && !statuses.includes(status as never)) throw usageError(`--status is draft, scheduled or published, not ${status}.`);
      const answer = ok(await listPosts({ lang: lang as ListPostsLang | undefined, status: status as ListPostsStatus | undefined }));
      const rows = answer.posts.map((post) => [post.status, post.lang, post.slug, when(post.publishedAt) || "-", post.title || "(untitled)"]);
      return { json: answer, text: rows.length ? table([["STATUS", "LANG", "SLUG", "GOES LIVE", "TITLE"], ...rows]) : "No posts." };
    }
    case "get": {
      const post = await findPost(args[0], lang);
      const lines = [
        ["id", post.id], ["status", post.status], ["address", address(post)], ["goes live", when(post.publishedAt) || "-"],
        ["title", post.title], ["description", post.description], ["keyword", post.keyword],
        ["secondary keywords", post.secondaryKeywords.join(", ") || "-"], ["type", post.type], ["cluster", post.cluster],
        ["author", post.author], ["image alt", post.imageAlt], ["updated", when(post.updatedAt)],
        ["approval", !post.approval ? "not approved by the owner"
          : `${post.approval.current ? "approved" : "lapsed: changed since it was approved"} by ${post.approval.approvedBy}, ${when(post.approval.approvedAt)}`],
      ];
      return { json: post, text: table(lines) };
    }
    case "push": {
      const result = await push(args[0]);
      const { post, media, problems } = result;
      const lines = [`${result.action === "created" ? "Created" : result.action === "updated" ? "Updated" : "No change to"} ${post.status} ${post.lang}/${post.slug} (${post.id}).`];
      if (media.uploaded.length) lines.push(`Uploaded ${media.uploaded.join(", ")}.`);
      lines.push(problems.length ? `The article contract still refuses:\n${problems.map((problem) => `  - ${problem}`).join("\n")}` : "It meets the article contract.");
      return { json: result, text: lines.join("\n") };
    }
    case "pull": {
      const post = await findPost(args[0], lang);
      const result = await pull(post, (values.out as string | undefined) ?? ".");
      return { json: result, text: `Wrote ${result.file}${result.images.length ? ` and ${result.images.length} image${result.images.length === 1 ? "" : "s"}` : ""}.` };
    }
    case "check": {
      const post = await findPost(args[0], lang);
      const preview = ok(await previewPost(post.id, {}));
      const text = preview.problems.length
        ? `${post.lang}/${post.slug} does not meet the article contract:\n${preview.problems.map((problem) => `  - ${problem}`).join("\n")}`
        : `${post.lang}/${post.slug} meets the article contract.`;
      return { json: { problems: preview.problems }, text, exitCode: preview.problems.length ? 1 : 0 };
    }
    case "schedule": {
      const at = values.at as string | undefined;
      const time = at ? new Date(at) : undefined;
      if (!at || !time || Number.isNaN(time.getTime()) || !/^\d{4}-\d{2}-\d{2}T/.test(at)) throw usageError("Give the time with --at, in ISO 8601 such as 2026-12-01T08:00Z.");
      const post = await findPost(args[0], lang);
      const scheduled = ok(await schedulePost(post.id, { publishedAt: time.toISOString() }));
      return { json: scheduled, text: `Scheduled ${address(scheduled)} for ${when(scheduled.publishedAt)}.` };
    }
    case "publish": {
      const published = ok(await publishPost((await findPost(args[0], lang)).id));
      return { json: published, text: `Published ${address(published)}.` };
    }
    case "unpublish": {
      const draft = ok(await unpublishPost((await findPost(args[0], lang)).id));
      return { json: draft, text: `${draft.lang}/${draft.slug} is a draft again.` };
    }
    case "delete": {
      const post = await findPost(args[0], lang);
      ok(await deletePost(post.id));
      return { json: { deleted: post.id }, text: `Deleted ${post.lang}/${post.slug}.` };
    }
    case "revisions": {
      const answer = ok(await listRevisions((await findPost(args[0], lang)).id));
      const rows = answer.revisions.map((revision) => [revision.id, when(revision.createdAt), revision.status, `${revision.actor}${revision.autosave ? " (autosave)" : ""}`]);
      return { json: answer, text: table([["REVISION", "SAVED", "STATUS", "BY"], ...rows]) };
    }
    case "restore": {
      if (!args[1]) throw usageError("Name the revision to restore.");
      const post = ok(await restoreRevision((await findPost(args[0], lang)).id, args[1]));
      return { json: post, text: `Restored revision ${args[1]} of ${post.lang}/${post.slug}.` };
    }
    default:
      throw usageError(action ? `Unknown command "posts ${action}".` : "posts needs a command.");
  }
}

/**
 * The OAuth 2.0 Device Authorization Grant (RFC 8628), as `gh auth login`:
 * show a one-time code, open the page that approves it, poll until the owner
 * decides. Returns the new token.
 */
async function deviceSignIn(origin: string, openBrowser: boolean) {
  connect(origin);
  const start = ok(await startDeviceSignIn({ clientName: `hush-cms on ${hostname().replace(/\.local$/, "")}` }));
  process.stderr.write(`! First copy your one-time code: ${start.userCode}\nOpen ${start.verificationUriComplete} to authorize hush-cms.\n`);
  if (openBrowser) Bun.spawn(["open", start.verificationUriComplete], { stdout: "ignore", stderr: "ignore" });
  let interval = start.interval;
  const deadline = Date.now() + start.expiresIn * 1000;
  while (Date.now() < deadline) {
    await Bun.sleep(interval * 1000);
    const answer = await pollDeviceSignIn({ deviceCode: start.deviceCode });
    if (answer.status === 200) return answer.data.token;
    const error = (answer.data as { error?: { code?: string; message?: string } }).error;
    if (error?.code === "authorization_pending") continue;
    if (error?.code === "slow_down") { interval += 5; continue; }
    throw new Failure(error?.message ?? `The CMS answered ${answer.status}.`);
  }
  throw new Failure("The sign-in expired. Run hush-cms auth login again.");
}

/** Revokes a token on the CMS, best effort: an expired or revoked one is already harmless. */
async function revoke(origin: string, token: string) {
  connect(origin, token);
  await revokeCaller().catch(() => undefined);
}

async function authCommand(action: string | undefined, origin: string, values: Record<string, string | boolean | undefined>): Promise<Output> {
  switch (action) {
    case "login": {
      // Fail before the browser opens, not after the owner approved.
      if (process.platform !== "darwin") throw new CredentialError("Only macOS has a Keychain here; set HUSH_CMS_TOKEN instead.");
      const token = values["with-token"] ? await promptToken() : await deviceSignIn(origin, values["no-browser"] !== true && !process.env.CI);
      connect(origin, token);
      const caller = ok(await getCaller());
      const previous = storedToken(origin);
      await saveToken(origin, token);
      // One stored token per CMS: the one it replaces stops working.
      if (previous && previous !== token) await revoke(origin, previous);
      return { json: caller, text: `Saved ${caller.actor} for ${origin} in the Keychain (${caller.scopes.join(", ")}).` };
    }
    case "status": {
      const stored = await readToken(origin);
      if (!stored) throw new Failure(`No token for ${origin}. Run hush-cms auth login, or set HUSH_CMS_TOKEN.`);
      connect(origin, stored.token);
      const caller = ok(await getCaller());
      const expiry = caller.expiresAt ? `expires ${when(caller.expiresAt)}` : "does not expire";
      return { json: { ...caller, origin, source: stored.source }, text: `${caller.actor} on ${origin}, from the ${stored.source}: ${caller.scopes.join(", ")}; ${expiry}.` };
    }
    case "logout": {
      const stored = storedToken(origin);
      if (stored) await revoke(origin, stored);
      const removed = deleteToken(origin);
      return { json: { removed }, text: removed ? `Revoked the token for ${origin} and removed it from the Keychain.` : `No stored token for ${origin}.` };
    }
    default:
      throw usageError(action ? `Unknown command "auth ${action}".` : "auth needs a command: login, status or logout.");
  }
}

/** Runs one command line; returns the exit code. */
export async function run(argv: string[]): Promise<number> {
  let json = argv.includes("--json");
  try {
    const { values, positionals } = (() => {
      try {
        return parseArgs({
          args: argv, allowPositionals: true, strict: true,
          options: {
            json: { type: "boolean" }, url: { type: "string" }, help: { type: "boolean", short: "h" },
            lang: { type: "string" }, status: { type: "string" }, at: { type: "string" }, out: { type: "string" },
            "with-token": { type: "boolean" }, "no-browser": { type: "boolean" },
          },
        });
      } catch (error) {
        throw usageError((error as Error).message);
      }
    })();
    json = values.json === true;
    const [group, action, ...args] = positionals;
    if (values.help || !group) {
      process.stdout.write(usage);
      return values.help ? 0 : 2;
    }
    const origin = new URL(values.url ?? process.env.HUSH_CMS_URL ?? defaultUrl).origin;
    let output: Output;
    if (group === "auth") {
      output = await authCommand(action, origin, values);
    } else if (group === "posts") {
      const stored = await readToken(origin);
      if (!stored) throw new Failure(`No token for ${origin}. Run hush-cms auth login, or set HUSH_CMS_TOKEN.`);
      connect(origin, stored.token);
      output = await postsCommand(action, args, values);
    } else {
      throw usageError(`Unknown command "${group}".`);
    }
    process.stdout.write(`${json ? JSON.stringify(output.json, null, 2) : output.text}\n`);
    return output.exitCode ?? 0;
  } catch (error) {
    const failure = error instanceof Failure ? error
      : error instanceof CredentialError ? new Failure(error.message)
      : error instanceof TypeError && /fetch|connect/i.test(error.message) ? new Failure(`Cannot reach the CMS: ${error.message}`)
      : new Failure(String((error as Error)?.message ?? error));
    if (json) {
      process.stdout.write(`${JSON.stringify(failure.body ?? { error: { message: failure.message, problems: failure.problems.length ? failure.problems : undefined } }, null, 2)}\n`);
    } else {
      process.stderr.write(`hush-cms: ${failure.message}\n${failure.problems.map((problem) => `  - ${problem}\n`).join("")}`);
    }
    return failure.exitCode;
  }
}
