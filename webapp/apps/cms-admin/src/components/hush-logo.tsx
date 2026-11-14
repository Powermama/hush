// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { cn } from "@/lib/utils";

/** The hush mark (public/favicon.svg) and name. */
export function HushLogo({ className, withName = true }: { className?: string; withName?: boolean }) {
  return (
    <span className={cn("inline-flex items-center gap-2.5", className)}>
      <svg viewBox="0 0 64 64" aria-hidden="true" className="size-7 shrink-0">
        <rect width="64" height="64" rx="15" ry="15" fill="#1F201E" />
        <g fill="none" stroke="#F8F8F6" strokeWidth="7" strokeLinecap="round">
          <path d="M14.75 25.2v13.6" /><path d="M26.25 12v40" /><path d="M37.75 20v24" /><path d="M49.25 27.2v9.6" />
        </g>
      </svg>
      {withName && <span className="text-[15px] font-semibold tracking-[-0.01em]">hush</span>}
    </span>
  );
}
