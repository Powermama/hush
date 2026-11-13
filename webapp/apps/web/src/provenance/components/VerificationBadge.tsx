export function VerificationBadge({
  tone,
  title,
  detail,
}: {
  tone: "valid" | "warning" | "invalid" | "neutral";
  title: string;
  detail: string;
}) {
  const treatment = {
    valid: { icon: "✓", iconClass: "bg-success text-white" },
    warning: { icon: "!", iconClass: "bg-amber-500 text-white" },
    invalid: { icon: "×", iconClass: "bg-red-500 text-white" },
    neutral: { icon: "…", iconClass: "bg-black/10 text-muted" },
  }[tone];
  return (
    <div className="proof-verification" data-tone={tone} role="status" aria-live="polite">
      <span
        className={`proof-verification-symbol ${treatment.iconClass}`}
        aria-hidden="true"
      >
        {treatment.icon}
      </span>
      <div>
        <h1>{title}</h1>
        <p>{detail}</p>
      </div>
    </div>
  );
}

