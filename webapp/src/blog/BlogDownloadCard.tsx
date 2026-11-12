// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { useEffect, useRef, useState } from "react";
import { blogCopy, type BlogLanguage } from "../../shared/blog";
import { AppleIcon } from "../components/AppleIcon";
import { DownloadLink } from "../components/DownloadExperience";
import { HushHud, type HushHudState } from "../components/visuals/HushHud";

// One dictation, as the app shows it: listen, process on the Mac, insert.
const sequence: Array<{ state: HushHudState; ms: number }> = [
  { state: "listening", ms: 2600 },
  { state: "processing", ms: 1500 },
  { state: "drafted", ms: 3200 },
];

/** Plays the HUD sequence while the card is on screen; reduced motion shows the result. */
function useDictationLoop(stage: React.RefObject<HTMLElement | null>) {
  const [step, setStep] = useState(0);
  const [seconds, setSeconds] = useState(1);
  useEffect(() => {
    const element = stage.current;
    if (!element || matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setStep(2);
      return;
    }
    let visible = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let clock: ReturnType<typeof setInterval> | undefined;
    let current = 0;
    const run = () => {
      clearInterval(clock);
      setStep(current);
      setSeconds(1);
      if (sequence[current]!.state === "listening") clock = setInterval(() => setSeconds((value) => value + 1), 1000);
      timer = setTimeout(() => {
        current = (current + 1) % sequence.length;
        if (visible) run();
      }, sequence[current]!.ms);
    };
    const observer = new IntersectionObserver(([entry]) => {
      const wasVisible = visible;
      visible = entry!.isIntersecting;
      if (visible && !wasVisible) run();
      if (!visible) { clearTimeout(timer); clearInterval(clock); }
    });
    observer.observe(element);
    return () => { observer.disconnect(); clearTimeout(timer); clearInterval(clock); };
  }, [stage]);
  return { state: sequence[step]!.state, seconds };
}

export function BlogDownloadCard({ lang }: { lang: BlogLanguage }) {
  const copy = blogCopy[lang];
  const stage = useRef<HTMLDivElement>(null);
  const { state, seconds } = useDictationLoop(stage);
  const typed = state === "drafted";
  return (
    <section className="blog-cta" aria-labelledby="blog-cta-title">
      <div className="blog-cta-stage" ref={stage} aria-hidden="true">
        <div className="blog-cta-window">
          <div className="blog-cta-window-bar"><i /><i /><i /><span>{copy.ctaDemo.title}</span></div>
          <div className="blog-cta-window-field"><span>{copy.ctaDemo.toLabel}</span>{copy.ctaDemo.to}</div>
          <div className="blog-cta-window-field"><span>{copy.ctaDemo.subjectLabel}</span>{copy.ctaDemo.subject}</div>
          <p className="blog-cta-window-text" data-typed={typed}>
            <span>{copy.ctaDemo.text}</span><i className="blog-cta-caret" />
          </p>
        </div>
        <HushHud
          state={state}
          className="blog-cta-hud"
          copy={{
            listening: { label: "Listening", detail: `0:0${Math.min(seconds, 9)}` },
            drafted: { label: copy.ctaDemo.words, detail: `inserted into ${copy.ctaDemo.app}` },
          }}
        />
      </div>
      <div className="blog-cta-body">
        <h2 id="blog-cta-title">{copy.ctaTitle}</h2>
        <p>{copy.ctaBody}</p>
        <DownloadLink variant="custom" className="gap-2 bg-ink text-white shadow-lg shadow-black/10 hover:bg-black" mobileLabel={copy.ctaMobile}>
          <AppleIcon />{copy.ctaDownload}
        </DownloadLink>
      </div>
    </section>
  );
}
