import { artwork } from "../media/artwork";
import { useEffect, useRef } from "react";

export function PortraitSculpture() {
  const host = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const node = host.current;
    if (!node) return;
    let cancelled = false;
    let dispose: (() => void) | undefined;
    const observer = new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) return;
      observer.disconnect();
      void import("./PortraitScene").then(async ({ mountPortraitScene }) => {
        if (cancelled) return;
        const scene = await mountPortraitScene(node);
        if (cancelled) scene?.();
        else if (scene) dispose = scene;
        else node.dataset.scene = "fallback";
      }).catch(() => { if (!cancelled) node.dataset.scene = "fallback"; });
    }, { rootMargin: "100px" });
    observer.observe(node);
    return () => { cancelled = true; observer.disconnect(); dispose?.(); };
  }, []);
  return <div ref={host} className="vm-portrait-sculpture" role="img" aria-label="An Ameca robot photograph split into sculptural fragments, an illustration of a feed filled with artificial voices.">
    <div className="vm-portrait-fallback" aria-hidden="true"><img src={artwork.robotPortrait.src} srcSet={artwork.robotPortrait.srcSet} sizes="(max-width: 760px) 85vw, 480px" width="780" height="973" decoding="async" alt="" /><div className="vm-portrait-fragment" /></div>
  </div>;
}
