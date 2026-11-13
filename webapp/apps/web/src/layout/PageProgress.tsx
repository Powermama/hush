import { useEffect, useRef, useState } from "react";
import { useLocation } from "@tanstack/react-router";
import "./page-progress.css";

/** Native reading progress, without scroll interception or an idle animation loop. */
export function PageProgress() {
  const path = useLocation({ select: location => location.pathname });
  const track = useRef<HTMLDivElement>(null);
  const [percent, setPercent] = useState(0);

  useEffect(() => {
    const node = track.current;
    if (!node) return;
    let frame = 0;
    let distance = Math.max(0, document.documentElement.scrollHeight - innerHeight);
    function update() {
      frame = 0;
      if (document.hidden) return;
      const progress = distance > 0 ? Math.max(0, Math.min(1, scrollY / distance)) : 0;
      node!.style.setProperty("--page-progress", String(progress));
      node!.dataset.started = String(scrollY > 1 && distance > 0);
      setPercent(Math.round(progress * 100));
    }
    function schedule() { if (!frame && !document.hidden) frame = requestAnimationFrame(update); }
    function measure() { distance = Math.max(0, document.documentElement.scrollHeight - innerHeight); schedule(); }
    function visibility() {
      if (document.hidden) { cancelAnimationFrame(frame); frame = 0; }
      else measure();
    }
    const size = new ResizeObserver(measure);
    size.observe(document.body);
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", measure, { passive: true });
    document.addEventListener("visibilitychange", visibility);
    update();
    return () => {
      cancelAnimationFrame(frame);
      size.disconnect();
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", measure);
      document.removeEventListener("visibilitychange", visibility);
    };
  }, [path]);

  return <div ref={track} className="page-progress" role="progressbar" aria-label="Page reading progress" aria-valuemin={0} aria-valuemax={100} aria-valuenow={percent} aria-valuetext={`${percent}% read`}>
    <div className="page-progress-fill" aria-hidden="true" />
  </div>;
}
