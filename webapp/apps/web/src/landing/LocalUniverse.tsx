import { shadowedAppIcons } from "../media/appIcons";
import { useEffect, useRef, type CSSProperties } from "react";
import { ResponsiveField } from "./ResponsiveField";
import { startLandingEntranceWithoutScene } from "./entrance/landingEntrance";
import { m } from "../paraglide/messages";

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

function showFallback(host: HTMLElement) {
  host.dataset.scene = "fallback";
  startLandingEntranceWithoutScene(host.closest<HTMLElement>(".hush-landing"));
}

export function LocalUniverse() {
  const host = useRef<HTMLDivElement>(null);
  useEffect(() => {
    let cancelled = false;
    const controller = new AbortController();
    let dispose: (() => void) | null = null;
    // These optional hints only accelerate the fallback. Safari and browsers
    // without them use the same bounded CSS window and actual scene readiness.
    const connection = (navigator as Navigator & {
      connection?: { saveData?: boolean; effectiveType?: string };
    }).connection;
    if (host.current && (connection?.saveData || /^(slow-)?2g$/.test(connection?.effectiveType ?? ""))) {
      host.current.dataset.fallback = "immediate";
      const entry = host.current.closest<HTMLElement>(".hush-landing");
      if (entry) entry.dataset.opening = "complete";
    }
    // Fetch immediately. The CSS fallback bounds content visibility independently
    // while a fast scene can coordinate the original entrance choreography.
    void import("./HushScene").then(async ({ mountHushScene }) => {
      if (!cancelled && host.current) {
        dispose = await mountHushScene(host.current, controller.signal);
        if (cancelled) { dispose?.(); return; }
        if (!dispose) showFallback(host.current);
      }
    }).catch(() => {
      if (cancelled) return;
      if (host.current) showFallback(host.current);
    });
    return () => {
      cancelled = true;
      controller.abort();
      dispose?.();
    };
  }, []);
  return <div className="local-universe">
    <div className="universe-texture" aria-hidden="true"><ResponsiveField /></div>
    <div className="universe-illustration" role="img" aria-label={m.universe_label()}>
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
      <div className="orbit-tile"><img src={shadowedAppIcons[app.name]} width="56" height="56" alt="" decoding="async" /></div>
      <span>{app.name}</span>
    </div>)}
    </div>
  </div>;
}
