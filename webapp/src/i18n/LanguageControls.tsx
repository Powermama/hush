// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { useState } from "react";
import { useLocation } from "@tanstack/react-router";
import { sitePages, type SiteLanguage } from "../../shared/site";
import { useBrowserValue } from "../components/useBrowserValue";
import { m } from "../paraglide/messages";
import { getLocale } from "../paraglide/runtime";
import "./language.css";

// Read by the head script in shared/site-head.ts: a stored choice always wins.
const storageKey = "hush.language";
const languageNames: Record<SiteLanguage, string> = { en: "English", de: "Deutsch" };

function storedLanguage(): SiteLanguage | undefined {
  try {
    const value = localStorage.getItem(storageKey);
    return value === "en" || value === "de" ? value : undefined;
  } catch { return undefined; }
}

function rememberLanguage(language: SiteLanguage) {
  try { localStorage.setItem(storageKey, language); } catch { /* private mode: the choice lasts for this page only */ }
}

/** The same page in the other language when it exists (landing, legal pages), otherwise that language's home. */
function counterpartPath(path: string, language: SiteLanguage) {
  return sitePages[path]?.alternatePaths?.[language] ?? (language === "de" ? "/de" : "/");
}

/**
 * Footer switcher between English and German: a segmented control whose thumb
 * glides to the chosen language before the page changes. The options are real
 * links, so it works without JavaScript; the choice is remembered.
 */
export function LanguageSwitcher() {
  const path = useLocation({ select: (location) => location.pathname });
  const current = getLocale() as SiteLanguage;
  const [selected, setSelected] = useState<SiteLanguage>(current);
  const languages = ["en", "de"] as const;
  return (
    <nav className="language-switcher" aria-label={m.footer_language()}>
      <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3c2.5 2.6 3.8 5.6 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.6-3.8-9S9.5 5.6 12 3Z" /></svg>
      <span className="language-switcher-track" data-selected={selected}>
        <span className="language-switcher-thumb" aria-hidden="true" />
        {languages.map((language) => {
          const href = language === current ? path : counterpartPath(path, language);
          return (
            <a
              key={language}
              href={href}
              hrefLang={language}
              lang={language}
              aria-current={language === current ? "true" : undefined}
              onClick={(event) => {
                rememberLanguage(language);
                if (language === current || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
                // Let the thumb arrive before the next page loads, unless motion is reduced.
                if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
                event.preventDefault();
                setSelected(language);
                setTimeout(() => location.assign(href), 220);
              }}
            >
              {languageNames[language]}
            </a>
          );
        })}
      </span>
    </nav>
  );
}

/**
 * A slim bar offering the page in the browser's first language when it differs
 * from the page and no choice is stored. Shown only on pages with a translation.
 */
export function LanguageHint() {
  const path = useLocation({ select: (location) => location.pathname });
  const current = getLocale() as SiteLanguage;
  const preferred = useBrowserValue<SiteLanguage | undefined>(() => {
    if (storedLanguage()) return undefined;
    const first = (navigator.languages?.[0] ?? navigator.language ?? "").toLowerCase();
    return first.startsWith("de") ? "de" : first.startsWith("en") ? "en" : undefined;
  }, undefined);
  const [dismissed, setDismissed] = useState(false);
  const target = preferred && preferred !== current ? sitePages[path]?.alternatePaths?.[preferred] : undefined;
  if (!target || dismissed) return null;
  // Messages in the offered language, so a German reader sees German on an English page.
  const options = { locale: preferred };
  return (
    <div className="language-hint" role="region" aria-label={m.footer_language({}, options)} lang={preferred}>
      <p>
        {m.language_hint({}, options)}{" "}
        <a href={target} hrefLang={preferred} onClick={() => rememberLanguage(preferred!)}>{m.language_hint_action({}, options)} <span aria-hidden="true">→</span></a>
      </p>
      <button type="button" aria-label={m.language_hint_dismiss({}, options)} onClick={() => { rememberLanguage(current); setDismissed(true); }}>
        <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18" /></svg>
      </button>
    </div>
  );
}
