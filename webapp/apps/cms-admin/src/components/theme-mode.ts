// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Light, dark or system appearance, as Ghost Admin applies it: a `dark` class on
// <html> (admin-x-framework/src/utils/admin-theme.ts). The choice is a per-browser
// preference, so it lives in localStorage.
import { useEffect, useState } from "react";

export type ThemeMode = "light" | "dark" | "system";
const storageKey = "hush-cms-appearance";

function stored(): ThemeMode {
  try {
    const value = localStorage.getItem(storageKey);
    return value === "light" || value === "dark" ? value : "system";
  } catch {
    return "system";
  }
}

export function applyStoredTheme() {
  apply(stored());
}

let releaseFrame: number | undefined;

function apply(mode: ThemeMode) {
  const dark = mode === "dark" || (mode === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches);
  const html = document.documentElement;
  if (html.classList.contains("dark") === dark) return;
  // Hold transitions back so the whole UI flips in one paint (theme-switching in @hush/theme).
  html.classList.add("theme-switching");
  html.classList.toggle("dark", dark);
  if (releaseFrame !== undefined) cancelAnimationFrame(releaseFrame);
  releaseFrame = requestAnimationFrame(() => {
    releaseFrame = requestAnimationFrame(() => {
      html.classList.remove("theme-switching");
      releaseFrame = undefined;
    });
  });
}

export function useThemeMode() {
  const [mode, setMode] = useState<ThemeMode>(stored);
  useEffect(() => {
    apply(mode);
    try { localStorage.setItem(storageKey, mode); } catch { /* private mode: keep it for this visit */ }
    if (mode !== "system") return;
    const query = window.matchMedia("(prefers-color-scheme: dark)");
    const follow = () => apply("system");
    query.addEventListener("change", follow);
    return () => query.removeEventListener("change", follow);
  }, [mode]);
  return [mode, setMode] as const;
}
