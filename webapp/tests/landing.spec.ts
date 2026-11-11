import { expect, test } from "@playwright/test";

test("renders the visual landing page with a clear download", async ({ page, isMobile }, testInfo) => {
  const errors: string[] = [];
  page.on("pageerror", error => errors.push(error.message));
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1, name: "The voice layer for your Mac." })).toBeVisible();
  await expect(page.getByRole("navigation", { name: "Primary navigation" })).toBeVisible();
  const download = page.locator(".landing-download").first();
  if (isMobile) {
    await expect(download).toHaveText("Get hush for Mac");
    await expect(download).toHaveAttribute("aria-haspopup", "dialog");
  } else {
    await expect(download).toHaveAttribute("href", "https://updates.behu.sh/downloads/hush-0.1.0-alpha.5-build.14.dmg");
    await expect(page.getByRole("link", { name: "Download", exact: true })).toHaveAttribute("href", await download.getAttribute("href") as string);
  }
  await expect(page.getByRole("img", { name: /hush connects your voice/ })).toBeVisible();
  await expect(page.getByText("Free alpha for Apple silicon Macs")).toBeVisible();
  await expect(page.getByRole("tablist")).toHaveCount(0);
  await expect(page.getByRole("button", { name: /replay|skip intro/i })).toHaveCount(0);
  await expect(page.getByText("All on your Mac", { exact: true })).toHaveCount(0);
  await expect(page.getByRole("link", { name: "Legal notice" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "A few things to know." })).toBeVisible();
  await expect(page.locator(".hush-landing")).not.toHaveAttribute("data-opening", /pending|playing/, { timeout: 8000 });
  await expect(download).toHaveCSS("background-color", "rgb(36, 39, 43)");
  await expect(download).toHaveCSS("color", "rgb(255, 255, 255)");
  await expect(page.locator(".hero-download-area")).toHaveCSS("filter", "none");
  const icon = await page.locator(".orbit-figma").boundingBox();
  const button = await download.boundingBox();
  expect(icon!.y + icon!.height + 12).toBeLessThan(button!.y);
  expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
  expect(errors).toEqual([]);
  await page.screenshot({ path: testInfo.outputPath("visual-landing.png"), fullPage: true });
});

test("explains hardware, offline limits and the beta with native disclosures", async ({ page }) => {
  await page.goto("/");
  const hardware = page.locator("summary").filter({ hasText: "Will it work on my Mac?" });
  await hardware.focus();
  await page.keyboard.press("Enter");
  await expect(page.getByText(/An 8 GB Mac can run transcription/)).toBeVisible();
  await expect(page.getByText(/macOS 15 or later/)).toBeVisible();
  await page.locator("summary").filter({ hasText: "Does it work offline?" }).click();
  await expect(page.getByText(/Web searches, browsing, model downloads/)).toBeVisible();
  await page.locator("summary").filter({ hasText: "What can the assistant do?" }).click();
  await expect(page.getByText(/Complex tasks may still need your help/)).toBeVisible();
});

test("keeps the landing usable when WebGL is unavailable", async ({ page }) => {
  await page.addInitScript(() => {
    const original = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (kind: string, ...args: unknown[]) {
      if (kind === "webgl2" || kind === "webgl") return null;
      return Reflect.apply(original, this, [kind, ...args]);
    } as typeof original;
  });
  await page.goto("/");
  await expect(page.locator(".core-fallback")).toHaveCSS("opacity", "1");
  await expect(page.locator(".orbit-app").first()).toHaveCSS("opacity", "1");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await expect(page.locator(".landing-download").first()).toBeVisible();
  await expect(page.locator(".hush-core canvas")).toHaveCount(0);
  const companion = page.getByRole("img", { name: /small hush cameo/ });
  await companion.scrollIntoViewIfNeeded();
  await expect(companion.locator("svg")).toBeVisible();
  await expect(companion.locator("canvas")).toHaveCount(0);
});

test("keeps the visual and download visible when the scene module fails", async ({ page }) => {
  await page.route(/HushScene.*\.js/, route => route.abort());
  await page.goto("/");
  await expect(page.locator(".hush-core")).toHaveAttribute("data-scene", "fallback");
  await expect(page.locator(".core-fallback")).toHaveCSS("opacity", "1");
  await expect(page.locator(".orbit-app").first()).toHaveCSS("opacity", "1");
  await expect(page.locator(".landing-download").first()).toBeVisible();
});

test("respects reduced motion while preserving the complete page", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await expect(page.locator(".orbit-app").first()).toHaveCSS("animation-name", "none");
  await expect(page.locator(".hush-landing")).not.toHaveAttribute("data-opening", /pending|playing/);
  await expect(page.locator(".landing-download").first()).toBeVisible();
  await page.locator(".thought-art").evaluate(el => {
    window.scrollTo({ top: scrollY + el.getBoundingClientRect().top - innerHeight * .62, behavior: "instant" });
  });
  const listener = page.getByRole("img", { name: /small hush cameo/ });
  await expect(listener.locator("svg")).toBeVisible();
  await expect(listener.locator("canvas")).toHaveCount(0);
  await expect(page.locator(".story-bridge")).toHaveCSS("animation-name", "none");
  const collage = page.locator(".provenance-collage");
  await collage.scrollIntoViewIfNeeded();
  const fragment = collage.locator(".press-echo");
  const originalFragmentPosition = await fragment.evaluate(el => getComputedStyle(el).translate);
  await collage.hover();
  await expect(fragment).toHaveCSS("translate", originalFragmentPosition);
});

test("allows Escape to end the entrance without blocking the page", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator(".hush-landing")).not.toHaveAttribute("data-opening", /pending|playing/);
  await expect(page.locator(".orbit-app").first()).toHaveCSS("opacity", "1");
});

test("keeps the mascot cameo within the artwork as the page scrolls", async ({ page }, testInfo) => {
  await page.goto("/");
  const companion = page.getByRole("img", { name: /small hush cameo/ });
  const art = page.locator(".thought-art");
  await art.scrollIntoViewIfNeeded();
  await expect(companion.locator("svg")).toBeVisible();
  await expect(companion.locator("canvas")).toHaveCount(0);
  const relativeTop = () => companion.evaluate(el => el.getBoundingClientRect().top - el.closest(".thought-art")!.getBoundingClientRect().top);
  const before = await relativeTop();
  await page.mouse.wheel(0, 150);
  await expect.poll(relativeTop).toBeCloseTo(before, 1);
  // Read both rectangles in the same frame while native scrolling settles.
  const { cameoBox, artBox } = await companion.evaluate(el => ({
    cameoBox: el.getBoundingClientRect().toJSON(),
    artBox: el.closest(".thought-art")!.getBoundingClientRect().toJSON(),
  }));
  expect(cameoBox.x).toBeGreaterThan(artBox.x);
  expect(cameoBox.x + cameoBox.width).toBeLessThan(artBox.x + artBox.width);
  expect(cameoBox.y).toBeGreaterThan(artBox.y);
  expect(cameoBox.y + cameoBox.height).toBeLessThan(artBox.y + artBox.height);
  expect(cameoBox.width / artBox.width).toBeLessThan(.28);
  await art.scrollIntoViewIfNeeded();
  await page.screenshot({ path: testInfo.outputPath("mascot-cameo.png") });
});

test("keeps download colors and position on hover and press", async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === "mobile", "Touch has no hover state");
  await page.goto("/");
  await expect(page.locator(".hush-landing")).not.toHaveAttribute("data-opening", /pending|playing/, { timeout: 8000 });
  for (const button of await page.locator(".site-header-download, .landing-download").all()) {
    await button.scrollIntoViewIfNeeded();
    await page.mouse.move(0, 0);
    const original = await button.boundingBox();
    const colors = await button.evaluate(el => {
      const style = getComputedStyle(el);
      return { background: style.backgroundColor, foreground: style.color };
    });
    await button.hover();
    await expect(button).toHaveCSS("background-color", colors.background);
    await expect(button).toHaveCSS("color", colors.foreground);
    await expect(button).toHaveCSS("translate", "none");
    await page.mouse.down();
    await expect(button).toHaveCSS("background-color", colors.background);
    await expect(button).toHaveCSS("color", colors.foreground);
    const pressed = await button.boundingBox();
    expect(pressed!.y).toBeCloseTo(original!.y, 1);
    await page.mouse.move(0, 0);
    await page.mouse.up();
    await page.keyboard.press("Tab");
    await button.focus();
    await expect(button).toBeFocused();
    await expect(button).toHaveCSS("outline-style", "solid");
  }
});

test("downloads the notarized alpha and opens its release notes", async ({
  browserName, context, page, isMobile,
}, testInfo) => {
  const downloadURL = "https://updates.behu.sh/downloads/hush-0.1.0-alpha.5-build.14.dmg";
  await context.route(downloadURL, async (route) => {
    await route.fulfill({
      status: 200,
      body: "test dmg",
      headers: {
        "content-type": "application/x-apple-diskimage",
        "content-disposition": 'attachment; filename="hush-0.1.0-alpha.5-build.14.dmg"',
        "cache-control": "public,max-age=31536000,immutable",
      },
    });
  });
  await page.goto("/");
  if (isMobile) {
    await page.locator(".landing-download").first().click();
    await expect(page.getByRole("dialog", { name: "Meet you on your Mac." })).toBeVisible();
    await expect(page.getByRole("link", { name: "Email myself the link" })).toHaveAttribute("href", /^mailto:/);
    return;
  }
  const requestPromise = page.waitForRequest(downloadURL);
  const releasePagePromise = page.waitForEvent("popup");
  const downloadPromise = browserName === "webkit" ? undefined : page.waitForEvent("download");
  await page.getByRole("link", { name: "Download for Mac" }).first().click();
  await requestPromise;
  if (downloadPromise) {
    const download = await downloadPromise;
    expect(download.suggestedFilename()).toBe("hush-0.1.0-alpha.5-build.14.dmg");
    await download.cancel();
  }
  const releasePage = await releasePagePromise;
  await expect(releasePage).toHaveURL(/\/releases\/0\.1\.0-alpha\.5$/);
  await expect(releasePage.getByRole("heading", { level: 1, name: "A clearer first step." })).toBeVisible();
  await expect(releasePage.getByText(/I'd like to open-source the app in the future/)).toBeVisible();
  await expect(releasePage.getByText(/full public release/).first()).toBeVisible();
  await expect(releasePage.getByText(/Build 14/)).toBeVisible();
  await expect(releasePage.getByText(/xattr|com\.apple\.quarantine|One extra step/)).toHaveCount(0);
  await expect(releasePage.getByRole("button", { name: /copy.*command/i })).toHaveCount(0);
  await expect(releasePage.locator('main a[download], main a[href*="updates.behu.sh/downloads/"]')).toHaveCount(0);
  await expect(releasePage.locator(".site-header").getByRole("link", { name: "Download", exact: true })).toHaveAttribute("href", downloadURL);
  expect(await releasePage.evaluate(
    () => document.documentElement.scrollWidth > window.innerWidth,
  )).toBe(false);
  await releasePage.screenshot({ path: testInfo.outputPath("installer-release.png"), fullPage: true });
});

test("withdraws old release pages and their Terminal instructions", async ({ page }) => {
  for (const slug of ["0.1.0-alpha.1", "0.1.0-alpha.2", "0.1.0-alpha.3"]) {
    const response = await page.goto(`/releases/${slug}`);
    expect(response?.status()).toBe(404);
    await expect(page.getByRole("heading", { name: "Nothing to install here." })).toBeVisible();
    await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", "noindex, nofollow");
    await expect(page.locator('a[download], a[href*="updates.behu.sh/downloads/"]')).toHaveCount(0);
    await expect(page.getByText(/xattr|com\.apple\.quarantine|One extra step/)).toHaveCount(0);
    await page.getByRole("link", { name: "View all releases" }).click();
    await expect(page.getByRole("heading", { name: "Our first notarized alpha." })).toBeVisible();
  }
});

test("shows the complete public correspondence address on every legal route", async ({ page }) => {
  for (const route of ["/impressum", "/datenschutz", "/de/impressum", "/de/datenschutz"]) {
    await page.goto(route);
    const address = page.locator("address");
    await expect(address).toHaveCount(1);
    await expect(address).toBeVisible();
    await expect(address).toHaveText(
      `Clemens Kressmannc/o COCENTERKoppoldstr. 186551 Aichach${route.startsWith("/de/") ? "Deutschland" : "Germany"}`,
    );
    expect((await address.innerText()).split("\n")).toEqual([
      "Clemens Kressmann", "c/o COCENTER", "Koppoldstr. 1", "86551 Aichach",
      route.startsWith("/de/") ? "Deutschland" : "Germany",
    ]);
  }
});

test("publishes legal drafts without indexing placeholder identities", async ({
  page,
  request,
}) => {
  for (const path of [
    "/impressum",
    "/datenschutz",
    "/de/impressum",
    "/de/datenschutz",
  ]) {
    const response = await request.get(path);
    expect(response.status()).toBe(200);
    expect(response.headers()["x-robots-tag"]).toBe("noindex, nofollow");
    expect(response.headers()["cache-control"]).toBe("no-store");
  }

  await page.goto("/impressum");
  await expect(page.getByRole("heading", { level: 1, name: "Legal notice" }))
    .toBeVisible();
  await expect(page.getByText("Draft with placeholders")).toHaveCount(0);
  await expect(page.getByText("DE455349278")).toBeVisible();
  await expect(page.getByText("Clemens Kressmann")).toBeVisible();
  await expect(page.getByText("c/o COCENTER")).toBeVisible();
  await expect(page.getByText("Koppoldstr. 1")).toBeVisible();
  await expect(page.getByText("86551 Aichach")).toBeVisible();
  await expect(page.getByRole("link", { name: "hello@behu.sh" })).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("lang", "en");
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute(
    "content",
    "noindex, nofollow",
  );

  await page.goto("/datenschutz");
  const legalNavigation = page.getByRole("navigation", { name: "Legal navigation" });
  await expect(legalNavigation.getByRole("link", { name: "Home", exact: true })).toBeVisible();
  await expect(legalNavigation.getByRole("link", { name: "EN", exact: true })).toHaveAttribute("aria-current", "page");
  await expect(
    page.getByRole("heading", { level: 1, name: "Privacy policy" }),
  ).toBeVisible();
  await expect(page.getByText("3. Website access and technical logs"))
    .toBeVisible();
  await expect(page.getByText(/expiry alone does not automatically delete/))
    .toBeVisible();

  await page.getByRole("link", { name: "DE", exact: true }).click();
  await expect(page).toHaveURL(/\/de\/datenschutz$/);
  await expect(
    page.getByRole("heading", { level: 1, name: "Datenschutzerklärung" }),
  ).toBeVisible();
  await expect(page.locator("html")).toHaveAttribute("lang", "de");
  await expect(page.getByText("Entwurf mit Platzhaltern")).toHaveCount(0);
  const germanNavigation = page.getByRole("navigation", { name: "Rechtliche Navigation" });
  await expect(germanNavigation.getByRole("link", { name: "DE", exact: true })).toHaveAttribute("aria-current", "page");
  await germanNavigation.getByRole("link", { name: "Startseite", exact: true }).click();
  await expect(page).toHaveURL(/\/$/);
});

test("opens the optional verification story from the privacy section", async ({
  page,
}) => {
  await page.goto("/");
  const featureBadge = page.getByRole("link", {
    name: "Explore Verified Messages",
  });
  await expect(featureBadge).toContainText("Verified Messages");
  await featureBadge.click();
  await expect(page).toHaveURL(/\/verified-messages$/);
  await expect(
    page.getByRole("heading", {
      level: 1,
      name: "Make your voice more than a post.",
    }),
  ).toBeVisible();
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
    "href",
    "https://behu.sh/verified-messages",
  );
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute(
    "content",
    "index, follow",
  );
  await page.getByRole("button", { name: "Verify", exact: true }).click();
  await expect(page.getByLabel("Illustrative Verified Message")).toBeVisible();
  await expect(page.getByText("Your audio stays on your Mac.")).toBeVisible();
  await expect(page.getByText(/Only your text and signed history travel/)).toBeVisible();
  await expect(page.getByText(/Decrypted in your browser. No audio attached/)).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth > window.innerWidth,
    ),
  ).toBe(false);
});

test("keeps unavailable release routes out of search indexing", async ({ request }) => {
  for (const [path, status] of [
    ["/releases", 200],
    ["/releases/latest", 200],
    ["/releases/0.1.0-alpha.4", 200],
    ["/releases/0.1.0-alpha.5", 200],
    ["/releases/0.1.0-alpha.2", 404],
    ["/releases/0.1.0-alpha.1", 404],
    ["/releases/unknown", 404],
  ] as const) {
    const response = await request.get(path);
    expect(response.status()).toBe(status);
    expect(response.headers()["x-robots-tag"]).toBe("noindex, nofollow");
    expect(response.headers()["cache-control"]).toBe("no-store");
  }
});

test("lists the corrected installer and retains the first notarized milestone", async ({ page }) => {
  await page.goto("/releases");
  await expect(page.getByRole("heading", { level: 1, name: "Release notes." })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Our first notarized alpha." })).toBeVisible();
  await expect(page.getByRole("heading", { name: "A clearer first step." })).toBeVisible();
  await expect(page.locator('a[href*="/releases/0.1.0-"]')).toHaveCount(2);
  await expect(page.getByRole("link", { name: "Open permanent page for 0.1 alpha 4" }))
    .toHaveAttribute("href", "/releases/0.1.0-alpha.4");
  await expect(page.getByText(/A smoother way into hush|Your voice, typed privately/)).toHaveCount(0);
  await page.goto("/releases/latest");
  await expect(page.getByRole("heading", { level: 1, name: "A clearer first step." })).toBeVisible();
  await expect(page.getByText(/Build 14/)).toBeVisible();
});


test("LANDING-006 keeps each locally hosted artwork with its story and credit", async ({ page }, testInfo) => {
  // This traverses the whole illustrated page and captures two full compositions.
  test.slow();
  const externalImages: string[] = [];
  await page.route("**/*", async route => {
    const request = route.request();
    if (!new URL(request.url()).hostname.match(/^(127\.0\.0\.1|localhost)$/)) {
      if (request.resourceType() === "image") externalImages.push(request.url());
      await route.abort();
      return;
    }
    await route.continue();
  });
  await page.goto("/");
  const freedom = page.getByRole("region", { name: "Keep your mind yours." });
  const liberty = freedom.locator("figure");
  await expect(liberty.getByRole("link", { name: "Liberty Leading the People" })).toHaveCount(1);
  await expect(liberty.getByRole("img", { name: /Delacroix/ })).toHaveCount(1);

  const intelligence = page.getByRole("region", { name: "Intelligence on your terms." });
  const figure = intelligence.getByRole("figure");
  const artwork = figure.getByRole("img", { name: /geographer/i });
  const heading = intelligence.getByRole("heading", { name: "Intelligence on your terms." });
  await expect(figure.getByRole("link", { name: "The Geographer", exact: true })).toHaveAttribute("href", /commons\.wikimedia\.org\/wiki\/File:/);
  await expect(intelligence.getByRole("link", { name: "Liberty Leading the People" })).toHaveCount(0);

  for (const image of await page.locator(".vision-story img:not([alt=''])").all()) {
    await image.scrollIntoViewIfNeeded();
    await expect(image).toBeVisible();
    await expect.poll(() => image.evaluate((el: HTMLImageElement) => el.complete && el.naturalWidth > 0)).toBe(true);
    expect(await image.evaluate((el: HTMLImageElement) => new URL(el.currentSrc).origin)).toBe(new URL(page.url()).origin);
  }
  const companion = intelligence.getByRole("img", { name: /hush thinking with you/ });
  await expect(companion).toBeVisible();
  await expect(page.getByRole("img", { name: /small hush cameo/ })).toBeVisible();
  await expect(page.locator(".local-compute-mark")).toHaveCount(0);
  await expect(intelligence.getByText(/Online tasks still use the internet/)).toBeVisible();
  await expect(page.getByRole("region", { name: "For minds of their own." })).toHaveCount(0);
  await expect(page.locator('img[src*="steve-jobs"]')).toHaveCount(0);
  await expect(page.locator(".hush-mascot")).toHaveCount(0);
  for (const mascot of [companion, page.getByRole("img", { name: /small hush cameo/ })]) {
    expect(await mascot.evaluate(el => el.closest("figure") !== null)).toBe(true);
    await expect(mascot.locator("svg")).toBeVisible();
    await expect(mascot.locator("canvas")).toHaveCount(0);
  }
  await intelligence.scrollIntoViewIfNeeded();
  const artBox = (await artwork.boundingBox())!;
  const headingBox = (await heading.boundingBox())!;
  expect(artBox.width).toBeGreaterThan(140);
  expect(artBox.height).toBeGreaterThan(170);
  expect(headingBox.x).toBeGreaterThanOrEqual(0);
  expect(headingBox.x + headingBox.width).toBeLessThanOrEqual(page.viewportSize()!.width);
  expect(externalImages).toEqual([]);
  expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
  const companionBox = (await companion.boundingBox())!;
  const windowBox = (await intelligence.locator(".intelligence-art").boundingBox())!;
  expect(companionBox.x).toBeGreaterThanOrEqual(windowBox.x);
  expect(companionBox.x + companionBox.width).toBeLessThanOrEqual(windowBox.x + windowBox.width);
  expect(companionBox.y + companionBox.height).toBeLessThanOrEqual(windowBox.y + windowBox.height);
  await expect(intelligence.getByRole("link", { name: "Explore the source" })).toHaveAttribute("href", "https://github.com/Powermama/hush");
  await page.getByRole("region", { name: "Think out loud." }).screenshot({ path: testInfo.outputPath("thought-artwork.png") });
  await intelligence.screenshot({ path: testInfo.outputPath("intelligence-artwork.png") });
});

test("LANDING-007 keeps the narrative and download usable when artwork fails", async ({ page, isMobile }) => {
  await page.route("**/art/**", route => route.abort());
  await page.goto("/");
  for (const name of ["Think out loud.", "Keep your mind yours.", "Intelligence on your terms.", "Reality has a copy problem.", "Give your words their story back."]) {
    const heading = page.getByRole("heading", { name });
    await heading.scrollIntoViewIfNeeded();
    await expect(heading).toBeVisible();
  }
  await expect(page.getByRole("link", { name: "Explore Verified Messages" })).toBeVisible();
  const download = page.locator(".landing-download").first();
  await download.scrollIntoViewIfNeeded();
  await expect(download).toBeVisible();
  if (isMobile) await expect(download).toHaveAttribute("aria-haspopup", "dialog");
  else await expect(download).toHaveAttribute("href", /updates\.behu\.sh\/downloads\//);
  expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
});

test("LANDING-VM-002 closes the visual story and links to the full proof explanation", async ({ page }, testInfo) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  const chapter = page.getByRole("region", { name: "Reality has a copy problem." });
  await chapter.scrollIntoViewIfNeeded();
  const woodcut = chapter.getByRole("img", { name: /Printers setting type/ });
  await expect.poll(() => woodcut.evaluate((el: HTMLImageElement) => el.complete && el.naturalWidth > 0)).toBe(true);
  await expect(chapter.getByRole("link", { name: "The printing press, 1568" })).toHaveAttribute("href", "https://commons.wikimedia.org/wiki/File:Buchdrucker-1568.png");
  await expect(chapter.getByText(/The internet gave everyone a voice/)).toBeVisible();
  await expect(chapter.getByRole("heading", { name: "Give your words their story back." })).toBeVisible();
  await expect(chapter.getByText("What’s verified?")).toHaveCount(0);
  await expect(chapter.getByText("Captured", { exact: true })).toHaveCount(0);
  await expect(chapter.locator(".provenance-resolution p")).toHaveCount(0);
  const question = chapter.locator(".noise-question");
  await expect(question).toHaveCSS("color", "rgb(17, 24, 39)");
  const questionBounds = (await question.boundingBox())!;
  expect(questionBounds.x).toBeGreaterThanOrEqual(0);
  expect(questionBounds.x + questionBounds.width).toBeLessThanOrEqual(page.viewportSize()!.width);
  const bounds = (await chapter.boundingBox())!;
  const intelligence = (await page.locator(".story-intelligence").boundingBox())!;
  const faq = (await page.getByRole("heading", { name: "A few things to know." }).boundingBox())!;
  expect(bounds.y).toBeGreaterThanOrEqual(intelligence.y + intelligence.height);
  expect(faq.y).toBeGreaterThan(bounds.y + bounds.height);
  expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
  await chapter.screenshot({ path: testInfo.outputPath("provenance-story.png") });
  const link = chapter.getByRole("link", { name: "Discover Verified Messages" });
  await link.focus();
  await expect(link).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/\/verified-messages$/);
  await expect(page.getByRole("heading", { name: "Make your voice more than a post." })).toBeVisible();
});
