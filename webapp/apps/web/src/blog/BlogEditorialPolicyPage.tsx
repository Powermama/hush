// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { blogCopy, editorialPolicyPath, type BlogLanguage } from "../../shared/blog";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { Footer } from "../layout/Footer";
import { BlogArrow, BlogHeader } from "./BlogArticlePage";
import { BlogDownloadBand } from "./BlogDownloadBand";
import "./blog.css";

type Section = { heading: string; body: string[] };

// How articles are made. Every statement here describes a step the blog
// pipeline or the hush-seo skill actually enforces; keep them in sync.
const policy: Record<BlogLanguage, { lead: string; sections: Section[] }> = {
  en: {
    lead: "How we research, test, write and correct the articles on the hush blog.",
    sections: [
      { heading: "Who writes", body: [
        "Every article is signed by a named author with a public profile. It shows the publication date and, once something changes, the date of the last update.",
      ] },
      { heading: "How we research", body: [
        "We start from the questions people actually search for. Facts come from primary sources: Apple's documentation, official vendor pages, model cards, papers and laws. Pages of other dictation apps are cited only for what those apps say about themselves.",
        "Every article ends with its sources and the date we accessed each one.",
      ] },
      { heading: "How we test", body: [
        "When an article says we tested something, we ran it ourselves, and the article names the Mac, the macOS version and the date. When a step relies only on documentation, the article says so.",
        "Screenshots come from our own test Mac, cropped to what matters, with nothing personal left in them.",
      ] },
      { heading: "How we use AI", body: [
        "AI tools help with research and drafting. Before an article is published, the author checks every claim, step and number against the sources and is responsible for the result. We do not publish unreviewed AI text.",
      ] },
      { heading: "hush in our articles", body: [
        "hush is our own product. We mention it where it is a fair answer to the question, say what it does not do, and describe other tools accurately. There are no affiliate links and no paid placements.",
      ] },
      { heading: "Corrections and updates", body: [
        "If something is wrong or out of date, write to hello@behu.sh. We correct it, update the article's date and, for substantial changes, note what changed.",
      ] },
      { heading: "Languages", body: [
        "English and German articles are written separately for each audience. They are not translations of each other.",
      ] },
    ],
  },
  de: {
    lead: "Wie die Artikel im hush Blog recherchiert, getestet, geschrieben und korrigiert werden.",
    sections: [
      { heading: "Wer schreibt", body: [
        "Jeder Artikel ist von einer namentlich genannten Person mit öffentlichem Profil gezeichnet. Er zeigt das Veröffentlichungsdatum und nach Änderungen das Datum der letzten Aktualisierung.",
      ] },
      { heading: "Wie recherchiert wird", body: [
        "Ausgangspunkt sind die Fragen, nach denen tatsächlich gesucht wird. Fakten stammen aus Primärquellen: Apple-Dokumentation, offizielle Herstellerseiten, Modellkarten, Fachartikel und Gesetze. Seiten anderer Diktier-Apps werden nur für Angaben zu diesen Apps selbst zitiert.",
        "Am Ende jedes Artikels stehen die Quellen mit dem jeweiligen Abrufdatum.",
      ] },
      { heading: "Wie getestet wird", body: [
        "Steht in einem Artikel, dass etwas getestet wurde, lief der Test auf eigener Hardware; der Artikel nennt Mac, macOS-Version und Datum. Beruht ein Schritt nur auf Dokumentation, steht das im Artikel.",
        "Screenshots stammen vom eigenen Test-Mac, zugeschnitten auf das Wesentliche und ohne persönliche Daten.",
      ] },
      { heading: "Wie KI genutzt wird", body: [
        "KI-Werkzeuge helfen bei Recherche und Entwurf. Vor der Veröffentlichung prüft der Autor jede Aussage, jeden Schritt und jede Zahl anhand der Quellen und verantwortet das Ergebnis. Ungeprüfte KI-Texte werden nicht veröffentlicht.",
      ] },
      { heading: "hush in den Artikeln", body: [
        "hush ist das eigene Produkt. Es wird dort erwähnt, wo es eine faire Antwort auf die Frage ist, mit seinen Grenzen, und andere Werkzeuge werden korrekt beschrieben. Es gibt keine Affiliate-Links und keine bezahlten Platzierungen.",
      ] },
      { heading: "Korrekturen und Aktualisierungen", body: [
        "Fehler oder veraltete Angaben bitte an hello@behu.sh melden. Sie werden korrigiert, das Datum des Artikels wird aktualisiert, und bei größeren Änderungen steht im Artikel, was sich geändert hat.",
      ] },
      { heading: "Sprachen", body: [
        "Englische und deutsche Artikel entstehen getrennt für ihr jeweiliges Publikum. Sie sind keine Übersetzungen voneinander.",
      ] },
    ],
  },
};

export function BlogEditorialPolicyPage({ lang }: { lang: BlogLanguage }) {
  const copy = blogCopy[lang];
  const content = policy[lang];
  return (
    <div className="min-h-screen bg-canvas text-ink" lang={lang}>
      <DocumentMetadata title={copy.editorialTitle} description={content.lead} canonicalPath={editorialPolicyPath(lang)} language={lang} />
      <BlogHeader lang={lang} />
      <main className="blog-article-main">
        {/* Same layout as an article: the way back sits in the left margin. */}
        <article className="blog-article blog-policy" aria-labelledby="policy-title">
          <a className="blog-back" href={copy.indexPath}><BlogArrow direction="back" />{copy.allArticles}</a>
          <header className="blog-article-header">
            <h1 id="policy-title">{copy.editorialHeading}</h1>
            <p className="blog-policy-lead">{content.lead}</p>
          </header>
          <div className="blog-body blog-prose">
            {content.sections.map((section) => (
              <section key={section.heading}>
                <h2>{section.heading}</h2>
                {section.body.map((paragraph) => <p key={paragraph}>{paragraph}</p>)}
              </section>
            ))}
          </div>
        </article>
      </main>
      <BlogDownloadBand lang={lang} />
      <Footer />
    </div>
  );
}
