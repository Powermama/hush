import type { ReactNode } from "react";
import { Reveal } from "./Reveal";

export function SectionHeading({
  title,
  text,
}: {
  title: ReactNode;
  text: string;
}) {
  return (
    <Reveal className="section-heading mx-auto max-w-2xl text-center">
      <div data-section-heading>
        <h2 className="text-balance font-display text-4xl font-bold leading-[1.02] tracking-[-0.045em] sm:text-6xl">
          {title}
        </h2>
        <p className="section-heading-copy mx-auto max-w-xl text-pretty leading-7 text-muted">
          {text}
        </p>
      </div>
    </Reveal>
  );
}
