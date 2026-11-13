const proofSteps = [
  {
    title: "Voice captured locally",
    detail: "18 seconds transcribed on the author's Mac",
  },
  {
    title: "Refined by local AI",
    detail: "Business persona applied without a cloud model",
  },
  {
    title: "Signed and encrypted",
    detail: "The exact final wording is tamper evident",
  },
] as const;

export function VerifiedMessagePreview({ className = "" }: { className?: string }) {
  return (
    <article
      className={`mx-auto max-w-[920px] overflow-hidden rounded-[2rem] border border-black/8 bg-white shadow-[0_24px_80px_rgb(31_32_30/0.08)] ${className}`}
      aria-label="Verified Message preview"
    >
      <div className="p-5 sm:p-7">
        <div className="flex items-start gap-3">
          <span className="grid size-9 shrink-0 place-items-center rounded-full bg-success text-sm font-bold text-white" aria-hidden="true">
            ✓
          </span>
          <div>
            <p className="text-sm font-bold">Verified hush message</p>
            <p className="mt-1 text-xs leading-5 text-muted">
              The signed voice capture and edit record matches.
            </p>
          </div>
        </div>

        <p className="mt-6 max-w-[760px] text-pretty font-display text-[clamp(1.7rem,4vw,2.55rem)] font-semibold leading-[1.22] tracking-[-0.03em]">
          Quick update: the new onboarding flow is ready for review.
        </p>

        <div className="mt-6 flex flex-wrap items-center gap-x-2 gap-y-1 border-t border-black/8 pt-4 text-xs text-muted">
          <span className="font-semibold text-ink">@clemoji</span>
          <span aria-hidden="true">·</span>
          <span>Created from voice</span>
          <span aria-hidden="true">·</span>
          <span>Local AI disclosed</span>
        </div>
      </div>

      <div className="grid border-t border-black/8 lg:grid-cols-[1.08fr_0.92fr]">
        <div className="p-5 sm:p-7">
          <h3 className="font-display text-xl font-bold tracking-tight">
            How this message was made
          </h3>
          <p className="mt-1 text-sm leading-5 text-muted">
            The complete history recorded in this signed proof.
          </p>
          <ol className="mt-6 space-y-0">
            {proofSteps.map((step, index) => (
              <li className="relative flex gap-4 pb-6 last:pb-0" key={step.title}>
                {index < proofSteps.length - 1 ? (
                  <span className="absolute left-[15px] top-8 h-[calc(100%-0.7rem)] w-px bg-black/10" aria-hidden="true" />
                ) : null}
                <span className="relative z-10 grid size-8 shrink-0 place-items-center rounded-full border border-black/8 bg-canvas text-xs font-bold">
                  {index + 1}
                </span>
                <div className="pt-1">
                  <p className="text-sm font-bold">{step.title}</p>
                  <p className="mt-1 text-xs leading-5 text-muted">{step.detail}</p>
                </div>
              </li>
            ))}
          </ol>
        </div>

        <div className="border-t border-black/8 bg-black/[0.018] p-5 sm:p-7 lg:border-l lg:border-t-0">
          <h3 className="font-display text-xl font-bold tracking-tight">
            Signed wording
          </h3>
          <p className="mt-1 text-sm leading-5 text-muted">
            The source and exact final message are bound to this proof.
          </p>
          <div className="mt-6 rounded-2xl border border-black/8 bg-white p-5">
            <p className="font-mono text-[10px] font-semibold uppercase tracking-[0.12em] text-soft">
              Original transcript
            </p>
            <p className="mt-3 text-sm leading-6 text-muted">
              Quick update the new onboarding flow is ready for review
            </p>
            <div className="mt-5 border-t border-black/8 pt-4">
              <p className="font-mono text-[10px] font-semibold uppercase tracking-[0.12em] text-soft">
                Local refinement
              </p>
              <p className="mt-2 text-xs leading-5 text-muted">
                Punctuation added. Wording preserved.
              </p>
            </div>
          </div>
        </div>
      </div>

      <div className="flex items-center gap-2 border-t border-black/8 px-5 py-4 text-[11px] leading-5 text-muted sm:px-8">
        <LockIcon />
        Proof contents decrypt in this browser. hush never receives the message key.
      </div>
    </article>
  );
}

export function ProofDisclaimer() {
  return (
    <p className="mx-auto mt-6 max-w-3xl text-center text-xs leading-5 text-soft">
      * Verifies the signed capture and edit record, not identity, accuracy, or
      liveness.
    </p>
  );
}

function LockIcon() {
  return (
    <svg className="size-3.5 shrink-0 text-soft" viewBox="0 0 16 16" fill="none" aria-hidden="true">
      <rect x="3" y="7" width="10" height="7" rx="2" stroke="currentColor" strokeWidth="1.4" />
      <path d="M5.5 7V5.5a2.5 2.5 0 0 1 5 0V7" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
    </svg>
  );
}
