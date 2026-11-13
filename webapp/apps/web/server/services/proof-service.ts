import { timingSafeEqual } from "node:crypto";
import {
  SHORT_PROOF_CODE_LENGTH,
  shortProofCodeSchema,
} from "../../shared/contracts/proof";
import type {
  EnrollInstallationInput,
  ReserveProofInput,
  ServiceReceipt,
} from "../../shared/contracts/proof";
import {
  canonicalEnrollmentRequest,
  canonicalProofRequest,
  canonicalReceipt,
} from "../../shared/provenance/canonical";
import {
  randomBase64Url,
  sha256,
  utf8,
} from "../crypto/base64url";
import {
  importP256PublicKey,
  publicKeyFingerprint,
  signP256,
  verifyP256,
  type ServiceSigningKey,
} from "../crypto/p256";
import type { ProofRecord } from "../domain/models";
import type { ProofRepository } from "../repositories/proof-repository";
import type { ProofObjectStore } from "../storage/proof-object-store";
import { ServiceError } from "./service-error";

const CHALLENGE_LIFETIME_MS = 5 * 60 * 1000;
const MIN_PROOF_LIFETIME_MS = 60 * 1000;
const MAX_PROOF_LIFETIME_MS = 90 * 24 * 60 * 60 * 1000;
const PROOF_CONTENT_TYPE = "application/vnd.hush.proof+encrypted";
const SHORT_CODE_BYTES = 6;
const SHORT_CODE_ATTEMPTS = 5;

type ProofServiceOptions = {
  shortBaseUrl?: string;
  now?: () => Date;
  generateShortCode?: () => string;
};

export class ProofService {
  constructor(
    private readonly repository: ProofRepository,
    private readonly objects: ProofObjectStore,
    private readonly serviceKey: ServiceSigningKey,
    private readonly publicBaseUrl: string,
    options: ProofServiceOptions = {},
  ) {
    this.shortBaseUrl =
      options.shortBaseUrl ?? new URL("/s/", publicBaseUrl).toString();
    this.now = options.now ?? (() => new Date());
    this.generateShortCode =
      options.generateShortCode ??
      (() => randomBase64Url(SHORT_CODE_BYTES).slice(0, SHORT_PROOF_CODE_LENGTH));
  }

  private readonly shortBaseUrl: string;
  private readonly now: () => Date;
  private readonly generateShortCode: () => string;

  async createEnrollmentChallenge() {
    const now = this.now();
    const challenge = await this.repository.createChallenge({
      purpose: "enroll",
      nonce: randomBase64Url(32),
      installationId: null,
      expiresAt: new Date(now.getTime() + CHALLENGE_LIFETIME_MS),
    });
    return {
      id: challenge.id,
      nonce: challenge.nonce,
      expiresAt: challenge.expiresAt.toISOString(),
    };
  }

  async enrollInstallation(input: EnrollInstallationInput) {
    const challenge = await this.repository.consumeChallenge({
      id: input.challengeId,
      purpose: "enroll",
      now: this.now(),
    });
    if (!challenge) {
      throw new ServiceError(
        "invalid_challenge",
        "The enrollment challenge is missing, expired, or already used.",
        409,
      );
    }
    let publicKey: CryptoKey;
    try {
      publicKey = await importP256PublicKey(input.publicKey);
    } catch {
      throw new ServiceError("invalid_public_key", "Invalid P-256 public key.", 422);
    }
    const valid = await verifyP256(
      publicKey,
      input.signature,
      canonicalEnrollmentRequest(challenge.id, input.publicKey, challenge.nonce),
    );
    if (!valid) {
      throw new ServiceError(
        "invalid_signature",
        "The installation signature could not be verified.",
        401,
      );
    }
    const fingerprint = await publicKeyFingerprint(input.publicKey);
    const existing = await this.repository.findInstallationByFingerprint(fingerprint);
    const installation =
      existing ??
      (await this.repository.createInstallation({
        publicKey: input.publicKey,
        fingerprint,
        keyKind: input.keyKind,
        appVersion: input.appVersion,
        platformVersion: input.platformVersion,
      }));
    return {
      id: installation.id,
      fingerprint: installation.fingerprint,
      createdAt: installation.createdAt.toISOString(),
    };
  }

  async createPublicationChallenge(installationId: string) {
    const installation = await this.requireActiveInstallation(installationId);
    const now = this.now();
    const challenge = await this.repository.createChallenge({
      purpose: "publish",
      nonce: randomBase64Url(32),
      installationId: installation.id,
      expiresAt: new Date(now.getTime() + CHALLENGE_LIFETIME_MS),
    });
    return {
      id: challenge.id,
      nonce: challenge.nonce,
      expiresAt: challenge.expiresAt.toISOString(),
    };
  }

  async reserveProof(input: ReserveProofInput) {
    const now = this.now();
    const expiresAt = new Date(input.expiresAt);
    const lifetime = expiresAt.getTime() - now.getTime();
    if (lifetime < MIN_PROOF_LIFETIME_MS || lifetime > MAX_PROOF_LIFETIME_MS) {
      throw new ServiceError(
        "invalid_expiry",
        "Proof expiry must be between one minute and 90 days.",
        422,
      );
    }
    const installation = await this.requireActiveInstallation(input.installationId);
    const challenge = await this.repository.consumeChallenge({
      id: input.challengeId,
      purpose: "publish",
      installationId: installation.id,
      now,
    });
    if (!challenge) {
      throw new ServiceError(
        "invalid_challenge",
        "The publication challenge is missing, expired, or already used.",
        409,
      );
    }
    const publicKey = await importP256PublicKey(installation.publicKey);
    const valid = await verifyP256(
      publicKey,
      input.signature,
      canonicalProofRequest(input, challenge.nonce),
    );
    if (!valid) {
      throw new ServiceError(
        "invalid_signature",
        "The proof reservation signature could not be verified.",
        401,
      );
    }
    const proofId = input.proofId;
    const slug = randomBase64Url(18);
    const uploadToken = randomBase64Url(32);
    const completionToken = uploadToken;
    const revocationSecret = randomBase64Url(32);
    const objectKey = `proofs/${proofId}.bin`;
    const proof = await this.repository.createProof({
      id: proofId,
      slug,
      installationId: installation.id,
      objectKey,
      commitment: input.commitment,
      ciphertextSha256: input.ciphertextSha256,
      ciphertextSize: input.ciphertextSize,
      assuranceLevel: input.assuranceLevel,
      completionTokenHash: await sha256(utf8(completionToken)),
      revocationSecretHash: await sha256(utf8(revocationSecret)),
      createdAt: now,
      expiresAt,
    });
    await this.repository.touchInstallation(installation.id, now);
    const target = await this.objects.createUploadTarget({
      objectKey,
      proofId,
      uploadToken,
      contentLength: proof.ciphertextSize,
      contentType: PROOF_CONTENT_TYPE,
    });
    return {
      id: proof.id,
      slug: proof.slug,
      uploadUrl: target.url,
      uploadHeaders: target.headers,
      completionToken,
      revocationSecret,
    };
  }

  async uploadProofContent(id: string, token: string, bytes: Uint8Array) {
    const proof = await this.requirePendingProof(id);
    await this.requireSecret(token, proof.completionTokenHash, "upload token");
    if (bytes.byteLength !== proof.ciphertextSize) {
      throw new ServiceError(
        "size_mismatch",
        "The encrypted proof size does not match its reservation.",
        422,
      );
    }
    const digest = await sha256(bytes);
    if (!safeStringEqual(digest, proof.ciphertextSha256)) {
      throw new ServiceError(
        "digest_mismatch",
        "The encrypted proof does not match its reserved digest.",
        422,
      );
    }
    await this.objects.put(proof.objectKey, bytes);
    // Revocation or cleanup may have occurred while the object store was writing.
    const current = await this.repository.findProofById(id);
    if (!current || current.deletedAt || current.revokedAt || current.expiresAt <= this.now()) {
      await this.objects.delete(proof.objectKey);
      throw new ServiceError("proof_unavailable", "This proof is no longer available.", 410);
    }
  }

  async completeProof(id: string, completionToken: string) {
    const proof = await this.repository.findProofById(id);
    if (!proof || proof.deletedAt) {
      throw new ServiceError("proof_not_found", "Proof not found.", 404);
    }
    await this.requireSecret(
      completionToken,
      proof.completionTokenHash,
      "completion token",
    );
    this.requireAvailableProof(proof);
    if (proof.completedAt) return this.completedResponse(proof);
    const bytes = await this.objects.get(proof.objectKey);
    if (!bytes) {
      throw new ServiceError(
        "object_missing",
        "The encrypted proof has not been uploaded.",
        409,
      );
    }
    if (bytes.byteLength !== proof.ciphertextSize) {
      await this.objects.delete(proof.objectKey);
      throw new ServiceError(
        "size_mismatch",
        "The uploaded object size does not match the reservation.",
        422,
      );
    }
    const digest = await sha256(bytes);
    if (!safeStringEqual(digest, proof.ciphertextSha256)) {
      await this.objects.delete(proof.objectKey);
      throw new ServiceError(
        "digest_mismatch",
        "The uploaded object does not match the reservation.",
        422,
      );
    }
    const receipt: ServiceReceipt = {
      version: 1,
      keyId: this.serviceKey.id,
      proofId: proof.id,
      slug: proof.slug,
      commitment: proof.commitment,
      ciphertextSha256: proof.ciphertextSha256,
      ciphertextSize: proof.ciphertextSize,
      assuranceLevel: proof.assuranceLevel,
      createdAt: proof.createdAt.toISOString(),
      expiresAt: proof.expiresAt.toISOString(),
    };
    const receiptJson = JSON.stringify(receipt);
    const receiptSignature = await signP256(
      this.serviceKey.privateKey,
      canonicalReceipt(receipt),
    );
    const completed = await this.repository.completeProof({
      id: proof.id,
      receiptJson,
      receiptSignature,
      completedAt: this.now(),
    });
    if (!completed) {
      const current = await this.repository.findProofById(proof.id);
      if (!current?.receiptJson || !current.receiptSignature) {
        throw new ServiceError(
          "completion_conflict",
          "The proof could not be completed.",
          409,
        );
      }
      this.requireAvailableProof(current);
      return this.completedResponse(current);
    }
    return this.completedResponse(completed);
  }

  async resolveProofAlias(code: string) {
    const proof = await this.repository.findProofByAlias(code);
    if (
      !proof ||
      proof.deletedAt ||
      !proof.completedAt ||
      !proof.receiptJson ||
      !proof.receiptSignature
    ) {
      throw new ServiceError("proof_not_found", "Proof not found.", 404);
    }
    return new URL(`/p/${proof.slug}`, this.publicBaseUrl).toString();
  }

  async getPublicProof(slug: string) {
    const proof = await this.requirePublishedProof(slug);
    const status = this.publicStatus(proof);
    return {
      status,
      receipt: JSON.parse(proof.receiptJson!) as ServiceReceipt,
      receiptSignature: proof.receiptSignature!,
      servicePublicKey: this.serviceKey.publicJwk,
      ciphertextUrl: new URL(`/v1/proofs/${proof.slug}/content`, this.publicBaseUrl)
        .toString(),
    };
  }

  async getPublicCiphertext(slug: string): Promise<Uint8Array> {
    const proof = await this.requirePublishedProof(slug);
    if (this.publicStatus(proof) !== "valid") {
      throw new ServiceError(
        "proof_unavailable",
        "This proof is expired or revoked.",
        410,
      );
    }
    const bytes = await this.objects.get(proof.objectKey);
    if (!bytes) {
      throw new ServiceError("object_missing", "The proof object is unavailable.", 404);
    }
    return bytes;
  }

  async revokeProof(slug: string, secret: string) {
    const proof = await this.repository.findProofBySlug(slug);
    if (!proof || proof.deletedAt) {
      throw new ServiceError("proof_not_found", "Proof not found.", 404);
    }
    await this.requireSecret(secret, proof.revocationSecretHash, "revocation secret");
    const revoked = await this.repository.revokeProof(proof.id, this.now());
    return { status: revoked?.revokedAt ? "revoked" : "valid" };
  }

  private async requireActiveInstallation(id: string) {
    const installation = await this.repository.findInstallation(id);
    if (!installation) {
      throw new ServiceError("installation_not_found", "Installation not found.", 404);
    }
    if (installation.revokedAt) {
      throw new ServiceError("installation_revoked", "Installation is revoked.", 403);
    }
    return installation;
  }

  private async requirePendingProof(id: string) {
    const proof = await this.repository.findProofById(id);
    if (!proof || proof.deletedAt) {
      throw new ServiceError("proof_not_found", "Proof not found.", 404);
    }
    this.requireAvailableProof(proof);
    if (proof.completedAt) {
      throw new ServiceError("proof_completed", "Proof is already complete.", 409);
    }
    return proof;
  }

  private requireAvailableProof(proof: ProofRecord) {
    if (proof.deletedAt || proof.revokedAt || proof.expiresAt <= this.now()) {
      throw new ServiceError("proof_unavailable", "This proof is expired or revoked.", 410);
    }
  }

  private async requirePublishedProof(slug: string) {
    const proof = await this.repository.findProofBySlug(slug);
    if (
      !proof ||
      proof.deletedAt ||
      !proof.completedAt ||
      !proof.receiptJson ||
      !proof.receiptSignature
    ) {
      throw new ServiceError("proof_not_found", "Proof not found.", 404);
    }
    return proof;
  }

  private publicStatus(proof: ProofRecord): "valid" | "expired" | "revoked" {
    if (proof.revokedAt) return "revoked";
    if (proof.expiresAt <= this.now()) return "expired";
    return "valid";
  }

  private async completedResponse(proof: ProofRecord) {
    const alias = await this.ensureProofAlias(proof.id);
    return {
      proofUrl: new URL(alias, this.shortBaseUrl).toString(),
      receipt: JSON.parse(proof.receiptJson!) as ServiceReceipt,
      receiptSignature: proof.receiptSignature!,
    };
  }

  private async ensureProofAlias(proofId: string): Promise<string> {
    for (let attempt = 0; attempt < SHORT_CODE_ATTEMPTS; attempt += 1) {
      const code = this.generateShortCode();
      if (!shortProofCodeSchema.safeParse(code).success) {
        throw new Error("Short proof code generator returned an invalid code");
      }
      const alias = await this.repository.ensureProofAlias({
        code,
        proofId,
        createdAt: this.now(),
      });
      if (alias) return alias.code;
    }
    throw new ServiceError(
      "alias_unavailable",
      "A short proof link could not be allocated. Try again.",
      503,
    );
  }

  private async requireSecret(value: string, expectedHash: string, label: string) {
    if (!value) {
      throw new ServiceError("missing_secret", `Missing ${label}.`, 401);
    }
    const actual = await sha256(utf8(value));
    if (!safeStringEqual(actual, expectedHash)) {
      throw new ServiceError("invalid_secret", `Invalid ${label}.`, 401);
    }
  }
}

function safeStringEqual(left: string, right: string): boolean {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}
