import { useEffect, useRef, useState } from "react";

const levels = [7, 10, 16, 9, 21, 28, 16, 32, 23, 12, 19, 27, 35, 22, 14, 25, 18, 30, 21, 12, 26, 17, 10, 23, 15, 9, 12, 6];

export function DictationPreview() {
  const [phase, setPhase] = useState<"ready" | "processing" | "inserted">("ready");
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(timer.current), []);

  function play() {
    clearTimeout(timer.current);
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setPhase("inserted");
      return;
    }
    setPhase("processing");
    timer.current = setTimeout(() => setPhase("inserted"), 950);
  }

  return <div className="dictation-preview" role="group" aria-label="Local dictation preview" data-phase={phase}>
    <div className="dictation-preview-label"><span>Dictation preview</span><button type="button" aria-label="Play dictation preview" onClick={play} disabled={phase === "processing"}><svg viewBox="0 0 16 16" aria-hidden="true"><path d="M5 3L12 8L5 13Z" /></svg>Try it</button></div>
    <div className="dictation-hud">
      <span className="dictation-hud-icon" aria-hidden="true"><svg viewBox="0 0 32 32"><path d="M8 13V19M13 8V24M19 11V21M24 14V18" /></svg></span>
      <div className="dictation-hud-label" role="status"><strong>{phase === "processing" ? "Transcribing" : phase === "inserted" ? "Inserted" : "Your voice, typed"}</strong><span>{phase === "inserted" ? "6 words · Notes" : "On your Mac"}</span></div>
      <div className="dictation-hud-wave" aria-hidden="true">{levels.map((height, index) => <i key={index} style={{ height }} />)}</div>
    </div>
    <p className="dictation-preview-text">{phase === "inserted" ? "What if we tried something different?" : "A thought, ready to become words."}<span aria-hidden="true">|</span></p>
  </div>;
}
