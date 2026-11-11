// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { useEffect, type RefObject } from "react";

/** CSS starts the entrance at first paint, before hydration or optional artwork. */
export function useLandingEntrance(root: RefObject<HTMLDivElement | null>) {
  useEffect(() => {
    const entry = root.current;
    if (!entry) return;
    let disposed = false;
    const motion = matchMedia("(prefers-reduced-motion: reduce)");
    const finish = () => { if (!disposed) entry.dataset.opening = "complete"; };
    // This is the longest CSS entrance animation. A late hydration observes its
    // finished state instead of starting a second, JavaScript-owned timer.
    const entrance = entry.querySelector(".universe-texture")?.getAnimations()[0];
    if (!entrance || entrance.playState === "finished" || motion.matches ||
        scrollY >= 100 || location.hash || document.hidden) finish();
    else void entrance.finished.then(finish, () => {});
    const visibility = () => { if (document.hidden) finish(); };
    const reduceMotion = () => { if (motion.matches) finish(); };
    window.addEventListener("wheel", finish, { passive: true });
    window.addEventListener("keydown", finish);
    window.addEventListener("touchstart", finish, { passive: true });
    window.addEventListener("pointerdown", finish, { passive: true });
    document.addEventListener("visibilitychange", visibility);
    motion.addEventListener("change", reduceMotion);
    return () => {
      disposed = true;
      window.removeEventListener("wheel", finish);
      window.removeEventListener("keydown", finish);
      window.removeEventListener("touchstart", finish);
      window.removeEventListener("pointerdown", finish);
      document.removeEventListener("visibilitychange", visibility);
      motion.removeEventListener("change", reduceMotion);
    };
  }, [root]);
}
