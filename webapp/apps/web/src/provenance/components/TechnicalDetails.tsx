import type { VerifiedProof } from "../crypto";

export function TechnicalDetails({ proof }: { proof: VerifiedProof }) {
  const { receipt } = proof.metadata;
  const revision = proof.manifest.revision;
  return (
    <details className="proof-technical">
      <summary className="flex cursor-pointer list-none items-center justify-between gap-4 font-bold">
        Technical details
        <span className="proof-chevron" aria-hidden="true">⌄</span>
      </summary>
      <dl className="mt-5 grid gap-4 text-xs sm:grid-cols-2">
        <Detail label="Proof ID" value={receipt.proofId} mono />
        <Detail label="Assurance" value={`Level ${receipt.assuranceLevel}`} />
        <Detail label="Receipt signer" value={receipt.keyId} mono />
        <Detail label="Signature" value="ECDSA P-256 / SHA-256" />
        <Detail label="Content commitment" value={receipt.commitment} mono />
        <Detail label="Ciphertext digest" value={receipt.ciphertextSha256} mono />
        <Detail label="Created" value={formatDate(receipt.createdAt)} />
        <Detail label="Expires" value={formatDate(receipt.expiresAt)} />
        {revision ? (
          <Detail label="Previous proof" value={revision.parentProofId} mono />
        ) : null}
        {revision ? (
          <Detail label="Previous commitment" value={revision.parentCommitment} mono />
        ) : null}
      </dl>
      <p className="mt-5 border-t border-black/8 pt-4 text-xs leading-5 text-muted">
        This verifies a signed hush origin and edit record. It does not prove legal
        identity, factual accuracy, or biological liveness.
      </p>
    </details>
  );
}

function Detail({
  label,
  value,
  mono = false,
}: {
  label: string;
  value: string;
  mono?: boolean;
}) {
  return (
    <div className="min-w-0">
      <dt className="font-medium text-muted">{label}</dt>
      <dd className={`mt-1 break-all text-ink ${mono ? "font-mono" : ""}`}>{value}</dd>
    </div>
  );
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}
