import {
  copyArrayBuffer,
  decodeBase64Url,
  encodeBase64Url,
  sha256,
  utf8,
} from "./base64url";

export async function importP256PublicKey(rawKey: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    copyArrayBuffer(decodeBase64Url(rawKey)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
}

export async function verifyP256(
  publicKey: CryptoKey,
  signature: string,
  message: string,
): Promise<boolean> {
  return crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    copyArrayBuffer(decodeBase64Url(signature)),
    copyArrayBuffer(utf8(message)),
  );
}

export async function publicKeyFingerprint(rawKey: string): Promise<string> {
  return sha256(decodeBase64Url(rawKey));
}

export type ServiceSigningKey = {
  id: string;
  privateKey: CryptoKey;
  publicJwk: PublicServiceJwk;
  /**
   * Every public key this service has signed receipts with, by key id,
   * including the current one. A receipt is verified with the key it names,
   * so replacing the private key never breaks earlier proofs.
   */
  publicKeys: Record<string, PublicServiceJwk>;
};

export type PublicServiceJwk = {
  kty: string;
  crv?: string;
  x?: string;
  y?: string;
  alg?: string;
  ext?: boolean;
  key_ops?: string[];
};

export async function createEphemeralServiceKey(): Promise<ServiceSigningKey> {
  const pair = (await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair;
  const publicJwk = normalizePublicJwk(
    await crypto.subtle.exportKey("jwk", pair.publicKey),
  );
  const raw = await crypto.subtle.exportKey("raw", pair.publicKey);
  const fingerprint = await sha256(new Uint8Array(raw));
  const id = `hush-${fingerprint.slice(0, 16)}`;
  return { id, privateKey: pair.privateKey, publicJwk, publicKeys: { [id]: publicJwk } };
}

export async function importServiceKey(
  id: string,
  privateJwk: JsonWebKey,
): Promise<ServiceSigningKey> {
  const privateKey = await crypto.subtle.importKey(
    "jwk",
    privateJwk,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const publicJwk = normalizePublicJwk({
    kty: privateJwk.kty,
    crv: privateJwk.crv,
    x: privateJwk.x,
    y: privateJwk.y,
    ext: true,
    key_ops: ["verify"],
  });
  return { id, privateKey, publicJwk, publicKeys: { [id]: publicJwk } };
}

export async function signP256(
  privateKey: CryptoKey,
  message: string,
): Promise<string> {
  return encodeBase64Url(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      privateKey,
      copyArrayBuffer(utf8(message)),
    ),
  );
}

function normalizePublicJwk(value: JsonWebKey): PublicServiceJwk {
  if (!value.kty) throw new Error("Service public key is missing kty");
  return {
    kty: value.kty,
    crv: value.crv,
    x: value.x,
    y: value.y,
    alg: value.alg,
    ext: value.ext,
    key_ops: value.key_ops,
  };
}
