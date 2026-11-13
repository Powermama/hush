// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { blogCopy } from "../../shared/blog";
import { blogPosts } from "../../shared/blog-posts.generated";
import { notFoundPages, type SiteLanguage } from "../../shared/site";
import { ButtonLink } from "../components/ButtonLink";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { HushMascot } from "../landing/HushMascot";
import { Footer } from "../layout/Footer";
import { Header } from "../layout/Header";
import { m } from "../paraglide/messages";
import { getLocale } from "../paraglide/runtime";
import "./not-found.css";

/** Shown for every unknown address; the server sends it with status 404. */
export function NotFoundPage() {
  const language = getLocale() as SiteLanguage;
  const hasBlog = blogPosts.some((post) => post.lang === language);
  return (
    <div className="min-h-screen bg-canvas text-ink">
      <DocumentMetadata {...notFoundPages[language]} />
      <Header />
      <main className="not-found-main" aria-labelledby="not-found-title">
        <div className="not-found-mascot"><HushMascot state="sad" /></div>
        <p className="not-found-code">{m.not_found_code()}</p>
        <h1 id="not-found-title">{m.not_found_title()}</h1>
        <p className="not-found-body">{m.not_found_body()}</p>
        <div className="not-found-actions">
          <ButtonLink href={language === "de" ? "/de" : "/"}>{m.not_found_home()}</ButtonLink>
          {hasBlog && <ButtonLink variant="secondary" href={blogCopy[language].indexPath}>{m.not_found_blog()}</ButtonLink>}
        </div>
      </main>
      <Footer />
    </div>
  );
}
