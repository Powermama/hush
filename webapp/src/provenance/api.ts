import { parsePublicProof } from "./schema";

export async function fetchProof(slug: string, signal: AbortSignal) {
  const response = await fetch(`/v1/proofs/${encodeURIComponent(slug)}`, {
    signal,
    headers: { accept: "application/json" },
  });
  if (!response.ok) {
    if (response.status === 404) throw new Error("This proof does not exist.");
    throw new Error("The proof service is unavailable.");
  }
  return parsePublicProof(await response.json());
}

export async function fetchCiphertext(
  url: string,
  signal: AbortSignal,
): Promise<Uint8Array<ArrayBuffer>> {
  const response = await fetch(url, {
    signal,
    headers: { accept: "application/vnd.hush.proof+encrypted" },
  });
  if (!response.ok) throw new Error("The encrypted proof is unavailable.");
  return new Uint8Array(await response.arrayBuffer());
}
