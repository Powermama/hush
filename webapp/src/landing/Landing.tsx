import { DownloadLink } from "../components/DownloadExperience";
import { useRef } from "react";
import { siApple } from "simple-icons";
import { Header } from "../layout/Header";
import { Footer } from "../layout/Footer";
import { LocalUniverse, WaveMark } from "./LocalUniverse";
import { useLandingEntrance } from "./useLandingEntrance";
import { VisionStory } from "./VisionStory";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { sitePages } from "../../shared/site";
import { Lines } from "../i18n/Lines";
import { m } from "../paraglide/messages";
import type { SiteLanguage } from "../../shared/site";
import "./landing.css";
import "./story.css";

const questions = [
  { question: m.faq_mac_q, answer: m.faq_mac_a },
  { question: m.faq_offline_q, answer: m.faq_offline_a },
  { question: m.faq_assistant_q, answer: m.faq_assistant_a },
  { question: m.faq_free_q, answer: m.faq_free_a },
];

function MacDownload() {
  return <DownloadLink variant="custom" className="landing-download"><svg viewBox="0 0 24 24" aria-hidden="true"><path d={siApple.path} fill="currentColor" /></svg>{m.download_for_mac()}</DownloadLink>;
}

/** The landing page; `/` in English and `/de` in German share one design. */
export function Landing({ lang = "en" }: { lang?: SiteLanguage }) {
  const root = useRef<HTMLDivElement>(null);
  useLandingEntrance(root);
  return <div className="hush-landing" id="top" data-opening="pending" ref={root}>
    <DocumentMetadata {...sitePages[lang === "de" ? "/de" : "/"]!} />
    <a className="landing-skip" href="#main">{m.skip_to_content()}</a>
    <Header progress />
    <main id="main">
      <section className="landing-hero" aria-labelledby="hero-title">
        <div className="hero-introduction">
          <h1 id="hero-title">{m.hero_title()}</h1>
          <p>{m.hero_lead()}</p>
        </div>
        <LocalUniverse />
        <div className="hero-download-area">
          <div className="hero-actions"><MacDownload /></div>
          <p className="download-requirements">{m.download_requirements()}</p>
        </div>
      </section>
      <VisionStory />
      <div className="story-afterword">
        <section className="landing-faq" aria-labelledby="faq-title"><h2 id="faq-title"><Lines text={m.faq_title()} /></h2><div>{questions.map(item => <details key={item.question()}><summary>{item.question()}<span aria-hidden="true">+</span></summary><p>{item.answer()}</p></details>)}</div></section>
        <section className="landing-final"><span className="final-imprint" aria-hidden="true">hush.</span><div className="final-mark"><WaveMark /></div><h2><Lines text={m.final_title()} /></h2><MacDownload /><a className="release-link" href="/releases">{m.final_release_link()}</a></section>
      </div>
    </main>
    <Footer />
  </div>;
}
