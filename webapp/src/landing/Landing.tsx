import { DownloadLink } from "../components/DownloadExperience";
import { useState } from "react";
import { siApple } from "simple-icons";
import { Header } from "../layout/Header";
import { Footer } from "../layout/Footer";
import { LocalUniverse, WaveMark } from "./LocalUniverse";
import { VisionStory } from "./VisionStory";
import "./landing.css";
import "./story.css";

const questions = [
  { question: "Will it work on my Mac?", answer: "hush needs an Apple silicon Mac (M1 or newer) running macOS 15 or later. An 8 GB Mac can run transcription. We recommend 16 GB for the optional AI assistant, with room for your other apps." },
  { question: "Does it work offline?", answer: "Once the models are downloaded, transcription, writing styles and local AI run on your Mac. Web searches, browsing, model downloads, updates and publishing optional Verified Messages need an internet connection." },
  { question: "What can the assistant do?", answer: "The assistant is in beta. It can use the current screen as context, help write or revise text, and perform supported actions in your apps. Hold Control + Fn to talk, follow up by voice, and press Escape to stop and start a fresh conversation. Complex tasks may still need your help." },
  { question: "Is hush free?", answer: "Yes. hush is free and open source, with no account required. The Mac app is Developer ID signed and notarized by Apple. You can read the source, contribute, or make it your own." },
];

function MacDownload() {
  return <DownloadLink variant="custom" className="landing-download"><svg viewBox="0 0 24 24" aria-hidden="true"><path d={siApple.path} fill="currentColor" /></svg>Download for Mac</DownloadLink>;
}

export function Landing() {
  // Present in the first React commit, before effects or the deferred scene load.
  const [initialOpening] = useState(() => matchMedia("(prefers-reduced-motion: reduce)").matches || scrollY >= 100 || location.hash || document.hidden ? "complete" : "pending");
  return <div className="hush-landing" id="top" data-opening={initialOpening}>
    <a className="landing-skip" href="#main">Skip to content</a>
    <Header />
    <main id="main">
      <section className="landing-hero" aria-labelledby="hero-title">
        <div className="hero-introduction">
          <h1 id="hero-title">The voice layer for your Mac.</h1>
          <p>Dictation, writing, and an assistant. All powered locally.</p>
        </div>
        <LocalUniverse />
        <div className="hero-download-area">
          <div className="hero-actions"><MacDownload /></div>
          <p className="download-requirements">Free alpha for Apple silicon Macs</p>
        </div>
      </section>
      <VisionStory />
      <div className="story-afterword">
        <section className="landing-faq" aria-labelledby="faq-title"><h2 id="faq-title">A few things<br />to know.</h2><div>{questions.map(item => <details key={item.question}><summary>{item.question}<span aria-hidden="true">+</span></summary><p>{item.answer}</p></details>)}</div></section>
        <section className="landing-final"><span className="final-imprint" aria-hidden="true">hush.</span><div className="final-mark"><WaveMark /></div><h2>Make room<br />for your voice.</h2><MacDownload /><a className="release-link" href="/releases">Notarized alpha. See what’s new.</a></section>
      </div>
    </main>
    <Footer />
  </div>;
}
