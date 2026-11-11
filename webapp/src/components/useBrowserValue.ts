// SPDX-License-Identifier: AGPL-3.0-only
// Copyright 2026 Clemens Kressmann
import { useSyncExternalStore } from "react";

const subscribe = () => () => {};
/** Match the static HTML during hydration, then read the browser's real state. */
export function useBrowserValue<T>(read: () => T, initial: T): T {
  return useSyncExternalStore(subscribe, read, () => initial);
}
