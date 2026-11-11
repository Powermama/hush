import { useEffect, useRef, useState } from "react";

export function CountUp({ to }: { to: number }) {
  const element = useRef<HTMLSpanElement>(null);
  const frame = useRef<number | undefined>(undefined);
  const [value, setValue] = useState(0);

  useEffect(() => {
    if (!element.current) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        observer.disconnect();
        const start = performance.now();

        const tick = (now: number) => {
          const progress = Math.min((now - start) / 1400, 1);
          const eased = 1 - (1 - progress) ** 3;
          setValue(Math.round(to * eased));
          if (progress < 1) frame.current = requestAnimationFrame(tick);
        };

        frame.current = requestAnimationFrame(tick);
      },
      { threshold: 0.5 },
    );

    observer.observe(element.current);
    return () => {
      observer.disconnect();
      if (frame.current) cancelAnimationFrame(frame.current);
    };
  }, [to]);

  return <span ref={element}>{value.toLocaleString("en-US")}</span>;
}
