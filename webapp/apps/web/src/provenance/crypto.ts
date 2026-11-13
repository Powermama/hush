import { canonicalReceipt } from "../../shared/provenance/canonical";
import {
  encryptedProofPackageSchema,
  proofManifestSchema,
  type ProofManifest,
  type PublicProof,
} from "./schema";

export type VerifiedProof = {
  manifest: ProofManifest;
  metadata: PublicProof;
  ciphertext: Uint8Array<ArrayBuffer>;
};

export async function verifyAndDecryptProof(input: {
  metadata: PublicProof;
  ciphertext: Uint8Array<ArrayBuffer>;
  decryptionKey: string;
}): Promise<VerifiedProof> {
  const receiptKey = await crypto.subtle.importKey(
    "jwk",
    input.metadata.servicePublicKey,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const receiptValid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    receiptKey,
    decodeBase64Url(input.metadata.receiptSignature),
    utf8(canonicalReceipt(input.metadata.receipt)),
  );
  if (!receiptValid) throw new Error("The hush service receipt is invalid.");

  const ciphertextDigest = await sha256(input.ciphertext);
  if (ciphertextDigest !== input.metadata.receipt.ciphertextSha256) {
    throw new Error("The encrypted proof was modified.");
  }
  if (input.ciphertext.byteLength !== input.metadata.receipt.ciphertextSize) {
    throw new Error("The encrypted proof has an unexpected size.");
  }

  const combined = input.ciphertext;
  if (combined.byteLength < 29) throw new Error("The encrypted proof is incomplete.");
  const key = await crypto.subtle.importKey(
    "raw",
    decodeBase64Url(input.decryptionKey),
    "AES-GCM",
    false,
    ["decrypt"],
  );
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: combined.slice(0, 12) },
    key,
    combined.slice(12),
  );
  const proofPackage = encryptedProofPackageSchema.parse(
    JSON.parse(new TextDecoder().decode(decrypted)) as unknown,
  );
  const manifestBytes = decodeBase64Url(proofPackage.manifest);
  const manifestCommitment = await sha256(manifestBytes);
  if (manifestCommitment !== input.metadata.receipt.commitment) {
    throw new Error("The signed message does not match the hush receipt.");
  }
  const installationKey = await crypto.subtle.importKey(
    "raw",
    decodeBase64Url(proofPackage.installationPublicKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const manifestValid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    installationKey,
    decodeBase64Url(proofPackage.manifestSignature),
    manifestBytes,
  );
  if (!manifestValid) throw new Error("The message signature is invalid.");

  const manifest = proofManifestSchema.parse(
    JSON.parse(new TextDecoder().decode(manifestBytes)) as unknown,
  );
  if (manifest.proofId !== input.metadata.receipt.proofId) {
    throw new Error("The proof identifier does not match.");
  }
  if (
    new Date(manifest.expiresAt).getTime() !==
    new Date(input.metadata.receipt.expiresAt).getTime()
  ) {
    throw new Error("The proof expiry does not match.");
  }
  return { manifest, metadata: input.metadata, ciphertext: input.ciphertext };
}

export function readDecryptionKey(): string | null {
  const fragment = new URLSearchParams(window.location.hash.slice(1));
  const key = fragment.get("k");
  return key && /^[A-Za-z0-9_-]{43}$/.test(key) ? key : null;
}

export function decodeBase64Url(value: string): Uint8Array<ArrayBuffer> {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

export function decodeBase64(value: string): Uint8Array<ArrayBuffer> {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function utf8(value: string): Uint8Array<ArrayBuffer> {
  return new TextEncoder().encode(value);
}

async function sha256(value: Uint8Array<ArrayBuffer>): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", value);
  const bytes = new Uint8Array(digest);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
