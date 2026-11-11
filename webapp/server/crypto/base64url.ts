export function encodeBase64Url(value: ArrayBuffer | Uint8Array): string {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  return Buffer.from(bytes).toString("base64url");
}

export function decodeBase64Url(value: string): Uint8Array {
  return Uint8Array.from(Buffer.from(value, "base64url"));
}

export function utf8(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

export async function sha256(value: Uint8Array): Promise<string> {
  return encodeBase64Url(
    await crypto.subtle.digest("SHA-256", copyArrayBuffer(value)),
  );
}

export function randomBase64Url(byteCount: number): string {
  return encodeBase64Url(crypto.getRandomValues(new Uint8Array(byteCount)));
}

export function copyArrayBuffer(value: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(value.byteLength);
  copy.set(value);
  return copy.buffer;
}
