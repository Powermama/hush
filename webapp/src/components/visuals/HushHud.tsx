export type HushHudState = "ready" | "listening" | "processing" | "signing" | "drafted" | "inserted";
export type HushHudCopy = { label: string; detail: string };

const defaultCopy: Record<HushHudState, HushHudCopy> = {
  ready: { label: "Ready when you are", detail: "hold fn to talk" },
  listening: { label: "Listening", detail: "0:02" },
  processing: { label: "Processing", detail: "on-device" },
  signing: { label: "Securing proof", detail: "on this Mac" },
  drafted: { label: "24 words", detail: "inserted into composer" },
  inserted: { label: "Sent", detail: "verified by hush" },
};

/**
 * Web replica of the macOS recording HUD (macos/Hush/Hush/HUD/HushHUD.swift):
 * 72pt tall, the 42pt stateful badge, two stacked labels and the waveform.
 * The caller positions it through className.
 */
export function HushHud({ state, copy, className = "" }: {
  state: HushHudState;
  copy?: Partial<Record<HushHudState, HushHudCopy>>;
  className?: string;
}) {
  const { label, detail } = copy?.[state] ?? defaultCopy[state];

  return (
    <div
      className={`workflow-hud-enter flex h-[72px] max-w-[380px] items-center rounded-[22px] border border-white/75 bg-white/72 px-[15px] shadow-[0_18px_50px_rgb(31_32_30/0.18),inset_0_0_0_0.5px_rgb(0_0_0/0.06)] backdrop-blur-2xl ${className}`}
      role="status"
    >
      <div
        key={state}
        className="workflow-hud-content-enter flex w-full items-center gap-3.5"
      >
        <HushBadge state={state} />
        <div className="w-[132px] shrink-0">
          <p className="text-[14px] font-semibold leading-5 text-ink">{label}</p>
          <p className="whitespace-nowrap text-[10px] leading-4 text-muted">{detail}</p>
        </div>
        <div className="flex min-w-0 flex-1 items-center justify-end">
          {state === "signing" ? (
            <ProofSteps />
          ) : state === "drafted" || state === "inserted" ? (
            <div className="flex items-center gap-2 text-[10px] font-semibold text-muted">
              <span className="h-7 w-px bg-gradient-to-b from-transparent via-[#c9b8ff] to-transparent" />
              <span className="whitespace-nowrap">
                powered by <strong className="text-ink">hush.</strong>
              </span>
            </div>
          ) : (
            <Waveform aurora={state === "processing"} active={state !== "ready"} />
          )}
        </div>
      </div>
    </div>
  );
}

function HushBadge({ state }: { state: HushHudState }) {
  const complete = state === "drafted" || state === "inserted";
  return (
    <div
      className={`relative grid size-[42px] shrink-0 place-items-center overflow-hidden rounded-xl text-white transition-all duration-500 ${
        complete
          ? "bg-success shadow-[0_0_22px_rgb(52_199_89/0.28)]"
          : state === "processing"
            ? "workflow-aurora shadow-[0_0_24px_rgb(201_184_255/0.55)]"
            : "bg-ink"
      }`}
    >
      {complete ? (
        <svg viewBox="0 0 24 24" className="size-5" aria-hidden="true">
          <path
            d="m6.5 12.5 3.3 3.3 7.7-8"
            fill="none"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="2.5"
          />
        </svg>
      ) : state === "signing" ? (
        <LockIcon compact />
      ) : (
        <HushMark />
      )}
    </div>
  );
}

function HushMark() {
  const heights = [13, 23, 31, 21, 12];
  return (
    <span className="flex items-center gap-[2.5px]" aria-hidden="true">
      {heights.map((height, index) => (
        <span
          key={index}
          className="w-[3px] rounded-full bg-white"
          style={{ height }}
        />
      ))}
    </span>
  );
}

function Waveform({ aurora, active }: { aurora: boolean; active: boolean }) {
  const bars = [8, 15, 23, 13, 29, 18, 10, 25, 34, 17, 28, 12, 21, 9, 26, 14];
  return (
    <span className="flex h-9 items-center gap-[2.5px]" aria-hidden="true">
      {bars.map((height, index) => (
        <span
          key={index}
          className={`workflow-wave w-[2.5px] rounded-full ${
            aurora ? "workflow-aurora-bar" : "bg-ink/70"
          } ${active ? "is-active" : "opacity-20"}`}
          style={{ height, animationDelay: `${index * -70}ms` }}
        />
      ))}
    </span>
  );
}

function ProofSteps() {
  return (
    <div className="flex items-center gap-1.5" aria-hidden="true">
      {["lock", "signature", "check"].map((item, index) => (
        <span className="contents" key={item}>
          {index > 0 && <span className="h-px w-2 bg-black/10" />}
          <span
            className="workflow-proof-step grid size-6 place-items-center rounded-full border border-[#c9b8ff]/45 bg-[#c9b8ff]/10 text-[9px] font-bold text-[#7667d7]"
            style={{ animationDelay: `${index * 240}ms` }}
          >
            {index === 0 ? "⌁" : index === 1 ? "✦" : "✓"}
          </span>
        </span>
      ))}
    </div>
  );
}

function LockIcon({ compact = false }: { compact?: boolean }) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={compact ? "size-5" : "size-5 text-white/40"}
      aria-hidden="true"
    >
      <rect
        x="6"
        y="10"
        width="12"
        height="10"
        rx="3"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.7"
      />
      <path
        d="M8.5 10V7.5a3.5 3.5 0 0 1 7 0V10"
        fill="none"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.7"
      />
    </svg>
  );
}
