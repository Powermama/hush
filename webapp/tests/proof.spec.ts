import { expect, test, type APIRequestContext } from "@playwright/test";
import { latestRelease } from "../shared/releases";
import type { ReserveProofInput } from "../shared/contracts/proof";
import {
  canonicalEnrollmentRequest,
  canonicalProofRequest,
  canonicalReceipt,
} from "../shared/provenance/canonical";

const e2eBaseUrl = process.env.HUSH_E2E_BASE_URL ?? "http://127.0.0.1:4173";

test("verifies and decrypts a complete signed message proof", async ({ page, isMobile }, testInfo) => {
  const fixture = await makeProofFixture();
  const errors: string[] = [];
  const outbound: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("request", request => outbound.push(request.url() + (request.postData() ?? "")));

  await page.route(`**/v1/proofs/${fixture.slug}`, async (route) => {
    await route.fulfill({ json: fixture.metadata });
  });
  await page.route(`**/v1/proofs/${fixture.slug}/content`, async (route) => {
    await route.fulfill({
      contentType: "application/vnd.hush.proof+encrypted",
      body: Buffer.from(fixture.ciphertext),
    });
  });

  await page.goto(`/p/${fixture.slug}#k=${fixture.key}`);

  await expect(page.getByText("Verified hush message")).toBeVisible();
  await expect(page.getByText("Perfect, let's lock in Thursday at 10.")).toBeVisible();
  await expect(page.getByText("Created from voice")).toBeVisible();
  await expect(page.getByText(/Alex.*self-declared/)).toBeVisible();
  await expect(page.getByRole("heading", { name: "Refined by local AI", exact: true })).toBeVisible();
  await expect(page.getByText("Local AI disclosed", { exact: true })).toBeVisible();
  await expect(page.locator(".proof-timeline li h3")).toHaveText(["Voice recorded", "Cleaned up locally", "Refined by local AI", "Signed and encrypted"]);
  await expect(page.locator('.proof-timeline li[data-kind="voice"] time')).toHaveAttribute("datetime", "2026-08-01T11:59:55.000Z");
  await expect(page.getByText("Business style.", { exact: false })).toBeVisible();
  await expect(page.getByText("AI-refined message", { exact: true })).toBeVisible();
  if (isMobile) {
    await expect(page.locator(".site-header-download")).toBeHidden();
    await expect(page.locator(".proof-download")).toBeVisible();
  } else {
    await expect(page.locator(".site-header").getByRole("link", { name: "Download", exact: true })).toHaveAttribute("href", latestRelease!.downloadURL);
    await expect(page.getByRole("link", { name: "Download for Mac", exact: true })).toHaveAttribute("href", latestRelease!.downloadURL);
  }
  expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
  await page.screenshot({ path: testInfo.outputPath("recipient-voice.png"), fullPage: true });
  await page.getByRole("button", { name: "Explore its history" }).click();
  await expect(page.locator("#message-history")).toBeFocused();
  await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(
    `#k=${fixture.key}`,
  );

  await page.locator(".proof-comparison summary").click();
  await page.getByRole("textbox", { name: "Received text" }).fill(fixture.manifest.finalText);
  await expect(page.getByText("✓ Exact match with the signed message")).toBeVisible();
  await page.getByRole("textbox", { name: "Received text" }).fill("A different message.");
  await expect(page.getByText("Message changed", { exact: true })).toBeVisible();
  expect(outbound.some(value => value.includes(fixture.key) || value.includes(fixture.manifest.finalText) || value.includes("A different message."))).toBe(false);

  await page.reload();
  await expect(page.getByText("Verified hush message")).toBeVisible();
  await expect(page.getByText("Perfect, let's lock in Thursday at 10.")).toBeVisible();
  expect(errors).toEqual([]);
});

test("keeps a signed version 1 proof verifiable without inventing history", async ({ page }) => {
  const fixture = await makeProofFixture(undefined, undefined, "microphone", 1);

  await page.route(`**/v1/proofs/${fixture.slug}`, async (route) => {
    await route.fulfill({ json: fixture.metadata });
  });
  await page.route(`**/v1/proofs/${fixture.slug}/content`, async (route) => {
    await route.fulfill({
      contentType: "application/vnd.hush.proof+encrypted",
      body: Buffer.from(fixture.ciphertext),
    });
  });

  await page.goto(`/p/${fixture.slug}#k=${fixture.key}`);

  await expect(page.getByText("Verified hush message")).toBeVisible();
  await expect(page.getByText("Voice captured locally")).toBeVisible();
  await expect(page.getByText("Voice recorded")).toHaveCount(0);
  await expect(page.locator(".proof-timeline time")).toHaveCount(1);
});

test("explains a message typed inside hush without claiming voice origin", async ({ page }, testInfo) => {
  const fixture = await makeProofFixture(undefined, undefined, "keyboard");

  await page.route(`**/v1/proofs/${fixture.slug}`, async (route) => {
    await route.fulfill({ json: fixture.metadata });
  });
  await page.route(`**/v1/proofs/${fixture.slug}/content`, async (route) => {
    await route.fulfill({
      contentType: "application/vnd.hush.proof+encrypted",
      body: Buffer.from(fixture.ciphertext),
    });
  });

  await page.goto(`/p/${fixture.slug}#k=${fixture.key}`);

  await expect(page.getByText("Verified hush message")).toBeVisible();
  await expect(page.getByText("Typed in hush")).toBeVisible();
  await expect(page.getByText("Message started in hush")).toBeVisible();
  await expect(page.getByText("Original text and changes")).toBeVisible();
  await expect(page.getByText("Created from voice")).toHaveCount(0);
  await expect(page.getByText("Original audio was not shared", { exact: false })).toHaveCount(0);
  await expect(page.getByText("Local AI disclosed", { exact: true })).toHaveCount(0);
  await expect(page.getByText("Manual edits recorded", { exact: true })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("recipient-typed.png"), fullPage: true });
});

test("shows immutable revision lineage and composer voice sections", async ({ page }, testInfo) => {
  const fixture = await makeProofFixture(undefined, undefined, "hush_history");

  await page.route(`**/v1/proofs/${fixture.slug}`, async (route) => {
    await route.fulfill({ json: fixture.metadata });
  });
  await page.route(`**/v1/proofs/${fixture.slug}/content`, async (route) => {
    await route.fulfill({
      contentType: "application/vnd.hush.proof+encrypted",
      body: Buffer.from(fixture.ciphertext),
    });
  });

  await page.goto(`/p/${fixture.slug}#k=${fixture.key}`);

  await expect(page.getByText("Voice recorded")).toBeVisible();
  await expect(page.getByText("Cleaned up locally")).toBeVisible();
  await expect(page.getByText("Voice section 1 added")).toBeVisible();
  await expect(page.getByText("Voice section 2 added")).toBeVisible();
  await expect(page.getByText("Edited inside hush")).toBeVisible();
  await expect(page.getByText("Edited and re-signed")).toBeVisible();
  await expect(page.getByText("Signed edited message")).toBeVisible();
  await expect(page.getByText("Local AI disclosed", { exact: true })).toHaveCount(0);
  await expect(page.locator(".proof-timeline li h3")).toHaveText(["Voice recorded", "Cleaned up locally", "Voice section 1 added", "Voice section 2 added", "Edited inside hush", "Edited and re-signed", "Signed and encrypted"]);
  await expect(page.locator('.proof-timeline li[data-kind="voice"] time')).toHaveCount(3);
  await page.screenshot({ path: testInfo.outputPath("recipient-revision.png"), fullPage: true });
  await expect(page.getByText("Signed refinement")).toHaveCount(0);
  await expect(page.getByText("Reopened in Hush")).toHaveCount(0);
  await expect(
    page.getByText("The complete history recorded in this signed proof."),
  ).toBeVisible();
  await page.getByText("Technical details").click();
  await expect(page.getByText("Previous proof")).toBeVisible();
  await expect(page.getByText("Previous commitment")).toBeVisible();
});

test("fails closed when signed expiry instants differ", async ({ page }) => {
  const fixture = await makeProofFixture("2026-08-31T12:00:00.000Z");

  await page.route(`**/v1/proofs/${fixture.slug}`, async (route) => {
    await route.fulfill({ json: fixture.metadata });
  });
  await page.route(`**/v1/proofs/${fixture.slug}/content`, async (route) => {
    await route.fulfill({
      contentType: "application/vnd.hush.proof+encrypted",
      body: Buffer.from(fixture.ciphertext),
    });
  });

  await page.goto(`/p/${fixture.slug}#k=${fixture.key}`);

  await expect(page.getByText("This message could not be verified")).toBeVisible();
  await expect(page.getByText("The proof expiry does not match.")).toBeVisible();
  await expect(page.getByText("Verified hush message")).toHaveCount(0);
});

test("fails closed when the private key fragment is missing", async ({ page }) => {
  await page.goto("/p/nondiscoverable-proof-slug");
  await expect(page.getByText("This private proof link is incomplete")).toBeVisible();
  await expect(page.getByText("Verified hush message")).toHaveCount(0);
});

for (const status of ["expired", "revoked"] as const) {
  test(`keeps the redesigned ${status} proof unavailable`, async ({ page }, testInfo) => {
    const fixture = await makeProofFixture();
    const contentRequests: string[] = [];
    page.on("request", request => { if (request.url().endsWith("/content")) contentRequests.push(request.url()); });
    await page.route(`**/v1/proofs/${fixture.slug}`, route => route.fulfill({ json: { ...fixture.metadata, status } }));
    await page.goto(`/p/${fixture.slug}#k=${fixture.key}`);
    await expect(page.getByRole("heading", { name: status === "expired" ? "This proof expired" : "The author revoked this proof" })).toBeVisible();
    await expect(page.locator('.proof-verification[data-tone="valid"], .proof-message, .proof-timeline, .proof-invitation')).toHaveCount(0);
    await expect(page.locator(".site-header")).toBeVisible();
    expect(contentRequests).toEqual([]);
    await page.screenshot({ path: testInfo.outputPath(`recipient-${status}.png`), fullPage: true });
  });
}

test("distinguishes automatic cleanup from AI and keeps long messages readable", async ({ page }) => {
  const fixture = await makeProofFixture(undefined, undefined, "microphone", 2, {
    localAI: false,
    displayName: null,
    finalText: "A thought can take more than a few words.\n".repeat(24) + "x".repeat(160),
  });
  await page.route(`**/v1/proofs/${fixture.slug}`, route => route.fulfill({ json: fixture.metadata }));
  await page.route(`**/v1/proofs/${fixture.slug}/content`, route => route.fulfill({ body: Buffer.from(fixture.ciphertext) }));
  await page.goto(`/p/${fixture.slug}#k=${fixture.key}`);
  await expect(page.getByText("Anonymous author", { exact: true })).toBeVisible();
  await expect(page.locator(".proof-message-text")).toHaveText(fixture.manifest.finalText);
  await expect(page.locator(".proof-timeline li h3")).toHaveText(["Voice recorded", "Cleaned up locally", "Signed and encrypted"]);
  await expect(page.getByText("Local AI disclosed", { exact: true })).toHaveCount(0);
  await expect(page.getByText("AI-refined message", { exact: true })).toHaveCount(0);
  await expect(page.locator(".proof-ai-share")).toHaveCount(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth)).toBe(false);
});

test("downloads hush from the recipient invitation without losing the private link", async ({ page, context, browserName, isMobile }) => {
  const fixture = await makeProofFixture();
  const release = latestRelease!;
  await page.route(`**/v1/proofs/${fixture.slug}`, route => route.fulfill({ json: fixture.metadata }));
  await page.route(`**/v1/proofs/${fixture.slug}/content`, route => route.fulfill({ body: Buffer.from(fixture.ciphertext) }));
  await context.route(release.downloadURL, route => route.fulfill({
    body: "local test download",
    headers: { "content-type": "application/x-apple-diskimage", "content-disposition": `attachment; filename="${release.downloadName}"` },
  }));
  await page.goto(`/p/${fixture.slug}#k=${fixture.key}`);
  await expect(page.getByRole("heading", { name: "Verified hush message", exact: true })).toBeVisible();
  if (isMobile) {
    await page.locator(".proof-download").click();
    const sheet = page.getByRole("dialog", { name: "Meet you on your Mac." });
    await expect(sheet.getByRole("textbox", { name: "hush download page" })).toHaveValue("https://behu.sh/");
    const email = await sheet.getByRole("link", { name: "Email myself the link" }).getAttribute("href");
    expect(email).not.toContain(fixture.key);
    expect(decodeURIComponent(email!)).not.toContain(fixture.manifest.finalText);
    await sheet.getByRole("button", { name: "Close", exact: true }).click();
    await expect.poll(() => page.evaluate(() => location.hash)).toBe(`#k=${fixture.key}`);
    return;
  }
  const request = page.waitForRequest(release.downloadURL);
  const popup = page.waitForEvent("popup");
  const download = browserName === "webkit" ? undefined : page.waitForEvent("download");
  await page.getByRole("link", { name: "Download for Mac", exact: true }).click();
  await request;
  if (download) {
    const file = await download;
    expect(file.suggestedFilename()).toBe(release.downloadName);
    await file.cancel();
  }
  const notes = await popup;
  await expect(notes).toHaveURL(new RegExp(`/releases/${release.version.replaceAll(".", "\\.")}$`));
  await expect.poll(() => page.evaluate(() => location.hash)).toBe(`#k=${fixture.key}`);
  await notes.close();
});

test("preserves the private key through a real short proof redirect", async ({
  page,
  request,
}) => {
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
  expiresAt.setUTCMilliseconds(789);
  const fixture = await makeProofFixture(undefined, {
    createdAt: now.toISOString(),
    manifestExpiresAt: expiresAt.toISOString(),
  });
  const completed = await publishProof(request, fixture);

  const shortProofUrl = new URL(completed.proofUrl);
  expect(shortProofUrl.origin).toBe(e2eBaseUrl);
  expect(shortProofUrl.pathname).toMatch(/^\/s\/[A-Za-z0-9_-]{6}$/);
  const code = shortProofUrl.pathname.split("/").at(-1);
  await page.goto(`${e2eBaseUrl}/${code}#k=${fixture.key}`);

  await expect(page.getByText("Verified hush message")).toBeVisible();
  await expect(page.getByText("Perfect, let's lock in Thursday at 10.")).toBeVisible();
  await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(
    `#k=${fixture.key}`,
  );
  expect(new URL(page.url()).pathname).toBe(`/p/${completed.slug}`);

  const forwardedPage = await page.context().newPage();
  await forwardedPage.goto(page.url());
  await expect(forwardedPage.getByText("Verified hush message")).toBeVisible();
  await expect(
    forwardedPage.getByText("Perfect, let's lock in Thursday at 10."),
  ).toBeVisible();
  await forwardedPage.close();
});

async function makeProofFixture(
  receiptExpiresAt?: string,
  dates: {
    createdAt: string;
    manifestExpiresAt: string;
  } | undefined = {
    createdAt: new Date("2026-08-01T12:00:00.000Z").toISOString(),
    manifestExpiresAt: "2026-08-31T12:00:00.789Z",
  },
  source: "microphone" | "keyboard" | "hush_history" = "microphone",
  manifestVersion: 1 | 2 = 2,
  options: { localAI?: boolean; displayName?: string | null; finalText?: string } = {},
) {
  const proofId = crypto.randomUUID();
  const parentProofId = crypto.randomUUID();
  const parentCommitment = encode(crypto.getRandomValues(new Uint8Array(32)));
  const firstVoiceSectionId = crypto.randomUUID();
  const secondVoiceSectionId = crypto.randomUUID();
  const slug = "test-proof-slug-4gJ8qA2pN7wK";
  const { createdAt, manifestExpiresAt } = dates ?? {
    createdAt: new Date("2026-08-01T12:00:00.000Z").toISOString(),
    manifestExpiresAt: "2026-08-31T12:00:00.789Z",
  };
  const installationKeys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const origin = source === "microphone" ? {
    capture: {
      source: "microphone",
      durationMs: 3_200,
      sampleRate: 16_000,
      audioSha256: encode(crypto.getRandomValues(new Uint8Array(32))),
    },
    transcription: {
      rawText: "Perfect lets lock in Thursday at ten",
      modelId: "large-v3",
      modelDisplayName: "Large v3",
      language: "en",
    },
    transformations: [
      { kind: "cleanup", algorithmVersion: "basic-v1" },
      {
        kind: "local_ai",
        provider: "Apple Intelligence",
        model: "System model",
        persona: "Business",
        algorithmVersion: "persona-v1",
      },
    ],
    provenanceEvents: [
      {
        id: crypto.randomUUID(),
        occurredAt: "2026-08-01T11:59:55.000Z",
        kind: "voice_capture",
        durationMs: 3_200,
        modelDisplayName: "Large v3",
      },
      {
        id: crypto.randomUUID(),
        occurredAt: "2026-08-01T11:59:59.000Z",
        kind: "cleanup_applied",
      },
      {
        id: crypto.randomUUID(),
        occurredAt: createdAt,
        kind: "local_ai_refined",
        modelDisplayName: "Apple Intelligence",
        persona: "Business",
      },
    ],
    aiEditShare: 0.28,
  } as const : source === "hush_history" ? {
      capture: { source: "hush_history" },
      sourceText: "Perfect, lets lock in Thursday at 10.",
      revision: {
        parentProofId,
        parentCommitment,
      },
      provenanceEvents: [
        {
          id: crypto.randomUUID(),
          occurredAt: "2026-07-30T14:30:00.000Z",
          kind: "voice_capture",
          durationMs: 12_400,
          modelDisplayName: "Large v3",
        },
        {
          id: crypto.randomUUID(),
          occurredAt: "2026-07-30T14:30:15.000Z",
          kind: "cleanup_applied",
        },
        {
          id: crypto.randomUUID(),
          occurredAt: "2026-07-30T14:32:00.000Z",
          kind: "voice_section_added",
          voiceSegmentId: firstVoiceSectionId,
          durationMs: 8_200,
          modelDisplayName: "Large v3",
        },
        {
          id: crypto.randomUUID(),
          occurredAt: "2026-07-30T14:34:00.000Z",
          kind: "voice_section_added",
          voiceSegmentId: secondVoiceSectionId,
          durationMs: 5_400,
          modelDisplayName: "Large v3",
        },
        {
          id: crypto.randomUUID(),
          occurredAt: "2026-08-01T11:59:45.000Z",
          kind: "manual_edit",
        },
        {
          id: crypto.randomUUID(),
          occurredAt: createdAt,
          kind: "revision_created",
          parentProofId,
          parentCommitment,
        },
      ],
      transformations: [
        { kind: "cleanup", algorithmVersion: "basic-v1" },
        { kind: "manual_hush_edit", algorithmVersion: "editor-v1" },
      ],
    } as const : {
      capture: { source: "keyboard" },
      sourceText: "Perfect, lets lock in Thursday at 10.",
      provenanceEvents: [
        {
          id: crypto.randomUUID(),
          occurredAt: "2026-08-01T11:59:00.000Z",
          kind: "message_started",
        },
        {
          id: crypto.randomUUID(),
          occurredAt: createdAt,
          kind: "manual_edit",
        },
      ],
      transformations: [
        { kind: "manual_hush_edit", algorithmVersion: "editor-v1" },
      ],
    } as const;
  const manifest = {
    version: manifestVersion,
    proofId,
    commitmentNonce: encode(crypto.getRandomValues(new Uint8Array(32))),
    createdAt,
    expiresAt: manifestExpiresAt,
    author: options.displayName === null ? { identityKind: "anonymous" } : { displayName: options.displayName ?? "Alex", identityKind: "self_declared" },
    ...origin,
    transformations: options.localAI === false ? origin.transformations.filter(item => item.kind !== "local_ai") : origin.transformations,
    provenanceEvents: manifestVersion === 2 ? origin.provenanceEvents.filter(event => options.localAI !== false || event.kind !== "local_ai_refined") : undefined,
    ...(options.localAI === false ? { aiEditShare: undefined } : {}),
    finalText: options.finalText ?? "Perfect, let's lock in Thursday at 10.",
  } as const;
  const manifestBytes = new TextEncoder().encode(JSON.stringify(manifest));
  const manifestSignature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      installationKeys.privateKey,
      manifestBytes,
    ),
  );
  const installationPublicKey = new Uint8Array(
    await crypto.subtle.exportKey("raw", installationKeys.publicKey),
  );
  const proofPackage = new TextEncoder().encode(
    JSON.stringify({
      version: 1,
      manifest: encode(manifestBytes),
      manifestSignature: encode(manifestSignature),
      installationPublicKey: encode(installationPublicKey),
      signatureAlgorithm: "ES256",
    }),
  );
  const keyBytes = crypto.getRandomValues(new Uint8Array(32));
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const encryptionKey = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, [
    "encrypt",
  ]);
  const encrypted = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, encryptionKey, proofPackage),
  );
  const ciphertext = new Uint8Array(nonce.byteLength + encrypted.byteLength);
  ciphertext.set(nonce);
  ciphertext.set(encrypted, nonce.byteLength);

  const receipt = {
    version: 1 as const,
    keyId: "test-service-key",
    proofId,
    slug,
    commitment: await digest(manifestBytes),
    ciphertextSha256: await digest(ciphertext),
    ciphertextSize: ciphertext.byteLength,
    assuranceLevel: 2,
    createdAt,
    expiresAt: receiptExpiresAt ?? manifestExpiresAt,
  };
  const serviceKeys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const receiptSignature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      serviceKeys.privateKey,
      new TextEncoder().encode(canonicalReceipt(receipt)),
    ),
  );
  const servicePublicKey = await crypto.subtle.exportKey("jwk", serviceKeys.publicKey);

  return {
    proofId,
    slug,
    key: encode(keyBytes),
    ciphertext,
    manifest,
    installationKeys,
    metadata: {
      status: "valid",
      receipt,
      receiptSignature: encode(receiptSignature),
      servicePublicKey,
      ciphertextUrl: `${e2eBaseUrl}/v1/proofs/${slug}/content`,
    },
  };
}

async function publishProof(
  request: APIRequestContext,
  fixture: Awaited<ReturnType<typeof makeProofFixture>>,
): Promise<{ proofUrl: string; slug: string }> {
  const publicKey = encode(
    new Uint8Array(
      await crypto.subtle.exportKey("raw", fixture.installationKeys.publicKey),
    ),
  );
  const enrollmentChallenge = await postJson<Challenge>(
    request,
    "/v1/installations/challenges",
  );
  const installation = await postJson<Installation>(
    request,
    "/v1/installations/enroll",
    {
      challengeId: enrollmentChallenge.id,
      publicKey,
      signature: await signMessage(
        fixture.installationKeys.privateKey,
        canonicalEnrollmentRequest(
          enrollmentChallenge.id,
          publicKey,
          enrollmentChallenge.nonce,
        ),
      ),
      keyKind: "keychain",
      appVersion: "proof-e2e",
      platformVersion: "playwright",
    },
  );
  const publicationChallenge = await postJson<Challenge>(
    request,
    "/v1/proofs/challenges",
    { installationId: installation.id },
  );
  const unsigned: ReserveProofInput = {
    proofId: fixture.proofId,
    challengeId: publicationChallenge.id,
    installationId: installation.id,
    commitment: await digest(
      new TextEncoder().encode(JSON.stringify(fixture.manifest)),
    ),
    ciphertextSha256: await digest(fixture.ciphertext),
    ciphertextSize: fixture.ciphertext.byteLength,
    expiresAt: fixture.manifest.expiresAt,
    assuranceLevel: 2,
    signature: "pending",
  };
  const reservation = await postJson<Reservation>(request, "/v1/proofs", {
    ...unsigned,
    signature: await signMessage(
      fixture.installationKeys.privateKey,
      canonicalProofRequest(unsigned, publicationChallenge.nonce),
    ),
  });
  const upload = await request.put(reservation.uploadUrl, {
    headers: reservation.uploadHeaders,
    data: Buffer.from(fixture.ciphertext),
  });
  expect(upload.status()).toBe(204);
  const completed = await postJson<{ proofUrl: string }>(
    request,
    `/v1/proofs/${reservation.id}/complete`,
    { completionToken: reservation.completionToken },
  );
  return { ...completed, slug: reservation.slug };
}

type Challenge = { id: string; nonce: string };
type Installation = { id: string };
type Reservation = {
  id: string;
  slug: string;
  uploadUrl: string;
  uploadHeaders: Record<string, string>;
  completionToken: string;
};

async function postJson<T>(
  request: APIRequestContext,
  path: string,
  data?: unknown,
): Promise<T> {
  const response = await request.post(path, { data });
  expect(response.ok(), await response.text()).toBe(true);
  return (await response.json()) as T;
}

async function signMessage(privateKey: CryptoKey, message: string): Promise<string> {
  return encode(
    new Uint8Array(
      await crypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        privateKey,
        new TextEncoder().encode(message),
      ),
    ),
  );
}

async function digest(bytes: Uint8Array): Promise<string> {
  return encode(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
}

function encode(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("base64url");
}
