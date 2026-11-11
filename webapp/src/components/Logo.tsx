export function Logo({ href = "#top" }: { href?: string }) {
  return (
    <a
      href={href}
      className="flex items-center gap-2.5 rounded-md font-display text-lg font-bold tracking-tight focus-visible:outline-2 focus-visible:outline-offset-4"
      aria-label="hush home"
    >
      <span className="grid size-8 place-items-center rounded-[10px] bg-ink text-white">
        <svg viewBox="0 0 24 24" className="size-4" aria-hidden="true">
          <path
            d="M4 10v4M9.3 6v12M14.7 8.5v7M20 10.5v3"
            fill="none"
            stroke="currentColor"
            strokeLinecap="round"
            strokeWidth="2.7"
          />
        </svg>
      </span>
      <span className="logo-wordmark">hush<span className="text-ink">.</span></span>
    </a>
  );
}
