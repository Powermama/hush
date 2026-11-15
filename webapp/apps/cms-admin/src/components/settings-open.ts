// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Whether the post settings panel is open, remembered in this browser across
// every post, as in Ghost's editor (apps/admin/src/editor/settings-open.ts). The
// editor opens with the panel as the writer last left it with the toggle or
// Cmd/Ctrl+.; where the panel covers the editor (below 1024px) it always starts
// closed and a toggle there is not remembered.
import { useCallback, useEffect, useRef, useState, useSyncExternalStore } from "react";

/** One state for all posts, stored as `open` or `closed`. */
export const settingsOpenKey = "hush-editor-settings-open";

/** Below Shade's `lg` breakpoint the panel overlays the editor instead of sitting beside it. */
const overlayScreen = "(width < 1024px)";

/** Reading `localStorage` can throw where storage is blocked. */
type StorageSource = () => Storage;
const browserStorage: StorageSource = () => window.localStorage;

/** Whether the writer last left the panel open; missing, unreadable or unknown values read as closed. */
export function readSettingsOpen(storage: StorageSource = browserStorage) {
  try {
    return storage().getItem(settingsOpenKey) === "open";
  } catch {
    return false;
  }
}

export function writeSettingsOpen(open: boolean, storage: StorageSource = browserStorage) {
  try {
    storage().setItem(settingsOpenKey, open ? "open" : "closed");
  } catch {
    // A full or blocked localStorage costs the memory, not the toggle.
  }
}

/** Whether the editor opens with the panel open: never where it would cover the post. */
export const settingsOpenAtStart = ({ overlay, stored }: { overlay: boolean; stored: boolean }) => !overlay && stored;

function subscribe(onChange: () => void) {
  const query = window.matchMedia(overlayScreen);
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
}

/** Whether the panel overlays the editor at the current width. */
export function useOverlayScreen() {
  return useSyncExternalStore(subscribe, () => window.matchMedia(overlayScreen).matches);
}

/**
 * The panel's remembered state, decided from the width in the first render and
 * never revisited, so nothing moves on its own after the editor has opened.
 * `restored` holds while the panel is still the one the editor opened with,
 * which is in place from the first paint rather than sliding in.
 */
export function useSettingsOpen() {
  const overlay = useOverlayScreen();
  const [openAtStart] = useState(() => settingsOpenAtStart({ overlay, stored: readSettingsOpen() }));
  const [restored, setRestored] = useState(openAtStart);
  const latest = useRef(overlay);
  useEffect(() => { latest.current = overlay; }, [overlay]);
  const toggled = useCallback((open: boolean) => {
    setRestored(false);
    if (!latest.current) writeSettingsOpen(open);
  }, []);
  return { openAtStart, restored, toggled };
}
