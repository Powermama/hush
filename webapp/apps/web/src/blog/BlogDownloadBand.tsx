// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { useEffect, useRef, useState } from "react";
import { type BlogLanguage } from "@hush/article/taxonomy";
import { blogCopy } from "../../shared/blog";
import { AppleIcon } from "../components/AppleIcon";
import { DownloadLink } from "../components/DownloadExperience";
import { HushHud, type HushHudState } from "../components/visuals/HushHud";

// One dictation, as the app shows it: listen, process on the Mac, insert.
const sequence: Array<{ state: HushHudState; ms: number }> = [
  { state: "listening", ms: 2600 },
  { state: "processing", ms: 700 },
  { state: "drafted", ms: 3200 },
];

/** Plays the HUD sequence while the card is on screen; reduced motion shows the result. */
function useDictationLoop(stage: React.RefObject<HTMLElement | null>, examples: number) {
  const [step, setStep] = useState(0);
  const [example, setExample] = useState(0);
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
        if (current === 0) setExample((value) => (value + 1) % examples);
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
  }, [stage, examples]);
  return { state: sequence[step]!.state, seconds, example };
}

type Demo = (typeof blogCopy)[BlogLanguage]["ctaDemos"][number];

/** The text dictated into the window, with a blinking caret until it arrives. */
function Typed({ text, typed, className }: { text: string; typed: boolean; className: string }) {
  return <p className={className} data-typed={typed}><span>{text}</span><i className="blog-cta-caret" /></p>;
}

/** One app per demo, each with its own look: Mail, a team chat and a coding agent in Terminal. */
function DemoWindow({ demo, typed }: { demo: Demo; typed: boolean }) {
  if (demo.kind === "slack") {
    return (
      <div className="blog-cta-window" data-kind="slack">
        <div className="blog-cta-window-bar"><i /><i /><i /><span>{demo.app}</span></div>
        <div className="blog-chat">
          <div className="blog-chat-sidebar" aria-hidden="true"><b /><b className="is-active" /><b /><b /></div>
          <div className="blog-chat-main">
            <p className="blog-chat-channel">{demo.title}</p>
            <div className="blog-chat-message">
              <span className="blog-chat-avatar">{demo.from[0]}</span>
              <div><strong>{demo.from}</strong><p>{demo.earlier}</p></div>
            </div>
            <div className="blog-chat-composer"><Typed text={demo.text} typed={typed} className="blog-cta-window-text" /></div>
          </div>
        </div>
      </div>
    );
  }
  if (demo.kind === "terminal") {
    return (
      <div className="blog-cta-window" data-kind="terminal">
        <div className="blog-cta-window-bar"><i /><i /><i /><span>{demo.title}</span></div>
        <div className="blog-terminal">
          <p className="blog-terminal-line"><span className="blog-terminal-path">~/hush</span> % {demo.prompt}</p>
          <div className="blog-terminal-box"><span className="blog-terminal-prompt">&gt;</span><Typed text={demo.text} typed={typed} className="blog-cta-window-text" /></div>
        </div>
      </div>
    );
  }
  return (
    <div className="blog-cta-window" data-kind="mail">
      <div className="blog-cta-window-bar"><i /><i /><i /><span>{demo.title}</span></div>
      {demo.fields.map(([label, value]) => (
        <div className="blog-cta-window-field" key={label}><span>{label}</span>{value}</div>
      ))}
      <Typed text={demo.text} typed={typed} className="blog-cta-window-text" />
    </div>
  );
}

/** Full-width download band above the footer of every blog page. */
export function BlogDownloadBand({ lang }: { lang: BlogLanguage }) {
  const copy = blogCopy[lang];
  const stage = useRef<HTMLDivElement>(null);
  const demos = copy.ctaDemos;
  const { state, seconds, example } = useDictationLoop(stage, demos.length);
  const demo = demos[example]!;
  const words = demo.text.split(/\s+/).length;
  const typed = state === "drafted";
  return (
    <section className="blog-download-band" aria-labelledby="blog-cta-title">
      <div className="blog-download-inner">
        <div className="blog-cta-body">
          <h2 id="blog-cta-title">{copy.ctaTitle}</h2>
          <p>{copy.ctaBody}</p>
          <DownloadLink variant="custom" className="gap-2 bg-ink text-white shadow-lg shadow-black/10 hover:bg-black" mobileLabel={copy.ctaMobile}>
            <AppleIcon />{copy.ctaDownload}
          </DownloadLink>
        </div>
        <div className="blog-cta-stage" ref={stage} aria-hidden="true">
          <DemoWindow demo={demo} typed={typed} />
          <HushHud
            state={state}
            className="blog-cta-hud"
            copy={{
              listening: { label: "Listening", detail: `0:0${Math.min(seconds, 9)}` },
              drafted: { label: `${words} words`, detail: `inserted into ${demo.app}` },
            }}
          />
        </div>
      </div>
    </section>
  );
}
