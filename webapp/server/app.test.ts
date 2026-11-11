import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { createApp } from "./app";
import {
  copyArrayBuffer,
  encodeBase64Url,
  sha256,
  utf8,
} from "./crypto/base64url";
import { createEphemeralServiceKey } from "./crypto/p256";
import {
  canonicalEnrollmentRequest,
  canonicalProofRequest,
  canonicalReceipt,
} from "../shared/provenance/canonical";
import type { ReserveProofInput } from "../shared/contracts/proof";
import { SQLiteProofRepository } from "./repositories/sqlite-proof-repository";
import { cleanupProofs } from "./services/proof-cleanup";
import { PROOF_RETENTION_MS } from "./services/retention-policy";
import { ProofService } from "./services/proof-service";
import type {
  ProofObjectStore,
  UploadTarget,
} from "./storage/proof-object-store";

class MemoryObjectStore implements ProofObjectStore {
  readonly values = new Map<string, Uint8Array>();

  async createUploadTarget(input: {
    objectKey: string;
    proofId: string;
    uploadToken: string;
    contentLength: number;
    contentType: string;
  }): Promise<UploadTarget> {
    return {
      url: `http://hush.test/v1/proofs/${input.proofId}/content?token=${input.uploadToken}`,
      headers: { "content-type": input.contentType },
    };
  }

  async put(objectKey: string, bytes: Uint8Array): Promise<void> {
    this.values.set(objectKey, Uint8Array.from(bytes));
  }

  async get(objectKey: string): Promise<Uint8Array | null> {
    return this.values.get(objectKey) ?? null;
  }

  async delete(objectKey: string): Promise<void> {
    this.values.delete(objectKey);
  }
}

describe("Hush provenance API", () => {
  let repository: SQLiteProofRepository;
  let objects: MemoryObjectStore;
  let app: ReturnType<typeof createApp>;

  beforeEach(async () => {
    repository = new SQLiteProofRepository();
    objects = new MemoryObjectStore();
    const serviceKey = await createEphemeralServiceKey();
    const service = new ProofService(
      repository,
      objects,
      serviceKey,
      "http://hush.test",
    );
    app = createApp({ proofService: service, allowedOrigin: "http://hush.test" });
  });

  afterEach(() => repository.close());

  test("enrolls, publishes, verifies, serves, and revokes an encrypted proof", async () => {
    const installationPair = (await crypto.subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign", "verify"],
    )) as CryptoKeyPair;
    const publicKey = encodeBase64Url(
      await crypto.subtle.exportKey("raw", installationPair.publicKey),
    );
    const enrollmentChallenge = await requestJson<Challenge>(
      app,
      "/v1/installations/challenges",
      { method: "POST" },
      200,
    );
    const enrollmentSignature = await sign(
      installationPair.privateKey,
      canonicalEnrollmentRequest(
        enrollmentChallenge.id,
        publicKey,
        enrollmentChallenge.nonce,
      ),
    );
    const installation = await requestJson<Installation>(
      app,
      "/v1/installations/enroll",
      jsonRequest({
        challengeId: enrollmentChallenge.id,
        publicKey,
        signature: enrollmentSignature,
        keyKind: "keychain",
        appVersion: "0.1.0-alpha.1",
        platformVersion: "macOS 15.6",
      }),
      201,
    );

    const publicationChallenge = await requestJson<Challenge>(
      app,
      "/v1/proofs/challenges",
      jsonRequest({ installationId: installation.id }),
      200,
    );
    const manifest = utf8(
      JSON.stringify({
        version: 1,
        nonce: encodeBase64Url(crypto.getRandomValues(new Uint8Array(32))),
      }),
    );
    const ciphertext = crypto.getRandomValues(new Uint8Array(512));
    const requestedExpiry = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
    requestedExpiry.setUTCMilliseconds(789);
    const unsigned: ReserveProofInput = {
      proofId: Bun.randomUUIDv7(),
      challengeId: publicationChallenge.id,
      installationId: installation.id,
      commitment: await sha256(manifest),
      ciphertextSha256: await sha256(ciphertext),
      ciphertextSize: ciphertext.byteLength,
      expiresAt: requestedExpiry.toISOString(),
      assuranceLevel: 2,
      signature: "pending",
    };
    const signature = await sign(
      installationPair.privateKey,
      canonicalProofRequest(unsigned, publicationChallenge.nonce),
    );
    const reservation = await requestJson<Reservation>(
      app,
      "/v1/proofs",
      jsonRequest({ ...unsigned, signature }),
      201,
    );
    const upload = new URL(reservation.uploadUrl);
    const uploadResponse = await app.request(`${upload.pathname}${upload.search}`, {
      method: "PUT",
      headers: reservation.uploadHeaders,
      body: ciphertext,
    });
    expect(uploadResponse.status).toBe(204);

    const completed = await requestJson<CompletedProof>(
      app,
      `/v1/proofs/${reservation.id}/complete`,
      jsonRequest({ completionToken: reservation.completionToken }),
      200,
    );
    const shortProofUrl = new URL(completed.proofUrl);
    expect(shortProofUrl.origin).toBe("http://hush.test");
    expect(shortProofUrl.pathname).toMatch(/^\/s\/[A-Za-z0-9_-]{6}$/);
    expect(shortProofUrl.hash).toBe("");

    const aliasResponse = await app.request(shortProofUrl.pathname);
    expect(aliasResponse.status).toBe(302);
    expect(aliasResponse.headers.get("location")).toBe(
      `http://hush.test/p/${reservation.slug}`,
    );
    expect(aliasResponse.headers.get("location")).not.toContain("#");
    expect(aliasResponse.headers.get("cache-control")).toBe(
      "public, max-age=300, s-maxage=300",
    );
    expect(aliasResponse.headers.get("referrer-policy")).toBe("no-referrer");
    expect(aliasResponse.headers.get("x-robots-tag")).toBe("noindex, nofollow");

    const aliasHeadResponse = await app.request(shortProofUrl.pathname, {
      method: "HEAD",
    });
    expect(aliasHeadResponse.status).toBe(302);
    expect(aliasHeadResponse.headers.get("location")).toBe(
      `http://hush.test/p/${reservation.slug}`,
    );
    expect(await aliasHeadResponse.text()).toBe("");

    const rootAliasPath = `/${shortProofUrl.pathname.split("/").at(-1)}`;
    const rootAliasResponse = await app.request(rootAliasPath);
    expect(rootAliasResponse.status).toBe(302);
    expect(rootAliasResponse.headers.get("location")).toBe(
      `http://hush.test/p/${reservation.slug}`,
    );
    expect(rootAliasResponse.headers.get("cache-control")).toBe(
      "public, max-age=300, s-maxage=300",
    );
    expect(rootAliasResponse.headers.get("x-robots-tag")).toBe(
      "noindex, nofollow",
    );

    const repeatedCompletion = await requestJson<CompletedProof>(
      app,
      `/v1/proofs/${reservation.id}/complete`,
      jsonRequest({ completionToken: reservation.completionToken }),
      200,
    );
    expect(repeatedCompletion.proofUrl).toBe(completed.proofUrl);

    const publicProof = await requestJson<PublicProof>(
      app,
      `/v1/proofs/${reservation.slug}`,
      undefined,
      200,
    );
    expect(publicProof.status).toBe("valid");
    expect(publicProof.receipt.expiresAt).toBe(unsigned.expiresAt);
    const servicePublicKey = await crypto.subtle.importKey(
      "jwk",
      publicProof.servicePublicKey,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    expect(
      await crypto.subtle.verify(
        { name: "ECDSA", hash: "SHA-256" },
        servicePublicKey,
        copyArrayBuffer(Uint8Array.from(Buffer.from(publicProof.receiptSignature, "base64url"))),
        copyArrayBuffer(utf8(canonicalReceipt(publicProof.receipt))),
      ),
    ).toBe(true);

    const contentResponse = await app.request(`/v1/proofs/${reservation.slug}/content`);
    expect(contentResponse.status).toBe(200);
    expect(new Uint8Array(await contentResponse.arrayBuffer())).toEqual(ciphertext);

    const revoked = await requestJson<{ status: string }>(
      app,
      `/v1/proofs/${reservation.slug}/revoke`,
      jsonRequest({ revocationSecret: reservation.revocationSecret }),
      200,
    );
    expect(revoked.status).toBe("revoked");
    const revokedMetadata = await requestJson<PublicProof>(
      app,
      `/v1/proofs/${reservation.slug}`,
      undefined,
      200,
    );
    expect(revokedMetadata.status).toBe("revoked");
    expect(objects.values.size).toBe(1);
    expect((await app.request(`/v1/proofs/${reservation.slug}/content`)).status).toBe(410);
    const completeAfterRevoke = await app.request(
      `/v1/proofs/${reservation.id}/complete`,
      jsonRequest({ completionToken: reservation.completionToken }),
    );
    expect(completeAfterRevoke.status).toBe(410);
    // Revocation first blocks access; cleanup later removes bytes, metadata and aliases.
    expect((await cleanupProofs(repository, objects)).deleted).toBe(0);
    const later = new Date(Date.now() + PROOF_RETENTION_MS + 1);
    expect((await cleanupProofs(repository, objects, later)).deleted).toBe(1);
    expect(objects.values.size).toBe(0);
    expect(await repository.findProofById(reservation.id)).toBeNull();
    expect((await app.request(shortProofUrl.pathname)).status).toBe(404);
    expect((await app.request(`/v1/proofs/${reservation.slug}/content`)).status).toBe(404);
  });

  test("rejects a replayed enrollment challenge", async () => {
    const pair = (await crypto.subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign", "verify"],
    )) as CryptoKeyPair;
    const publicKey = encodeBase64Url(
      await crypto.subtle.exportKey("raw", pair.publicKey),
    );
    const challenge = await requestJson<Challenge>(
      app,
      "/v1/installations/challenges",
      { method: "POST" },
      200,
    );
    const payload = {
      challengeId: challenge.id,
      publicKey,
      signature: await sign(
        pair.privateKey,
        canonicalEnrollmentRequest(challenge.id, publicKey, challenge.nonce),
      ),
      keyKind: "keychain",
      appVersion: "test",
      platformVersion: "test",
    };
    expect((await app.request("/v1/installations/enroll", jsonRequest(payload))).status).toBe(201);
    expect((await app.request("/v1/installations/enroll", jsonRequest(payload))).status).toBe(409);
  });

  test("does not resolve malformed or unknown short proof codes", async () => {
    expect((await app.request("/s/five5")).status).toBe(400);
    expect((await app.request("/s/Ab3dE7")).status).toBe(404);
    expect((await app.request("/five5")).status).toBe(404);
    expect((await app.request("/Ab3dE7")).status).toBe(404);
  });

  test("canonicalizes equivalent RFC 3339 proof expiries", () => {
    const base: ReserveProofInput = {
      proofId: "018f47a6-84d2-7a10-9c2d-2f2c29ba7b34",
      challengeId: "018f47a6-84d2-7a10-9c2d-2f2c29ba7111",
      installationId: "018f47a6-84d2-7a10-9c2d-2f2c29ba7000",
      commitment: "A".repeat(43),
      ciphertextSha256: "B".repeat(43),
      ciphertextSize: 512,
      expiresAt: "2026-08-31T12:00:00.000Z",
      assuranceLevel: 2,
      signature: "pending",
    };

    expect(canonicalProofRequest(base, "nonce")).toBe(
      canonicalProofRequest(
        { ...base, expiresAt: "2026-08-31T13:00:00+01:00" },
        "nonce",
      ),
    );
  });
});

type Challenge = { id: string; nonce: string; expiresAt: string };
type Installation = { id: string; fingerprint: string; createdAt: string };
type Reservation = {
  id: string;
  slug: string;
  uploadUrl: string;
  uploadHeaders: Record<string, string>;
  completionToken: string;
  revocationSecret: string;
};
type CompletedProof = { proofUrl: string };
type PublicProof = {
  status: string;
  receipt: Parameters<typeof canonicalReceipt>[0];
  receiptSignature: string;
  servicePublicKey: JsonWebKey;
};

function jsonRequest(value: unknown): RequestInit {
  return {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(value),
  };
}

async function sign(privateKey: CryptoKey, message: string): Promise<string> {
  return encodeBase64Url(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      privateKey,
      copyArrayBuffer(utf8(message)),
    ),
  );
}

async function requestJson<T>(
  target: ReturnType<typeof createApp>,
  path: string,
  init: RequestInit | undefined,
  expectedStatus: number,
): Promise<T> {
  const response = await target.request(path, init);
  if (response.status !== expectedStatus) {
    throw new Error(
      `Expected ${expectedStatus}, received ${response.status}: ${await response.text()}`,
    );
  }
  return (await response.json()) as T;
}
