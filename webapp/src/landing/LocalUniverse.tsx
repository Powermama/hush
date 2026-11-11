import { useEffect, useRef, type CSSProperties } from "react";
import { ResponsiveField } from "./ResponsiveField";

export function WaveMark({ className = "" }: { className?: string }) {
  return <svg className={className} viewBox="0 0 80 80" fill="none" aria-hidden="true">
    <path d="M17 34v12M32 20v40M48 27v26M63 35v10" stroke="currentColor" strokeWidth="6.5" strokeLinecap="round" />
  </svg>;
}

const apps = [
  { name: "Mail", file: "mail", x: 23, y: 19 },
  { name: "Messages", file: "messages", x: 76, y: 19 },
  { name: "Notes", file: "notes", x: 10, y: 50 },
  { name: "Slack", file: "slack", x: 90, y: 50 },
  { name: "Chrome", file: "chrome", x: 23, y: 82 },
  { name: "Notion", file: "notion", x: 76, y: 82 },
  { name: "Figma", file: "figma", x: 50, y: 96 },
];

export function LocalUniverse() {
  const host = useRef<HTMLDivElement>(null);
  useEffect(() => {
    let cancelled = false;
    const controller = new AbortController();
    let dispose: (() => void) | null = null;
    const entry = host.current?.closest<HTMLElement>(".hush-landing");
    const release = () => { if (entry?.dataset.opening === "pending") entry.dataset.opening = "complete"; };
    if (matchMedia("(prefers-reduced-motion: reduce)").matches || scrollY >= 100 || location.hash || document.hidden) release();
    const recovery = window.setTimeout(release, 2200);
    window.addEventListener("wheel", release, { passive: true });
    window.addEventListener("keydown", release);
    window.addEventListener("touchstart", release, { passive: true });
    window.addEventListener("pointerdown", release, { passive: true });
    // Keep the initial canvas blank until the scene and its CSS timeline are ready.
    const timer = window.setTimeout(() => {
      void import("./HushScene").then(async ({ mountHushScene }) => {
        if (!cancelled && host.current) {
          dispose = await mountHushScene(host.current, controller.signal);
          if (cancelled) { dispose?.(); return; }
          if (!dispose) { host.current.dataset.scene = "fallback"; release(); }
        }
      }).catch(() => {
        if (cancelled) return;
        if (host.current) host.current.dataset.scene = "fallback";
        release();
      });
    }, 150);
    return () => {
      cancelled = true;
      controller.abort();
      clearTimeout(timer);
      clearTimeout(recovery);
      window.removeEventListener("wheel", release);
      window.removeEventListener("keydown", release);
      window.removeEventListener("touchstart", release);
      window.removeEventListener("pointerdown", release);
      dispose?.();
    };
  }, []);
  return <div className="local-universe">
    <div className="universe-texture" aria-hidden="true"><ResponsiveField /></div>
    <div className="universe-illustration" role="img" aria-label="hush connects your voice to familiar Mac apps: Mail, Messages, Notes, Slack, Chrome, Notion and Figma.">
    <div className="universe-halo" />
    <svg className="universe-paths" viewBox="0 0 1000 500" fill="none" aria-hidden="true">
      <ellipse cx="500" cy="250" rx="405" ry="205" />
      <ellipse cx="500" cy="250" rx="320" ry="150" className="inner-orbit" />
      {apps.map(app => <path key={app.name} d={`M500 250 Q ${app.x * 10} 250 ${app.x * 10} ${app.y * 5}`} />)}
    </svg>
    <div className="hush-core" ref={host} aria-hidden="true">
      <div className="core-fallback"><i /><i /><div><WaveMark /></div></div>
    </div>
    {apps.map((app, index) => <div className={`orbit-app orbit-${app.file}`} key={app.name}
      style={{ left: `${app.x}%`, top: `${app.y}%`, "--app-delay": `${index * 0.08}s` } as CSSProperties} aria-hidden="true">
      <div className="orbit-tile"><img src={`/app-icons/${app.file}.png`} width="64" height="64" alt="" decoding="async" /></div>
      <span>{app.name}</span>
    </div>)}
    </div>
  </div>;
}
