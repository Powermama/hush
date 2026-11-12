// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { useEffect, useState } from "react";

// A section counts as current once its heading has passed this line
// (just below the sticky site header).
const readingLine = 140;

/** The id of the section being read, for highlighting the table of contents. */
export function useActiveSection(ids: string[]) {
  const [active, setActive] = useState<string | undefined>(undefined);
  const key = ids.join(" ");
  useEffect(() => {
    const sectionIds = key.split(" ");
    let frame = 0;
    const update = () => {
      frame = 0;
      // Looked up on every update: hydration can replace the article HTML, and
      // detached headings would report a position of 0.
      const headings = sectionIds.map((id) => document.getElementById(id)).filter((element) => element !== null);
      if (!headings.length) return;
      let current: string | undefined;
      for (const heading of headings) {
        if (heading.getBoundingClientRect().top <= readingLine) current = heading.id;
        else break;
      }
      // At the very end of the page the last short sections can never reach
      // the line, so the last heading wins once the page cannot scroll further.
      if (innerHeight + scrollY >= document.documentElement.scrollHeight - 2) current = headings.at(-1)!.id;
      setActive(current);
    };
    const schedule = () => { if (!frame) frame = requestAnimationFrame(update); };
    update();
    addEventListener("scroll", schedule, { passive: true });
    addEventListener("resize", schedule);
    return () => {
      removeEventListener("scroll", schedule);
      removeEventListener("resize", schedule);
      cancelAnimationFrame(frame);
    };
  }, [key]);
  return active;
}
