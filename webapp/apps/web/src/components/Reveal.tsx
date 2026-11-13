import { useEffect, type ReactNode } from "react";
import { useAnimate } from "motion/react-mini";

const ease = [0.22, 1, 0.36, 1] as const;

export function Reveal({
  children,
  className = "",
  delay = 0,
}: {
  children: ReactNode;
  className?: string;
  delay?: number;
}) {
  const [scope, animate] = useAnimate();

  useEffect(() => {
    const element = scope.current;
    if (!element) return;

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      element.style.opacity = "1";
      element.style.transform = "none";
      return;
    }

    let stop = () => {};
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (!entry.isIntersecting) return;
        const controls = animate(
          element,
          { opacity: 1, transform: "translateY(0px)" },
          { duration: 0.8, delay: delay / 1000, ease },
        );
        stop = () => controls.stop();
        observer.disconnect();
      },
      { threshold: 0.12 },
    );

    observer.observe(element);
    return () => {
      observer.disconnect();
      stop();
    };
  }, [animate, delay, scope]);

  return (
    <div
      ref={scope}
      className={className}
      style={{ opacity: 0, transform: "translateY(20px)" }}
    >
      {children}
    </div>
  );
}
