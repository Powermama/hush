import { useEffect, useRef } from "react";

// A quiet, original elastic dot field. Draw only while responding or settling.
export function ResponsiveField() {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current;
    const hero = canvas?.closest<HTMLElement>(".landing-hero");
    const context = canvas?.getContext("2d");
    if (!canvas || !hero || !context) return;
    const motion = matchMedia("(prefers-reduced-motion: reduce)");
    let width = 1, height = 1, frame = 0, visible = true;
    let targetX = -1000, targetY = -1000, x = targetX, y = targetY;
    let strength = 0, targetStrength = 0;
    let points: { x: number; y: number; radius: number }[] = [];
    function schedule() {
      if (!frame && visible && !document.hidden) frame = requestAnimationFrame(draw);
    }
    function draw() {
      frame = 0;
      if (!visible || document.hidden) return;
      x += (targetX - x) * .2;
      y += (targetY - y) * .2;
      strength += (targetStrength - strength) * .14;
      context!.clearRect(0, 0, width, height);
      context!.fillStyle = "#638c98";
      context!.beginPath();
      for (const point of points) {
        const dx = point.x - x, dy = point.y - y;
        const distance = Math.hypot(dx, dy);
        const force = motion.matches ? 0 : Math.pow(Math.max(0, 1 - distance / 150), 2) * 32 * strength;
        const px = point.x + dx / Math.max(1, distance) * force;
        const py = point.y + dy / Math.max(1, distance) * force;
        context!.moveTo(px + point.radius, py);
        context!.arc(px, py, point.radius, 0, Math.PI * 2);
      }
      context!.fill();
      if (!motion.matches && (Math.abs(targetX - x) + Math.abs(targetY - y) > .1 || Math.abs(targetStrength - strength) > .001)) schedule();
    }
    function resize() {
      const rect = canvas!.getBoundingClientRect();
      width = rect.width; height = rect.height;
      const dpr = Math.min(devicePixelRatio, 1.5);
      canvas!.width = Math.round(width * dpr); canvas!.height = Math.round(height * dpr);
      context!.setTransform(dpr, 0, 0, dpr, 0, 0);
      points = [];
      const gap = Math.max(9, Math.sqrt(width * height / 15000));
      for (let py = 0; py < height; py += gap) {
        for (let px = 0; px < width; px += gap) {
          const wave = (Math.sin(px * .012 + py * .018) + 1) * .5;
          points.push({ x: px, y: py, radius: .5 + wave * .6 });
        }
      }
      schedule();
    }
    function move(event: PointerEvent) {
      if (event.pointerType !== "mouse" || motion.matches) return;
      const rect = canvas!.getBoundingClientRect();
      targetX = event.clientX - rect.left; targetY = event.clientY - rect.top;
      if (strength < .01) { x = targetX; y = targetY; }
      targetStrength = 1;
      schedule();
    }
    function clear() { targetStrength = 0; if (motion.matches) strength = 0; schedule(); }
    function visibility() { if (document.hidden) { cancelAnimationFrame(frame); frame = 0; } else { clear(); } }
    const resizeObserver = new ResizeObserver(resize);
    const intersectionObserver = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      if (visible) schedule(); else { cancelAnimationFrame(frame); frame = 0; targetStrength = strength = 0; }
    });
    resizeObserver.observe(canvas); intersectionObserver.observe(hero);
    hero.addEventListener("pointermove", move, { passive: true });
    hero.addEventListener("pointerleave", clear);
    window.addEventListener("blur", clear);
    document.addEventListener("visibilitychange", visibility);
    motion.addEventListener("change", clear);
    resize();
    return () => {
      cancelAnimationFrame(frame);
      resizeObserver.disconnect(); intersectionObserver.disconnect();
      hero.removeEventListener("pointermove", move);
      hero.removeEventListener("pointerleave", clear);
      window.removeEventListener("blur", clear);
      document.removeEventListener("visibilitychange", visibility);
      motion.removeEventListener("change", clear);
    };
  }, []);
  return <canvas className="universe-field" ref={ref} aria-hidden="true" />;
}
