// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { useState } from "react";
import { siX } from "simple-icons";
import { type BlogLanguage } from "@hush/article/taxonomy";
import { blogCopy } from "../../shared/blog";
import { siteOrigin } from "../../shared/site";
import { useBrowserValue } from "../components/useBrowserValue";

/**
 * Share actions for an article: the system share sheet where touch devices
 * offer one, otherwise copy link, LinkedIn, X and email. Plain links, so they
 * work before hydration and without JavaScript.
 */
export function BlogShare({ lang, path, title, className = "" }: { lang: BlogLanguage; path: string; title: string; className?: string }) {
  const copy = blogCopy[lang];
  const url = `${siteOrigin}${path}`;
  const [status, setStatus] = useState("");
  const nativeShare = useBrowserValue(() => typeof navigator.share === "function" && matchMedia("(pointer: coarse)").matches, false);

  async function copyLink() {
    try { await navigator.clipboard.writeText(url); setStatus(copy.linkCopied); }
    catch { setStatus(url); }
    setTimeout(() => setStatus(""), 2400);
  }

  return (
    <div className={`blog-share ${className}`}>
      <p className="blog-share-title">{copy.share}</p>
      <div className="blog-share-actions">
        {nativeShare
          ? (
            <button type="button" className="blog-share-native" onClick={() => navigator.share({ title, url }).catch(() => {})}>
              <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 15V3m0 0L7.5 7.5M12 3l4.5 4.5M7 11H5.5A1.5 1.5 0 0 0 4 12.5v7A1.5 1.5 0 0 0 5.5 21h13a1.5 1.5 0 0 0 1.5-1.5v-7a1.5 1.5 0 0 0-1.5-1.5H17" /></svg>
              {copy.share}
            </button>
          )
          : (
            <>
              <button type="button" onClick={copyLink} aria-label={copy.copyLink} title={copy.copyLink}>
                <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1 1M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1-1" /></svg>
              </button>
              <a href={`https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(url)}`} target="_blank" rel="noopener" aria-label={copy.shareOn("LinkedIn")} title={copy.shareOn("LinkedIn")}>
                <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="3.5" width="17" height="17" rx="3" /><path d="M8 10.5V16M8 7.8v.1M11.5 16v-5.5M11.5 13c0-1.6 1-2.6 2.3-2.6s2.2.9 2.2 2.6v3" /></svg>
              </a>
              <a href={`https://x.com/intent/post?url=${encodeURIComponent(url)}&text=${encodeURIComponent(title)}`} target="_blank" rel="noopener" aria-label={copy.shareOn("X")} title={copy.shareOn("X")}>
                <svg viewBox="0 0 24 24" aria-hidden="true" className="blog-share-filled"><path d={siX.path} transform="translate(4.5 4.5) scale(0.625)" /></svg>
              </a>
              <a href={`mailto:?subject=${encodeURIComponent(title)}&body=${encodeURIComponent(url)}`} aria-label={copy.shareByEmail} title={copy.shareByEmail}>
                <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5.5" width="17" height="13" rx="2.5" /><path d="m4.5 7 7.5 6 7.5-6" /></svg>
              </a>
            </>
          )}
      </div>
      <p className="blog-share-status" role="status">{status}</p>
    </div>
  );
}
