export function FeatureAnnouncement({
  href,
  label,
  title,
  ariaLabel,
}: {
  href: string;
  label: string;
  title: string;
  ariaLabel: string;
}) {
  return (
    <a
      href={href}
      className="group inline-flex items-center gap-2 rounded-full border border-black/8 bg-black/[0.025] px-4 py-2 text-[13px] font-medium text-muted transition hover:border-black/15 hover:text-ink"
      aria-label={ariaLabel}
    >
      <span className="rounded-full bg-ink px-2 py-1 text-[10px] font-semibold uppercase tracking-[0.08em] text-white">
        {label}
      </span>
      <span className="font-semibold text-ink">{title}</span>
      <AnimatedArrow />
    </a>
  );
}

function AnimatedArrow() {
  return (
    <span
      className="relative inline-flex size-3.5 overflow-hidden text-soft"
      aria-hidden="true"
    >
      <span className="absolute inset-0 grid place-items-center transition duration-200 group-hover:translate-x-2 group-hover:opacity-0 group-focus-visible:translate-x-2 group-focus-visible:opacity-0">
        <svg viewBox="0 0 14 14" fill="none" className="size-3">
          <path d="m5 3.5 3.5 3.5L5 10.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
      <span className="absolute inset-0 grid -translate-x-2 place-items-center opacity-0 transition duration-200 group-hover:translate-x-0 group-hover:opacity-100 group-focus-visible:translate-x-0 group-focus-visible:opacity-100">
        <svg viewBox="0 0 14 14" fill="none" className="size-3.5">
          <path d="M2.5 7h8M7.5 4l3 3-3 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
    </span>
  );
}
