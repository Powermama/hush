// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// CMS-001 to CMS-006 (docs/user-journeys/cms.md): the owner's journeys in the
// admin, on desktop, a phone and WebKit. Each test writes its own posts, so
// browsers running in parallel never share one.
import { expect, test as base, type Page } from "@playwright/test";
import { validPost } from "../fixtures";

type Post = { id: string; slug: string; status: string };

const test = base.extend<{ signedIn: Page; draft: (overrides?: Record<string, unknown>) => Promise<Post> }>({
  signedIn: async ({ page }, use) => {
    await page.goto("/__e2e/sign-in");
    await use(page);
  },
  draft: async ({ signedIn }, use, testInfo) => {
    let count = 0;
    await use(async (overrides = {}) => {
      const slug = `journey-${testInfo.project.name}-${testInfo.workerIndex}-${Date.now().toString(36)}-${count++}`;
      const response = await signedIn.request.post("/v1/posts", {
        data: validPost({ slug, keyword: slug.replaceAll("-", " "), ...overrides }),
      });
      expect(response.status()).toBe(201);
      return await response.json() as Post;
    });
  },
});

const order = ["Scheduled", "Draft", "Published"];
const statusOf = async (page: Page, id: string) => (await (await page.request.get(`/v1/posts/${id}`)).json() as Post).status;

test("CMS-001 the owner signs in with GitHub and sees every post with its status", async ({ browser, signedIn, draft }, testInfo) => {
  // A visitor without a session, in a browser of their own.
  const visitor = await browser.newContext({ ...testInfo.project.use, baseURL: "https://localhost:4310", ignoreHTTPSErrors: true });
  const anonymous = await visitor.newPage();
  await anonymous.goto("/");
  await expect(anonymous).toHaveURL(/\/sign-in$/);
  await expect(anonymous.getByRole("link", { name: "Sign in with GitHub" })).toHaveAttribute("href", "/auth/github");
  await visitor.close();

  const post = await draft();
  await signedIn.goto("/");
  await expect(signedIn.getByRole("heading", { name: "Posts", exact: true })).toBeVisible();
  const row = signedIn.getByRole("listitem").filter({ has: signedIn.locator(`a[href="/posts/${post.id}"]`) });
  await expect(row).toContainText("By Clemens Kressmann - in Dictation without the cloud");
  await expect(row).toContainText("Draft");
  await expect(signedIn.getByRole("listitem").filter({ hasText: "Published" }).first()).toBeVisible();

  // Drafts come before published posts, whichever way they are sorted.
  const statuses = async () => await signedIn.getByRole("main").getByRole("listitem").evaluateAll((rows) => rows.map((item) => /Draft|Scheduled|Published/.exec(item.textContent ?? "")?.[0]));
  expect(await statuses()).toEqual([...(await statuses())].sort((a, b) => order.indexOf(a!) - order.indexOf(b!)));
  await signedIn.getByRole("combobox", { name: "Sort: Newest first" }).click();
  await signedIn.getByRole("option", { name: "Oldest first" }).click();
  await expect(signedIn.getByRole("combobox", { name: "Sort: Oldest first" })).toBeVisible();

  // The views live in the sidebar, which is a sheet behind the bottom bar on a phone.
  const published = signedIn.getByRole("link", { name: "Published", exact: true });
  const sidebar = signedIn.getByRole("button", { name: "Toggle Sidebar" });
  const sheet = !await published.isVisible();
  if (sheet) await sidebar.click();
  await published.click();
  await expect(signedIn).toHaveURL(/status=published/);
  await expect(signedIn.getByRole("heading", { name: "Published", exact: true })).toBeVisible();
  await expect(signedIn.locator(`a[href="/posts/${post.id}"]`)).toHaveCount(0);
  // Choosing a view closes the sheet.
  if (sheet) {
    await expect(published).toBeHidden();
    await sidebar.click();
  }
  await expect(published).toHaveAttribute("aria-current", "page");
});

test("CMS-002 writing updates the preview from the real renderer and lists what the contract refuses", async ({ signedIn, draft }) => {
  const post = await draft();
  await signedIn.goto(`/posts/${post.id}`);
  const preview = signedIn.frameLocator("iframe[title=Preview]");
  await expect(preview.getByRole("heading", { level: 1 })).toHaveText("How to dictate on a Mac without the cloud");
  await expect(signedIn.locator("iframe[title=Preview]")).toHaveAttribute("sandbox", "");

  const editor = signedIn.getByRole("textbox", { name: "Article in Markdown" });
  await editor.click();
  await signedIn.keyboard.press("ControlOrMeta+End");
  await signedIn.keyboard.type("\n\nA sentence written in the admin.");
  await expect(preview.getByText("A sentence written in the admin.")).toBeVisible();
  await expect(signedIn.getByText("Unsaved changes")).toBeVisible();

  await signedIn.keyboard.type("\n\n[a dead link](/blog/does-not-exist)");
  await expect(signedIn.getByRole("alert")).toContainText("does not resolve");

  await signedIn.keyboard.press("ControlOrMeta+z");
  await signedIn.keyboard.press("ControlOrMeta+s");
  await expect(signedIn.getByRole("banner").getByText("Saved", { exact: true })).toBeVisible();
});

test("CMS-003 publishing now takes a valid draft live", async ({ signedIn, draft }) => {
  const post = await draft();
  await signedIn.goto(`/posts/${post.id}`);
  await signedIn.getByRole("button", { name: "Publish" }).click();
  await signedIn.getByRole("button", { name: "Publish now" }).click();
  await expect(signedIn.getByText(/Published\. behu\.sh updates/)).toBeVisible();
  expect(await statusOf(signedIn, post.id)).toBe("published");
  await expect(signedIn.getByRole("button", { name: "Unpublish" })).toBeVisible();
});

test("CMS-004 scheduling sets a future time and the post waits for it", async ({ signedIn, draft }) => {
  const post = await draft();
  await signedIn.goto(`/posts/${post.id}`);
  await signedIn.getByRole("button", { name: "Publish" }).click();
  await signedIn.getByLabel("Or schedule it").fill("2031-05-04T09:30");
  await signedIn.getByRole("button", { name: "Schedule", exact: true }).click();
  await expect(signedIn.getByText("Scheduled for 4 May 2031")).toBeVisible();
  expect(await statusOf(signedIn, post.id)).toBe("scheduled");
});

test("CMS-005 unpublishing asks first, then returns the post to drafts", async ({ signedIn, draft }) => {
  const post = await draft();
  // A bodyless POST counts as a form for the CSRF check: it must name its origin, as browsers do.
  expect((await signedIn.request.post(`/v1/posts/${post.id}/publish`, { headers: { origin: "https://localhost:4310" } })).status()).toBe(200);
  await signedIn.goto(`/posts/${post.id}`);
  await signedIn.getByRole("button", { name: "Unpublish" }).click();
  await expect(signedIn.getByRole("alertdialog")).toContainText("Take this post offline?");
  await signedIn.getByRole("button", { name: "Keep it" }).click();
  expect(await statusOf(signedIn, post.id)).toBe("published");
  await signedIn.getByRole("button", { name: "Unpublish" }).click();
  await signedIn.getByRole("alertdialog").getByRole("button", { name: "Unpublish" }).click();
  await expect(signedIn.getByText(/Unpublished\./)).toBeVisible();
  expect(await statusOf(signedIn, post.id)).toBe("draft");
});

test("CMS-006 an earlier revision can be restored from the post's history", async ({ signedIn, draft }) => {
  const post = await draft();
  const changed = validPost().markdown.replace("The speech model runs on your Mac.", "A later wording of the answer.");
  expect((await signedIn.request.patch(`/v1/posts/${post.id}`, { data: { markdown: changed } })).status()).toBe(200);
  await signedIn.goto(`/posts/${post.id}`);
  await expect(signedIn.getByRole("textbox", { name: "Article in Markdown" })).toContainText("A later wording of the answer.");
  await signedIn.getByRole("button", { name: "Post settings" }).click();
  await signedIn.getByRole("button", { name: "Restore" }).first().click();
  await expect(signedIn.getByText("Revision restored")).toBeVisible();
  await signedIn.keyboard.press("Escape");
  await expect(signedIn.getByRole("textbox", { name: "Article in Markdown" })).toContainText("The speech model runs on your Mac.");
});

test("the admin runs under its Content Security Policy without violations", async ({ signedIn, draft }) => {
  const violations: string[] = [];
  signedIn.on("console", (message) => { if (/Content.Security.Policy|Refused to/i.test(message.text())) violations.push(message.text()); });
  const post = await draft();
  const response = await signedIn.goto(`/posts/${post.id}`);
  expect(response!.headers()["content-security-policy"]).toContain("script-src 'self'");
  await expect(signedIn.frameLocator("iframe[title=Preview]").getByRole("heading", { level: 1 })).toBeVisible();
  expect(violations).toEqual([]);
});

test("the admin never scrolls sideways, also on a phone", async ({ signedIn, draft }) => {
  const post = await draft();
  for (const path of ["/", `/posts/${post.id}`]) {
    await signedIn.goto(path);
    await signedIn.waitForLoadState("networkidle");
    expect(await signedIn.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  }
});
