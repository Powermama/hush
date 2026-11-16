// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// What the settings navigation (in the sidebar) and the settings page share,
// as Ghost Admin's settings-app-context and use-scroll-section do: the search
// filter, the section in view, and a jump to a section.
import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from "react";

/** The sections, in page order, with the words the settings search matches. */
export const settingsSections = [
  { id: "account", group: "General settings", title: "Account", keywords: ["account", "github", "sign in", "sign out", "session", "owner", "login"] },
  { id: "integrations", group: "Advanced", title: "Integrations", keywords: ["integrations", "api", "tokens", "token", "cli", "hush-cms", "devices", "connect", "revoke", "keys"] },
] as const;
export type SettingsSectionId = (typeof settingsSections)[number]["id"];

type SettingsState = {
  filter: string;
  setFilter: (filter: string) => void;
  /** Whether a section matches the filter (every section does while it is empty). */
  isVisible: (id: SettingsSectionId) => boolean;
  current: SettingsSectionId | undefined;
  setCurrent: (id: SettingsSectionId) => void;
  /** The section a nav click asked for, highlighted for a moment once it is in view. */
  highlighted: SettingsSectionId | undefined;
  jumpTo: (id: SettingsSectionId) => void;
};

const SettingsContext = createContext<SettingsState | null>(null);

export function SettingsProvider({ children }: { children: ReactNode }) {
  const [filter, setFilter] = useState("");
  const [current, setCurrent] = useState<SettingsSectionId>();
  const [highlighted, setHighlighted] = useState<SettingsSectionId>();
  const isVisible = useCallback((id: SettingsSectionId) => {
    const term = filter.trim().toLowerCase();
    if (!term) return true;
    const section = settingsSections.find((item) => item.id === id)!;
    return [section.title.toLowerCase(), ...section.keywords].some((keyword) => keyword.includes(term));
  }, [filter]);
  const jumpTo = useCallback((id: SettingsSectionId) => {
    setFilter("");
    setCurrent(id);
    setHighlighted(id);
    // After the cleared filter has shown every section.
    requestAnimationFrame(() => document.getElementById(`settings-${id}`)?.scrollIntoView({ behavior: "smooth", block: "start" }));
    setTimeout(() => setHighlighted((value) => (value === id ? undefined : value)), 2000);
  }, []);
  const value = useMemo(() => ({ filter, setFilter, isVisible, current, setCurrent, highlighted, jumpTo }), [filter, isVisible, current, highlighted, jumpTo]);
  return <SettingsContext.Provider value={value}>{children}</SettingsContext.Provider>;
}

export function useSettings() {
  const state = useContext(SettingsContext);
  if (!state) throw new Error("useSettings needs a SettingsProvider");
  return state;
}
