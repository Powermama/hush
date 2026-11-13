import type { ReserveProofInput, ServiceReceipt } from "../contracts/proof";

export function canonicalEnrollmentRequest(
  challengeId: string,
  publicKey: string,
  nonce: string,
): string {
  return ["hush-enroll-v1", challengeId, nonce, publicKey].join("\n");
}

export function canonicalProofRequest(
  input: ReserveProofInput,
  challengeNonce: string,
): string {
  return [
    "hush-proof-v1",
    input.proofId,
    input.challengeId,
    challengeNonce,
    input.installationId,
    input.commitment,
    input.ciphertextSha256,
    String(input.ciphertextSize),
    new Date(input.expiresAt).toISOString(),
    String(input.assuranceLevel),
  ].join("\n");
}

export function canonicalReceipt(receipt: ServiceReceipt): string {
  return [
    "hush-receipt-v1",
    receipt.keyId,
    receipt.proofId,
    receipt.slug,
    receipt.commitment,
    receipt.ciphertextSha256,
    String(receipt.ciphertextSize),
    String(receipt.assuranceLevel),
    receipt.createdAt,
    receipt.expiresAt,
  ].join("\n");
}
