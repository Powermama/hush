// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { useEffect, type RefObject } from "react";
import { canStartLandingEntrance } from "./entrance/landingEntrance";

/** Own interruption and CSS fallback; a prepared scene starts the shared timeline. */
export function useLandingEntrance(root: RefObject<HTMLDivElement | null>) {
  useEffect(() => {
    const entry = root.current;
    if (!entry) return;
    let disposed = false;
    const motion = matchMedia("(prefers-reduced-motion: reduce)");
    const finish = () => { if (!disposed) entry.dataset.opening = "complete"; };
    // Read the CSS fallback clock, including after delayed hydration. The scene
    // may start the choreography only while the first composition is unrevealed.
    if (!canStartLandingEntrance(entry) || motion.matches ||
        scrollY >= 100 || location.hash || document.hidden) finish();
    const fallbackEnd = (event: AnimationEvent) => {
      if (event.animationName === "entrance-fallback" && entry.dataset.opening === "pending") finish();
    };
    const visibility = () => { if (document.hidden) finish(); };
    const reduceMotion = () => { if (motion.matches) finish(); };
    entry.addEventListener("animationend", fallbackEnd);
    window.addEventListener("wheel", finish, { passive: true });
    window.addEventListener("keydown", finish);
    window.addEventListener("touchstart", finish, { passive: true });
    window.addEventListener("pointerdown", finish, { passive: true });
    document.addEventListener("visibilitychange", visibility);
    motion.addEventListener("change", reduceMotion);
    return () => {
      disposed = true;
      entry.removeEventListener("animationend", fallbackEnd);
      window.removeEventListener("wheel", finish);
      window.removeEventListener("keydown", finish);
      window.removeEventListener("touchstart", finish);
      window.removeEventListener("pointerdown", finish);
      document.removeEventListener("visibilitychange", visibility);
      motion.removeEventListener("change", reduceMotion);
    };
  }, [root]);
}
