import { useEffect, useState } from "react";
import { fetchCiphertext, fetchProof } from "./api";
import {
  readDecryptionKey,
  verifyAndDecryptProof,
  type VerifiedProof,
} from "./crypto";

export type ProofVerificationState =
  | { status: "loading" }
  | { status: "valid"; proof: VerifiedProof }
  | { status: "expired" }
  | { status: "revoked" }
  | { status: "missing_key" }
  | { status: "invalid"; message: string };

export function useProofVerification(slug: string): ProofVerificationState {
  const [state, setState] = useState<ProofVerificationState>({ status: "loading" });

  useEffect(() => {
    const controller = new AbortController();
    const run = async () => {
      setState({ status: "loading" });
      try {
        const decryptionKey = readDecryptionKey();
        if (!decryptionKey) {
          setState({ status: "missing_key" });
          return;
        }
        const metadata = await fetchProof(slug, controller.signal);
        if (metadata.status === "expired") {
          setState({ status: "expired" });
          return;
        }
        if (metadata.status === "revoked") {
          setState({ status: "revoked" });
          return;
        }
        const ciphertext = await fetchCiphertext(
          metadata.ciphertextUrl,
          controller.signal,
        );
        const proof = await verifyAndDecryptProof({
          metadata,
          ciphertext,
          decryptionKey,
        });
        if (!controller.signal.aborted) setState({ status: "valid", proof });
      } catch (error) {
        if (controller.signal.aborted) return;
        setState({
          status: "invalid",
          message: error instanceof Error ? error.message : "Proof verification failed.",
        });
      }
    };
    void run();
    return () => controller.abort();
  }, [slug]);

  return state;
}
