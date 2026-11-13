import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type PointerEvent,
} from "react";

const raw =
  "um so basically i wanted to like follow up on our chat from tuesday and uh see if you had time to look at the proposal i sent over last week no rush tho";

const fillers = new Set(["um", "uh", "like", "basically", "tho"]);

const refinements = {
  email: {
    label: "Email",
    model: "Qwen 3 · 4B",
    text: "Hi Sarah,\n\nI wanted to follow up on our conversation from Tuesday and see whether you’ve had a chance to review the proposal I sent over last week.\n\nNo rush at all. Looking forward to your thoughts.\n\nBest,\nAlex",
  },
  linkedin: {
    label: "LinkedIn",
    model: "Qwen 3 · 4B",
    text: "The best follow-ups aren’t pushy. They’re present.\n\nLast week I sent a proposal I genuinely believe in. Today I sent one line: “No rush. Curious what you think.”\n\nConfidence isn’t chasing. It’s trusting your work enough to nudge.",
  },
  casual: {
    label: "Casual",
    model: "Apple Intelligence",
    text: "hey! did you get a chance to look at that proposal from last week? no stress either way",
  },
  cleanup: {
    label: "Clean up",
    model: "Qwen 3 · 4B",
    text: "I wanted to follow up on our chat from Tuesday and see if you had time to look at the proposal I sent over last week. No rush, though.",
  },
} as const;

type Refinement = keyof typeof refinements;
type Mode = "idle" | "listening" | "raw" | "refining" | "refined";

export function ProductDemo() {
  const stage = useRef<HTMLDivElement>(null);
  const streamTimer = useRef<ReturnType<typeof setInterval> | undefined>(
    undefined,
  );
  const typeTimer = useRef<ReturnType<typeof setInterval> | undefined>(
    undefined,
  );
  const typed = useRef(0);
  const downAt = useRef(0);
  const toggleStop = useRef(false);
  const modeRef = useRef<Mode>("idle");
  const [mode, setModeState] = useState<Mode>("idle");
  const [text, setText] = useState("");
  const [selected, setSelected] = useState<Refinement>();
  const [meta, setMeta] = useState("");

  const setMode = useCallback((next: Mode) => {
    modeRef.current = next;
    setModeState(next);
  }, []);

  const clearTimers = useCallback(() => {
    clearInterval(streamTimer.current);
    clearInterval(typeTimer.current);
  }, []);

  const reset = useCallback(() => {
    clearTimers();
    typed.current = 0;
    setMode("idle");
    setText("");
    setSelected(undefined);
    setMeta("");
  }, [clearTimers, setMode]);

  const stopRecording = useCallback(() => {
    if (modeRef.current !== "listening") return;
    clearInterval(streamTimer.current);
    if (typed.current > 12) {
      setText(raw.slice(0, typed.current));
      setMode("raw");
    } else {
      reset();
    }
  }, [reset, setMode]);

  const startRecording = useCallback(() => {
    if (modeRef.current === "listening") return;
    clearTimers();
    typed.current = 0;
    setText("");
    setSelected(undefined);
    setMeta("");
    setMode("listening");
    streamTimer.current = setInterval(() => {
      typed.current += 1 + Math.floor(Math.random() * 3);
      if (typed.current >= raw.length) {
        typed.current = raw.length;
        stopRecording();
        return;
      }
      setText(raw.slice(0, typed.current));
    }, 34);
  }, [clearTimers, setMode, stopRecording]);

  useEffect(() => {
    const onPointerUp = () => {
      if (modeRef.current !== "listening") return;
      const held = Date.now() - downAt.current;
      if (toggleStop.current || held >= 380) {
        toggleStop.current = false;
        stopRecording();
      }
    };
    const onKeyDown = (event: KeyboardEvent) => {
      const rect = stage.current?.getBoundingClientRect();
      const visible =
        rect && rect.top < window.innerHeight && rect.bottom > 0;
      if (
        event.code !== "Space" ||
        event.repeat ||
        !visible ||
        /INPUT|TEXTAREA/.test(document.activeElement?.tagName ?? "")
      )
        return;
      event.preventDefault();
      downAt.current = Date.now();
      startRecording();
    };
    const onKeyUp = (event: KeyboardEvent) => {
      if (event.code === "Space") stopRecording();
    };

    window.addEventListener("pointerup", onPointerUp);
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    return () => {
      window.removeEventListener("pointerup", onPointerUp);
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      clearTimers();
    };
  }, [clearTimers, startRecording, stopRecording]);

  const handlePointerDown = (event: PointerEvent<HTMLButtonElement>) => {
    event.preventDefault();
    if (modeRef.current !== "listening") {
      downAt.current = Date.now();
      startRecording();
    } else {
      toggleStop.current = true;
    }
  };

  const refine = (key: Refinement) => {
    clearInterval(typeTimer.current);
    const refinement = refinements[key];
    const seconds = (0.6 + Math.random() * 0.5).toFixed(1);
    let index = 0;
    setSelected(key);
    setText("");
    setMeta("Refining locally…");
    setMode("refining");
    typeTimer.current = setInterval(() => {
      index += 1 + Math.floor(Math.random() * 2);
      setText(refinement.text.slice(0, index));
      if (index < refinement.text.length) return;
      clearInterval(typeTimer.current);
      setText(refinement.text);
      setMeta(
        `Refined on-device · ${refinement.model} · ${seconds}s · 0 bytes uploaded`,
      );
      setMode("refined");
    }, 16);
  };

  const renderText = () => {
    if (mode === "idle")
      return (
        <span className="text-soft">
          Your words land here. Hold the orb and talk…
        </span>
      );
    if (mode === "raw")
      return text.split(" ").map((word, index) => {
        const filler = fillers.has(word.replace(/[^a-z]/gi, "").toLowerCase());
        return (
          <span
            className={filler ? "text-soft line-through" : ""}
            key={`${word}-${index}`}
          >
            {index ? " " : ""}
            {word}
          </span>
        );
      });
    return (
      <>
        {text}
        {(mode === "listening" || mode === "refining") && (
          <span className="caret" />
        )}
      </>
    );
  };

  return (
    <div id="demo" className="mx-auto mt-[76px] max-w-[700px]">
      <div
        ref={stage}
        className="mb-11 flex flex-col items-center gap-5"
      >
        <button
          data-testid="microphone"
          className={`orb relative grid size-[118px] place-items-center rounded-full focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ink ${
            mode === "listening" ? "is-listening" : ""
          }`}
          type="button"
          aria-label={
            mode === "listening" ? "Stop listening demo" : "Start listening demo"
          }
          aria-pressed={mode === "listening"}
          onPointerDown={handlePointerDown}
        >
          <span className="orb-ripple" />
          <span className="orb-ripple orb-ripple-2" />
          <span className="orb-surface" />
          <svg
            viewBox="0 0 24 24"
            className="relative z-10 size-7 text-white"
            aria-hidden="true"
          >
            <path
              d="M8.5 5a3.5 3.5 0 0 1 7 0v7a3.5 3.5 0 0 1-7 0V5Zm-3 6v1a6.5 6.5 0 0 0 13 0v-1M12 18.5V22"
              fill="none"
              stroke="currentColor"
              strokeLinecap="round"
              strokeWidth="1.8"
            />
          </svg>
        </button>
        <span className="whitespace-nowrap text-xs font-medium text-soft">
          {mode === "listening" ? (
            "Listening… release to refine"
          ) : (
            "Hold to speak"
          )}
        </span>
      </div>
      <div className="overflow-hidden rounded-[26px] border border-black/8 bg-white text-left shadow-[0_2px_6px_rgb(0_0_0/0.05),0_32px_80px_rgb(0_0_0/0.1)]">
        <div className="flex items-center gap-2 border-b border-black/8 bg-[#f5f5f7] px-[18px] py-[13px]">
          <span className="size-[11px] rounded-full bg-[#ff5f57]" />
          <span className="size-[11px] rounded-full bg-[#febc2e]" />
          <span className="size-[11px] rounded-full bg-[#28c840]" />
          <span className="ml-2 text-xs font-medium text-soft">
            New Message · Mail
          </span>
        </div>
        <div className="flex items-center gap-2.5 border-b border-black/8 px-[22px] py-3 text-[13.5px] text-muted">
          To:{" "}
          <span className="rounded-full bg-black/5 px-2.5 py-0.5 text-[12.5px] text-ink">
            sarah@studio.com
          </span>
          <span className="text-soft">Subject: Following up</span>
        </div>
        <div className="min-h-[164px] whitespace-pre-line px-[22px] py-[22px] text-[15.5px] leading-7">
          {renderText()}
        </div>
        <div
          className={`flex flex-wrap items-center gap-[9px] px-[22px] transition-all duration-500 ${
            mode === "raw" || mode === "refining" || mode === "refined"
              ? "translate-y-0 pb-[18px] opacity-100"
              : "pointer-events-none translate-y-1.5 pb-0 opacity-0"
          }`}
        >
          <span className="mr-1 text-xs text-soft">Refine as</span>
          {(Object.keys(refinements) as Refinement[]).map((key) => (
            <button
              className={`rounded-full border px-3 py-1.5 text-xs font-semibold transition ${
                selected === key
                  ? "border-ink bg-ink text-white"
                  : "border-black/10 hover:border-ink"
              }`}
              type="button"
              key={key}
              onClick={() => refine(key)}
            >
              {refinements[key].label}
            </button>
          ))}
        </div>
        {meta && (
          <div className="flex flex-wrap items-center gap-2 px-[22px] pb-5 text-xs text-soft">
            <span className={mode === "refined" ? "text-success" : ""}>
              {meta}
            </span>
            {mode === "refined" && (
              <button
                className="font-semibold text-muted underline underline-offset-4"
                type="button"
                onClick={reset}
              >
                start over
              </button>
            )}
          </div>
        )}
      </div>
      <p className="mt-[34px] text-center text-[13.5px] text-soft">
        This is hush working.{" "}
        <span className="font-medium text-muted">Try it</span>, then watch local
        AI rewrite it for any context.
      </p>
    </div>
  );
}
