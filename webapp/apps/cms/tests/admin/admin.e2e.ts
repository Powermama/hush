// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// CMS-001 to CMS-008 (docs/user-journeys/cms.md): the owner's journeys in the
// admin, on desktop, a phone and WebKit. Each test writes its own posts, so
// browsers running in parallel never share one.
import { expect, test as base, type Page } from "@playwright/test";
import sharp from "sharp";
import { validPost } from "../fixtures";

type Post = { id: string; slug: string; status: string };

const test = base.extend<{ signedIn: Page; draft: (overrides?: Record<string, unknown>) => Promise<Post> }>({
  signedIn: async ({ page }, use) => {
    await page.goto("/__e2e/sign-in");
    // WebKit can report the sign-in loaded before its redirect to the posts list has; a test's own goto would then be cut off.
    await expect(page.getByRole("heading", { name: "Posts", exact: true })).toBeVisible();
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

/** The article's editable body, and the way to its end. */
const article = (page: Page) => page.getByRole("textbox", { name: "Article" });
async function endOfArticle(page: Page) {
  await article(page).locator("p").last().click();
  await page.keyboard.press("End");
}
const status = (page: Page) => page.getByRole("banner").locator("[aria-live]");
/** While the writer types, the editor's header fades out; moving the pointer brings it back, as in Ghost. */
async function showChrome(page: Page) {
  await page.mouse.move(10, 300);
  await page.mouse.move(60, 340);
}

test("CMS-002 writing in the block editor saves the draft by itself, and the preview lists what the contract refuses", async ({ signedIn, draft }) => {
  const post = await draft();
  await signedIn.goto(`/posts/${post.id}`);
  await expect(signedIn.getByRole("textbox", { name: "Post title" })).toHaveValue("How to dictate on a Mac without the cloud");
  await expect(article(signedIn).getByRole("heading", { name: "Frequently asked questions" })).toBeVisible();
  await expect(status(signedIn)).toHaveText("Draft - Saved");

  await endOfArticle(signedIn);
  await signedIn.keyboard.press("Enter");
  await signedIn.keyboard.type("A sentence written in the admin.");
  await expect(status(signedIn)).toHaveText("Draft");
  // Saved three seconds after the writer stops, with nothing pressed.
  await expect(status(signedIn)).toHaveText("Draft - Saved", { timeout: 10_000 });
  const saved = await (await signedIn.request.get(`/v1/posts/${post.id}`)).json() as { markdown: string };
  expect(saved.markdown).toBe(`${validPost().markdown}\n\nA sentence written in the admin.\n`);

  await showChrome(signedIn);
  await signedIn.getByRole("button", { name: "Preview" }).click();
  const preview = signedIn.frameLocator("iframe[title=Preview]");
  await expect(preview.getByText("A sentence written in the admin.")).toBeVisible();
  await expect(signedIn.locator("iframe[title=Preview]")).toHaveAttribute("sandbox", "allow-same-origin");

  // The preview covers the screen, as Ghost's does; Escape returns to writing.
  await signedIn.keyboard.press("Escape");
  await expect(signedIn.locator("iframe[title=Preview]")).toHaveCount(0);

  // A Markdown link typed in the editor becomes a link; one to a missing page is refused.
  await endOfArticle(signedIn);
  await signedIn.keyboard.type(" See [a dead link](/blog/does-not-exist) ");
  await expect(article(signedIn).getByRole("link", { name: "a dead link" })).toBeVisible();
  await signedIn.keyboard.press("ControlOrMeta+p");
  await expect(signedIn.getByRole("dialog", { name: "Preview" }).getByRole("alert")).toContainText("does not resolve");
  await signedIn.getByRole("button", { name: "Close" }).click();
  await signedIn.keyboard.press("ControlOrMeta+s");
  await expect(status(signedIn)).toHaveText("Draft - Saved");
});

test("CMS-002 the editor and the preview show the article's images, as the site will", async ({ signedIn }, testInfo) => {
  const slug = `previewed-picture-${testInfo.project.name}-${Date.now().toString(36)}`;
  const base = validPost({ slug, keyword: slug.replaceAll("-", " ") });
  const markdown = base.markdown.replace("## How does it work?", `![The dictation settings on a Mac](media/${slug}/settings.png "Where it lives")\n\n## How does it work?`);
  const post = await (await signedIn.request.post("/v1/posts", { data: { ...base, markdown } })).json() as Post;
  const png = await sharp({ create: { width: 800, height: 500, channels: 3, background: "#7667d7" } }).png().toBuffer();
  expect((await signedIn.request.put(`/v1/posts/${post.id}/media/settings.png`, { data: png, headers: { "content-type": "image/png" } })).status()).toBe(200);
  await signedIn.goto(`/posts/${post.id}`);
  // The editor's card shows the stored picture too.
  const card = article(signedIn).locator("figure");
  await expect(card.getByRole("img", { name: "The dictation settings on a Mac" })).toBeVisible();
  await expect(card).not.toContainText("not uploaded yet");
  await signedIn.getByRole("button", { name: "Preview" }).click();
  const image = signedIn.frameLocator("iframe[title=Preview]").getByRole("img", { name: "The dictation settings on a Mac" });
  await expect(image).toBeVisible();
  await expect.poll(() => image.evaluate((element: HTMLImageElement) => element.complete && element.naturalWidth)).toBeGreaterThan(0);
});

test("CMS-007 a new post starts with its title, saves itself and gets its address from it", async ({ signedIn }, testInfo) => {
  const title = `A post written in the browser ${testInfo.project.name} ${Date.now().toString(36)}`;
  await signedIn.goto("/posts/new");
  const titleField = signedIn.getByRole("textbox", { name: "Post title" });
  await expect(titleField).toBeFocused();
  await signedIn.keyboard.type(title);
  await signedIn.keyboard.press("Enter");
  await signedIn.keyboard.type("What this post is about.");
  await signedIn.keyboard.press("Enter");
  await signedIn.keyboard.type("## A section");
  await signedIn.keyboard.press("Enter");
  await signedIn.keyboard.type("Some **bold** words.");
  // The address moves to the saved post while the same editor stays open.
  await expect(signedIn).toHaveURL(/\/posts\/[0-9a-f-]{36}$/, { timeout: 10_000 });
  await expect(status(signedIn)).toHaveText("Draft - Saved", { timeout: 10_000 });
  const id = signedIn.url().split("/").at(-1);
  const saved = await (await signedIn.request.get(`/v1/posts/${id}`)).json() as Record<string, string>;
  expect(saved.slug).toBe(title.toLowerCase().replaceAll(" ", "-"));
  expect(saved.description).toBe("What this post is about.");
  expect(saved.markdown).toBe(`# ${title}\n\n## A section\n\nSome **bold** words.\n`);

  // "/" offers the blocks of an article.
  await signedIn.keyboard.press("Enter");
  await signedIn.keyboard.type("/div");
  await expect(signedIn.getByRole("option", { name: /Divider/ })).toBeVisible();
  await signedIn.keyboard.press("Enter");
  await expect(article(signedIn).locator("hr")).toHaveCount(1);
  await expect(article(signedIn)).not.toContainText("/div");
});

test("CMS-008 an image goes into a new post through its card and follows the post's address", async ({ signedIn }, testInfo) => {
  const png = await sharp({ create: { width: 800, height: 500, channels: 3, background: "#7667d7" } }).png().toBuffer();
  await signedIn.goto("/posts/new");
  await article(signedIn).click();
  await signedIn.keyboard.type("/image");
  await signedIn.keyboard.press("Enter");
  const card = article(signedIn).locator("figure");
  await expect(card).toContainText("Click to select an image");
  // Choosing the picture saves the new post first: its images live under its address.
  await card.locator("input[type=file]").setInputFiles({ name: "Dictation Settings.png", mimeType: "image/png", buffer: png });
  await expect(card.locator("img")).toBeVisible({ timeout: 10_000 });
  await expect(signedIn).toHaveURL(/\/posts\/[0-9a-f-]{36}$/);
  await card.getByLabel("Caption").fill("Where the setting lives");
  await card.getByRole("button", { name: "Alt" }).click();
  await card.getByLabel("Alt text").fill("The dictation settings on a Mac");

  // The post is named after the title it gets; the picture moves with it.
  const title = `A post with a picture ${testInfo.project.name} ${Date.now().toString(36)}`;
  const slug = title.toLowerCase().replaceAll(" ", "-");
  await signedIn.getByRole("textbox", { name: "Post title" }).fill(title);
  const id = signedIn.url().split("/").at(-1);
  await expect.poll(async () => (await (await signedIn.request.get(`/v1/posts/${id}`)).json() as { markdown: string }).markdown, { timeout: 15_000 })
    .toBe(`# ${title}\n\n![The dictation settings on a Mac](media/${slug}/dictation-settings.png "Where the setting lives")\n`);
  await expect(card.locator("img")).toBeVisible();

  // With its metadata complete, the article contract finds the image where the post says it is.
  const { markdown: _markdown, slug: _slug, ...metadata } = validPost({ keyword: slug.replaceAll("-", " ") });
  const preview = await (await signedIn.request.post(`/v1/posts/${id}/preview`, { data: metadata })).json() as { problems: string[] };
  expect(preview.problems).toEqual(['missing the "## Frequently asked questions" section']);
});

test("CMS-003 publishing now takes a valid draft live", async ({ signedIn, draft }) => {
  const post = await draft();
  await signedIn.goto(`/posts/${post.id}`);
  await signedIn.getByRole("button", { name: "Publish", exact: true }).click();
  await signedIn.getByRole("button", { name: "Publish now" }).click();
  await expect(signedIn.getByText("Post published")).toBeVisible();
  expect(await statusOf(signedIn, post.id)).toBe("published");
  await expect(status(signedIn)).toHaveText("Published");
  await expect(signedIn.getByRole("button", { name: "Unpublish" })).toBeVisible();
});

test("CMS-004 scheduling sets a future time and the post waits for it", async ({ signedIn, draft }) => {
  const post = await draft();
  await signedIn.goto(`/posts/${post.id}`);
  await signedIn.getByRole("button", { name: "Publish", exact: true }).click();
  await signedIn.getByLabel("Or schedule it").fill("2031-05-04T09:30");
  await signedIn.getByRole("button", { name: "Schedule", exact: true }).click();
  await expect(signedIn.getByText("Post scheduled")).toBeVisible();
  await expect(status(signedIn)).toHaveText("Scheduled");
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
  await expect(signedIn.getByText("Post reverted to a draft.")).toBeVisible();
  expect(await statusOf(signedIn, post.id)).toBe("draft");
});

test("CMS-006 an earlier revision can be restored from the post's history", async ({ signedIn, draft }) => {
  const post = await draft();
  const changed = validPost().markdown.replace("The speech model runs on your Mac.", "A later wording of the answer.");
  expect((await signedIn.request.patch(`/v1/posts/${post.id}`, { data: { markdown: changed } })).status()).toBe(200);
  await signedIn.goto(`/posts/${post.id}`);
  await expect(article(signedIn)).toContainText("A later wording of the answer.");
  await signedIn.getByRole("button", { name: "Settings" }).click();
  await signedIn.getByRole("button", { name: "Restore" }).first().click();
  await expect(signedIn.getByText("Revision restored")).toBeVisible();
  await signedIn.keyboard.press("Escape");
  await expect(article(signedIn)).toContainText("The speech model runs on your Mac.");
});

test("the admin runs under its Content Security Policy without violations", async ({ signedIn, draft }) => {
  const violations: string[] = [];
  signedIn.on("console", (message) => { if (/Content.Security.Policy|Refused to/i.test(message.text())) violations.push(message.text()); });
  const post = await draft();
  const response = await signedIn.goto(`/posts/${post.id}`);
  expect(response!.headers()["content-security-policy"]).toContain("script-src 'self'");
  await expect(article(signedIn)).toBeVisible();
  await signedIn.getByRole("button", { name: "Preview" }).click();
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
