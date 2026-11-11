import { expect, test } from "@playwright/test";
import { canonicalEnrollmentRequest } from "../shared/provenance/canonical";

test("registers a Mac through the public HTTP API contract", async ({ request }) => {
  const keys = (await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const publicKey = Buffer.from(
    await crypto.subtle.exportKey("raw", keys.publicKey),
  ).toString("base64url");

  const challengeResponse = await request.post("/v1/installations/challenges");
  expect(challengeResponse.status()).toBe(200);
  expect(challengeResponse.headers()["content-type"]).toContain("application/json");
  const challenge = (await challengeResponse.json()) as {
    id: string;
    nonce: string;
  };
  const signature = Buffer.from(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      keys.privateKey,
      new TextEncoder().encode(
        canonicalEnrollmentRequest(challenge.id, publicKey, challenge.nonce),
      ),
    ),
  ).toString("base64url");

  const enrollmentResponse = await request.post("/v1/installations/enroll", {
    data: {
      challengeId: challenge.id,
      publicKey,
      signature,
      keyKind: "keychain",
      appVersion: "0.1.0-alpha.1",
      platformVersion: "macOS E2E",
    },
  });

  expect(enrollmentResponse.status()).toBe(201);
  await expect(enrollmentResponse.json()).resolves.toMatchObject({
    id: expect.any(String),
    fingerprint: expect.any(String),
    createdAt: expect.any(String),
  });
});
