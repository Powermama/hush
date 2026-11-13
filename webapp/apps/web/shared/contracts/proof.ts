import { z } from "zod";

export const base64UrlSchema = z
  .string()
  .min(1)
  .max(12_000_000)
  .regex(/^[A-Za-z0-9_-]+$/);

export const identifierSchema = z.string().uuid();
export const SHORT_PROOF_CODE_LENGTH = 6;
export const shortProofCodeSchema = z
  .string()
  .length(SHORT_PROOF_CODE_LENGTH)
  .regex(/^[A-Za-z0-9_-]+$/);
export const digestSchema = base64UrlSchema.refine(
  (value) => value.length === 43,
  "Expected a SHA-256 digest",
);

export const challengePurposeSchema = z.enum(["enroll", "publish"]);

export const challengeResponseSchema = z.object({
  id: identifierSchema,
  nonce: base64UrlSchema,
  expiresAt: z.string().datetime(),
});

export const enrollInstallationSchema = z.object({
  challengeId: identifierSchema,
  publicKey: base64UrlSchema,
  signature: base64UrlSchema,
  keyKind: z.enum(["secure_enclave", "keychain", "app_attest"]),
  appVersion: z.string().min(1).max(64),
  platformVersion: z.string().min(1).max(64),
});

export const installationResponseSchema = z.object({
  id: identifierSchema,
  fingerprint: digestSchema,
  createdAt: z.string().datetime(),
});

export const reserveProofSchema = z.object({
  proofId: identifierSchema,
  challengeId: identifierSchema,
  installationId: identifierSchema,
  commitment: digestSchema,
  ciphertextSha256: digestSchema,
  ciphertextSize: z.number().int().min(1).max(8_000_000),
  expiresAt: z.string().datetime(),
  assuranceLevel: z.number().int().min(1).max(2),
  signature: base64UrlSchema,
});

export const proofReservationResponseSchema = z.object({
  id: identifierSchema,
  slug: z.string().min(16).max(64),
  uploadUrl: z.string().url(),
  uploadHeaders: z.record(z.string(), z.string()),
  completionToken: base64UrlSchema,
  revocationSecret: base64UrlSchema,
});

export const completeProofSchema = z.object({
  completionToken: base64UrlSchema,
});

export const serviceReceiptSchema = z.object({
  version: z.literal(1),
  keyId: z.string().min(1).max(128),
  proofId: identifierSchema,
  slug: z.string().min(16).max(64),
  commitment: digestSchema,
  ciphertextSha256: digestSchema,
  ciphertextSize: z.number().int().min(1),
  assuranceLevel: z.number().int().min(1).max(2),
  createdAt: z.string().datetime(),
  expiresAt: z.string().datetime(),
});

export const publicJwkSchema = z.object({
  kty: z.string(),
  crv: z.string().optional(),
  x: z.string().optional(),
  y: z.string().optional(),
  alg: z.string().optional(),
  ext: z.boolean().optional(),
  key_ops: z.array(z.string()).optional(),
});

export const completedProofResponseSchema = z.object({
  proofUrl: z.string().url(),
  receipt: serviceReceiptSchema,
  receiptSignature: base64UrlSchema,
});

export const publicProofResponseSchema = z.object({
  status: z.enum(["valid", "expired", "revoked"]),
  receipt: serviceReceiptSchema,
  receiptSignature: base64UrlSchema,
  servicePublicKey: publicJwkSchema,
  ciphertextUrl: z.string().url(),
});

export const revokeProofSchema = z.object({
  revocationSecret: base64UrlSchema,
});

export const errorResponseSchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    requestId: z.string(),
  }),
});

export type EnrollInstallationInput = z.infer<typeof enrollInstallationSchema>;
export type ReserveProofInput = z.infer<typeof reserveProofSchema>;
export type ServiceReceipt = z.infer<typeof serviceReceiptSchema>;
