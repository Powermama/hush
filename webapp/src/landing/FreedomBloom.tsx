import { useEffect, useId, useRef } from "react";

/** Locally served CC0 rose with a vector fallback; never a product control. */
export function FreedomBloom() {
  const host = useRef<HTMLDivElement>(null);
  const id = useId().replaceAll(":", "");
  useEffect(() => {
    const node = host.current;
    if (!node) return;
    let disposed = false;
    const controller = new AbortController();
    let dispose: (() => void) | undefined;
    const observer = new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) return;
      observer.disconnect();
      void import("./FreedomBloomScene").then(async ({ mountFreedomBloom }) => {
        if (disposed) return;
        const cleanup = await mountFreedomBloom(node, controller.signal);
        if (disposed) { cleanup?.(); return; }
        dispose = cleanup ?? undefined;
        if (!dispose) node.dataset.scene = "fallback";
      }).catch(() => { if (!disposed) node.dataset.scene = "fallback"; });
    }, { rootMargin: "120px" });
    observer.observe(node);
    return () => { disposed = true; controller.abort(); observer.disconnect(); dispose?.(); };
  }, []);
  return <div ref={host} className="freedom-bloom" style={{ position: "relative", width: "100%", aspectRatio: "6 / 7", overflow: "hidden" }} role="img" aria-label="A sculptural pearl and lilac rose, an open bloom for ideas that belong to everyone.">
    <svg className="bloom-fallback" viewBox="0 0 600 700" aria-hidden="true">
      <defs><linearGradient id={`${id}-petal`} x1="0" y1="0" x2="1" y2="1"><stop stopColor="#f4e9ee" /><stop offset=".5" stopColor="#d6c6df" /><stop offset="1" stopColor="#a695c0" /></linearGradient></defs>
      <path d="M308 640C325 500 210 436 300 300" fill="none" stroke="#9aa8b7" strokeWidth="7" />
      <path d="M300 514C225 510 190 452 184 414C256 417 289 455 300 514ZM294 447C366 440 409 386 416 358C352 362 315 400 294 447Z" fill="#bdc4d4" />
      <g transform="translate(300 270)">
        {[{ count: 7, scale: 1, phase: 0 }, { count: 6, scale: .74, phase: 28 }, { count: 5, scale: .49, phase: 55 }, { count: 3, scale: .25, phase: 85 }].map((ring, index) => <g key={index} transform={`rotate(${ring.phase}) scale(${ring.scale})`}>
          {Array.from({ length: ring.count }, (_, i) => <path key={i} transform={`rotate(${i * 360 / ring.count})`} d="M-16 24C-132-4-176-142-85-182C-26-209 83-192 111-128C141-59 61 7-16 24Z" fill={`url(#${id}-petal)`} stroke="#b6a7c7" strokeWidth="1.5" />)}
        </g>)}
        <ellipse rx="13" ry="18" fill="#ad9ac3" />
      </g>
    </svg>
  </div>;
}
