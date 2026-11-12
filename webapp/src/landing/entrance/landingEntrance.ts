// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann

/** CSS independently reveals the page if graphics or hydration arrive too late. */
export function canStartLandingEntrance(entry: HTMLElement) {
  if (entry.dataset.opening !== "pending") return false;
  const fallback = entry.querySelector(".site-header")?.getAnimations().find(animation =>
    animation instanceof CSSAnimation && animation.animationName === "entrance-fallback");
  const delay = fallback?.effect?.getTiming().delay ?? 0;
  return Boolean(fallback && Number(fallback.currentTime) < delay);
}

/** Start once, before fallback visibility; never replay already visible content. */
export function startLandingEntrance(entry: HTMLElement | null) {
  if (!entry || !canStartLandingEntrance(entry)) return false;
  entry.dataset.opening = "playing";
  return true;
}
