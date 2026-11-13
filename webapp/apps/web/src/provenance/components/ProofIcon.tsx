export type ProofIconKind = "voice" | "text" | "cleanup" | "ai" | "manual" | "revision" | "signature" | "lock";

/** Shared symbols for the kinds of evidence in a signed record. */
export function ProofIcon({ kind }: { kind: ProofIconKind }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.65" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {kind === "voice" && <><rect x="9" y="3" width="6" height="12" rx="3" /><path d="M6 10v2a6 6 0 0 0 12 0v-2M12 18v3M9 21h6" /></>}
      {kind === "text" && <><rect x="3" y="5" width="18" height="14" rx="3" /><path d="M7 9h.01M12 9h.01M17 9h.01M7 12h.01M12 12h.01M17 12h.01M8 15h8" /></>}
      {kind === "cleanup" && <><path d="m4 15 7-7 5 5-7 7H6l-2-2zM13 6l2-2 5 5-2 2M13 20h7M4 4v4M2 6h4" /></>}
      {kind === "ai" && <><path d="m12 3 2.7 6.3L21 12l-6.3 2.7L12 21l-2.7-6.3L3 12l6.3-2.7zM20 2v4M18 4h4" /></>}
      {kind === "manual" && <><path d="m4 16 11-11a2.1 2.1 0 0 1 3 3L7 19l-4 1zM13 7l3 3M12 20h8" /></>}
      {kind === "revision" && <><path d="M5 9a8 8 0 1 1-1 8M5 4v5h5M12 8v5l3 2" /></>}
      {kind === "signature" && <><path d="m12 3 8 3v6c0 4-4 7-8 9-4-2-8-5-8-9V6z" /><path d="m8 12 3 3 5-6" /></>}
      {kind === "lock" && <><rect x="5" y="10" width="14" height="11" rx="3" /><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3" /></>}
    </svg>
  );
}
