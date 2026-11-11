import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { ReactionPills } from "./workflow/ReactionPills";

type WorkflowState =
  | "ready"
  | "listening"
  | "processing"
  | "signing"
  | "drafted"
  | "inserted";

const polishedText =
  "quick update: the new onboarding flow is ready for review ✨ if you spot anything, send feedback my way today\n\n-typed with hush: behu.sh/s/clemoji";

const stages: Array<{
  id: Exclude<WorkflowState, "ready" | "drafted">;
  shortLabel: string;
  label: string;
}> = [
  { id: "listening", shortLabel: "Capture", label: "Voice captured locally" },
  { id: "processing", shortLabel: "Refine", label: "Text refined locally" },
  { id: "signing", shortLabel: "Verify", label: "Proof secured locally" },
  { id: "inserted", shortLabel: "Insert", label: "Result inserted locally" },
];

type SelectableStage = Exclude<WorkflowState, "ready" | "drafted">;

const stageContinuation: Record<
  SelectableStage,
  Array<{ delay: number; state: WorkflowState }>
> = {
  listening: [
    { delay: 1500, state: "processing" },
    { delay: 2600, state: "signing" },
    { delay: 3700, state: "drafted" },
    { delay: 5100, state: "inserted" },
  ],
  processing: [
    { delay: 1100, state: "signing" },
    { delay: 2200, state: "drafted" },
    { delay: 3600, state: "inserted" },
  ],
  signing: [
    { delay: 1100, state: "drafted" },
    { delay: 2500, state: "inserted" },
  ],
  inserted: [],
};

const stageRestartDelay: Record<SelectableStage, number> = {
  listening: 8700,
  processing: 7200,
  signing: 6100,
  inserted: 3600,
};

export function LocalWorkflowDemo() {
  const demo = useRef<HTMLDivElement>(null);
  const visible = useRef(false);
  const timers = useRef<Array<ReturnType<typeof setTimeout>>>([]);
  const [state, setState] = useState<WorkflowState>("ready");
  const [cycle, setCycle] = useState(0);
  const [scene, setScene] = useState<0 | 1 | 2>(0);
  const [notificationVisible, setNotificationVisible] = useState(false);
  const [composerFocused, setComposerFocused] = useState(false);

  const clearTimers = useCallback(() => {
    timers.current.forEach(clearTimeout);
    timers.current = [];
  }, []);

  useEffect(() => clearTimers, [clearTimers]);

  const play = useCallback(() => {
    clearTimers();
    setState("ready");
    setScene(0);
    setNotificationVisible(false);
    setComposerFocused(false);
    setCycle((value) => value + 1);

    timers.current = [
      setTimeout(() => setNotificationVisible(true), 500),
      setTimeout(() => setScene(1), 1300),
      setTimeout(() => {
        setScene(2);
        setComposerFocused(true);
      }, 2000),
      setTimeout(() => setState("listening"), 2500),
      setTimeout(() => setState("processing"), 4000),
      setTimeout(() => setState("signing"), 5100),
      setTimeout(() => setState("drafted"), 6200),
      setTimeout(() => setState("inserted"), 7600),
      setTimeout(() => {
        if (visible.current) play();
      }, 11200),
    ];
  }, [clearTimers]);

  const showStage = useCallback(
    (next: SelectableStage) => {
      clearTimers();
      setScene(2);
      setNotificationVisible(true);
      setComposerFocused(true);
      setState(next);
      setCycle((value) => value + 1);

      timers.current = [
        ...stageContinuation[next].map(({ delay, state: nextState }) =>
          setTimeout(() => setState(nextState), delay),
        ),
        setTimeout(() => {
          if (visible.current) play();
        }, stageRestartDelay[next]),
      ];
    },
    [clearTimers, play],
  );

  useEffect(() => {
    const element = demo.current;
    if (!element) return;

    const reduceMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;
    const observer = new IntersectionObserver(
      ([entry]) => {
        visible.current = entry.isIntersecting;
        if (!entry.isIntersecting) {
          clearTimers();
          return;
        }
        if (reduceMotion) {
          setScene(2);
          setNotificationVisible(true);
          setComposerFocused(true);
          setState("inserted");
        } else {
          play();
        }
      },
      { threshold: 0.1 },
    );

    observer.observe(element);
    return () => observer.disconnect();
  }, [clearTimers, play]);

  const activeStage: SelectableStage | "ready" =
    state === "drafted" ? "inserted" : state;

  return (
    <div
      ref={demo}
      data-testid="local-workflow-demo"
      className="relative"
    >
      <div className="overflow-hidden rounded-[30px] border border-black/12 bg-[#dce6ee] shadow-[0_2px_5px_rgb(0_0_0/0.04),0_36px_90px_rgb(31_32_30/0.14)]">
        <div className="relative flex h-8 items-center border-b border-white/30 bg-white/68 px-3 text-[9px] font-medium text-ink backdrop-blur-2xl sm:px-4">
          <div className="flex items-center gap-3">
            <span className="font-bold">Teamspace</span>
            <span className="hidden text-muted sm:inline">File</span>
            <span className="hidden text-muted sm:inline">Edit</span>
            <span className="hidden text-muted sm:inline">View</span>
          </div>
          <span className="absolute left-1/2 -translate-x-1/2 text-muted">
            Tue 10:42
          </span>
          <div className="ml-auto flex items-center gap-2.5 text-muted">
            <HushMenuIcon />
            <WifiIcon />
            <BatteryIcon />
            <span className="hidden sm:inline">Wed 5. Aug 20:06</span>
          </div>
        </div>

        <div className="workflow-desktop relative min-h-[590px] overflow-hidden p-3 pb-28 sm:p-7 sm:pb-28 lg:min-h-[550px] lg:p-8 lg:pb-8">
          <div className="workflow-desktop-glow" aria-hidden="true" />

          <div className="relative z-[1] mx-auto max-w-[900px] overflow-hidden rounded-[22px] border border-black/10 bg-white shadow-[0_24px_70px_rgb(31_32_30/0.2)]">
            <div className="relative flex h-11 items-center border-b border-black/8 bg-[#f5f5f7]/95 px-4">
              <div className="flex gap-2" aria-hidden="true">
                <span className="size-2.5 rounded-full bg-[#ff5f57]" />
                <span className="size-2.5 rounded-full bg-[#febc2e]" />
                <span className="size-2.5 rounded-full bg-[#28c840]" />
              </div>
              <span className="absolute left-1/2 -translate-x-1/2 text-[11px] font-semibold text-muted">
                Teamspace
              </span>
            </div>

            <div className="grid min-h-[390px] sm:grid-cols-[145px_minmax(0,1fr)]">
              <aside className="hidden bg-[#241327] px-3 py-4 text-white sm:block">
                <div className="px-2 text-[12px] font-bold">hush team</div>
                <div className="mt-1 px-2 text-[9px] text-white/40">clemoji</div>
                <p className="mt-7 px-2 text-[9px] font-bold uppercase tracking-[0.12em] text-white/35">
                  Channels
                </p>
                <div className="mt-2 space-y-0.5 text-[11px] text-white/55">
                  <div
                    className={`rounded-lg px-2.5 py-1.5 transition-colors duration-500 ${
                      scene === 0 ? "bg-white/12 font-semibold text-white" : ""
                    }`}
                  >
                    # general
                  </div>
                  <div
                    className={`flex items-center rounded-lg px-2.5 py-1.5 transition-colors duration-500 ${
                      scene > 0 ? "bg-white/12 font-semibold text-white" : ""
                    }`}
                  >
                    <span># product</span>
                    {scene === 0 && notificationVisible && (
                      <span
                        className="workflow-notification-pop ml-auto grid size-4 place-items-center rounded-full bg-[#c9b8ff] text-[8px] font-bold text-[#332b52]"
                        aria-hidden="true"
                      >
                        1
                      </span>
                    )}
                  </div>
                  <div className="rounded-lg px-2.5 py-1.5"># launches</div>
                  <div className="rounded-lg px-2.5 py-1.5"># random</div>
                </div>
              </aside>

              <div
                key={scene === 0 ? "general" : "product"}
                className="workflow-scene-enter flex min-w-0 flex-col bg-white"
              >
                <div className="flex items-center gap-2 border-b border-black/7 px-5 py-3.5 sm:px-6">
                  <h3 className="text-[15px] font-bold text-ink">
                    {scene === 0 ? "# general" : "# product"}
                  </h3>
                  <span className="text-[9px] text-soft">
                    {scene === 0 ? "24 members" : "8 members"}
                  </span>
                  {scene > 0 && (
                    <span className="ml-auto rounded-full bg-[#c9b8ff]/20 px-2.5 py-1 text-[9px] font-semibold text-[#7667d7]">
                      Team update
                    </span>
                  )}
                  {scene === 0 && notificationVisible && (
                    <span
                      className="workflow-notification-pop ml-auto rounded-full bg-[#c9b8ff]/25 px-2.5 py-1 text-[9px] font-semibold text-[#685b8b]"
                      aria-label="1 unread message in product"
                    >
                      Product +1
                    </span>
                  )}
                </div>
                <div className="flex flex-1 flex-col gap-5 px-5 py-6 sm:px-7 sm:py-7">
                  {scene === 0 ? (
                    <>
                      <ChatMessage initials="LS" name="Luca" time="10:31">
                        Morning! I moved today&apos;s stand-up notes into the shared folder.
                      </ChatMessage>
                      <ChatMessage initials="NP" name="Nina" time="10:34">
                        Nice. I&apos;ll add the launch checklist before lunch.
                      </ChatMessage>
                      <ChatMessage initials="OM" name="Omar" time="10:37">
                        Perfect, the latest build is looking stable here too.
                      </ChatMessage>
                    </>
                  ) : (
                    <>
                      <ChatMessage initials="MK" name="Maya" time="10:39">
                        The new onboarding flow is looking great. Share the final version when it is ready.
                      </ChatMessage>
                      {state === "inserted" && (
                        <ChatMessage initials="CK" name="Clemoji" time="now" current>
                          {polishedText}
                        </ChatMessage>
                      )}
                    </>
                  )}
                </div>
                <div
                  key={cycle}
                  className={`mx-5 mb-4 flex items-center gap-2 rounded-xl border px-3.5 text-[11px] text-soft transition-[border-color,box-shadow,padding] duration-500 sm:mx-6 ${
                    state === "drafted" ? "py-3" : "py-2.5"
                  } ${
                    state === "ready"
                      ? "workflow-composer-focus border-black/10"
                      : state === "listening"
                        ? "border-[#9ec9ff]/70 ring-2 ring-[#9ec9ff]/15"
                        : "border-black/10"
                  }`}
                >
                  <span className="text-base leading-none">＋</span>
                  <span className="flex min-w-0 flex-1 items-center">
                    {state === "drafted" ? (
                      <span
                        className="workflow-draft-arrive max-h-12 overflow-hidden whitespace-pre-line text-[10px] leading-4 text-ink"
                        data-testid="workflow-composer-draft"
                      >
                        {polishedText.replace("\n\n", "  ·  ")}
                      </span>
                    ) : composerFocused && state !== "inserted" ? (
                      <span className="workflow-composer-caret" aria-hidden="true" />
                    ) : (
                      <span>Message {scene === 0 ? "#general" : "#product"}</span>
                    )}
                  </span>
                  {state === "drafted" && (
                    <kbd
                      className="workflow-return-key ml-2 grid size-7 shrink-0 place-items-center rounded-lg border border-black/10 bg-stone font-mono text-[12px] font-bold text-muted shadow-sm"
                      aria-label="Press Return to send"
                    >
                      ↵
                    </kbd>
                  )}
                </div>
              </div>
            </div>
          </div>

          <ShortcutHint state={state} />
          {state !== "ready" && <HushHud state={state} />}
        </div>
      </div>

      <div className="mx-auto mt-5 flex w-fit max-w-full items-center gap-3 rounded-2xl border border-black/8 bg-white/70 p-2 shadow-[0_12px_35px_rgb(31_32_30/0.07)] backdrop-blur-xl">
        <div className="flex min-w-0 items-center gap-3">
          <span className="hidden pl-2 text-[10px] font-bold uppercase tracking-[0.14em] text-soft md:block">
            Explore
          </span>
          <div className="grid grid-cols-4 gap-1 rounded-xl bg-black/[0.045] p-1">
            {stages.map((stage) => (
              <button
                key={stage.id}
                type="button"
                aria-label={stage.label}
                aria-pressed={activeStage === stage.id}
                onClick={() => showStage(stage.id)}
                className={`rounded-[9px] px-2.5 py-2 text-[11px] font-semibold transition sm:px-3.5 ${
                  activeStage === stage.id
                    ? "bg-white text-ink shadow-sm"
                    : "text-soft hover:text-muted"
                }`}
              >
                {stage.shortLabel}
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function ShortcutHint({ state }: { state: WorkflowState }) {
  return (
    <div
      className={`absolute bottom-9 left-5 z-[3] flex items-center gap-2.5 transition-all duration-500 ease-out sm:left-8 ${
        state === "listening"
          ? "translate-y-0 opacity-100"
          : "pointer-events-none translate-y-2 opacity-0"
      }`}
      aria-hidden={state !== "listening"}
    >
      <kbd className="workflow-fn-key grid size-11 place-items-center rounded-[13px] border border-white/70 bg-white/75 font-mono text-[13px] font-bold text-ink shadow-[0_10px_25px_rgb(31_32_30/0.16),inset_0_-3px_0_rgb(0_0_0/0.08)] backdrop-blur-xl">
        fn
      </kbd>
      <span className="rounded-full border border-white/50 bg-white/65 px-3 py-1.5 text-[10px] font-semibold text-muted backdrop-blur-xl">
        hold to talk
      </span>
    </div>
  );
}

function ChatMessage({
  initials,
  name,
  time,
  current = false,
  children,
}: {
  initials: string;
  name: string;
  time: string;
  current?: boolean;
  children: ReactNode;
}) {
  return (
    <div
      className={`flex gap-3 ${current ? "workflow-message-arrive" : ""}`}
      data-testid={current ? "workflow-sent-message" : undefined}
    >
      <span
        className={`grid size-9 shrink-0 place-items-center rounded-[10px] text-[11px] font-bold ${
          current ? "bg-ink text-white" : "bg-[#e4def4] text-[#685b8b]"
        }`}
      >
        {initials}
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2 leading-4">
          <span className="text-[13px] font-bold text-ink">{name}</span>
          <span className="text-[9px] text-soft">{time}</span>
        </div>
        <div className="mt-0.5 whitespace-pre-line text-[14px] leading-5 text-ink sm:text-[15px] sm:leading-[1.4]">
          {children}
        </div>
        {current && (
          <ReactionPills />
        )}
      </div>
    </div>
  );
}

function HushHud({ state }: { state: WorkflowState }) {
  const label =
    state === "listening"
      ? "Listening"
      : state === "processing"
        ? "Processing"
        : state === "signing"
          ? "Securing proof"
          : state === "drafted"
            ? "24 words"
          : state === "inserted"
            ? "Sent"
            : "Ready when you are";
  const detail =
    state === "listening"
      ? "0:02"
      : state === "processing"
        ? "on-device"
        : state === "signing"
          ? "on this Mac"
          : state === "drafted"
            ? "inserted into composer"
          : state === "inserted"
            ? "verified by hush"
            : "hold fn to talk";

  return (
    <div
      className="workflow-hud-enter absolute bottom-7 left-1/2 z-[4] flex h-[72px] w-[calc(100%-3rem)] max-w-[380px] -translate-x-1/2 items-center rounded-[22px] border border-white/75 bg-white/72 px-[15px] shadow-[0_18px_50px_rgb(31_32_30/0.18),inset_0_0_0_0.5px_rgb(0_0_0/0.06)] backdrop-blur-2xl sm:bottom-9"
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

function HushBadge({ state }: { state: WorkflowState }) {
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

function HushMenuIcon() {
  const heights = [5, 10, 14, 9, 5];
  return (
    <span className="flex h-3 items-center gap-px" aria-hidden="true">
      {heights.map((height, index) => (
        <span
          key={index}
          className="w-[1.5px] rounded-full bg-current"
          style={{ height }}
        />
      ))}
    </span>
  );
}

function WifiIcon() {
  return (
    <svg viewBox="0 0 20 16" className="h-3 w-4" aria-hidden="true">
      <path
        d="M1.7 5.4a12.5 12.5 0 0 1 16.6 0M4.7 8.6a8 8 0 0 1 10.6 0M7.7 11.7a3.5 3.5 0 0 1 4.6 0"
        fill="none"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="1.35"
      />
      <circle cx="10" cy="14.2" r="0.85" fill="currentColor" />
    </svg>
  );
}

function BatteryIcon() {
  return (
    <svg viewBox="0 0 24 12" className="h-2.5 w-5" aria-hidden="true">
      <rect
        x="1"
        y="1"
        width="19"
        height="10"
        rx="2.5"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.3"
      />
      <rect x="3" y="3" width="14" height="6" rx="1" fill="currentColor" />
      <path d="M22 4v4" stroke="currentColor" strokeLinecap="round" strokeWidth="1.5" />
    </svg>
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
