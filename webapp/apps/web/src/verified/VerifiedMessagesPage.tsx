import { DocumentMetadata } from "../components/DocumentMetadata";
import { DownloadLink } from "../components/DownloadExperience";
import { DownloadIcon } from "../components/icons/DownloadIcon";
import { Header } from "../layout/Header";
import { Footer } from "../layout/Footer";
import { PortraitSculpture } from "./PortraitSculpture";
import { MessageStory } from "./MessageStory";
import "./verified-editorial.css";

export function VerifiedMessagesPage() {
  return <div className="verified-editorial">
    <DocumentMetadata title="Give your words a verifiable history - hush" description="Record in hush. Keep the recorded time and edits. Share a private link so someone else can verify the signed message history." canonicalPath="/verified-messages" />
    <a className="vm-skip" href="#vm-main">Skip to content</a>
    <Header currentPage="verified-messages" navigationLabel="Verified Messages navigation" />

    <main id="vm-main">
      <section className="vm-opening" aria-labelledby="vm-title">
        <div className="vm-opening-inner">
          <div className="vm-opening-copy">
            <h1 id="vm-title">Make your voice<br />more than a post.</h1>
            <p className="vm-opening-thought">In a feed full of bots and AI, share more than words. Let people check how your message began and what changed.</p>
          </div>
          <figure className="vm-portrait-figure">
            <div className="vm-portrait-art">
              <div className="vm-portrait-orbit" aria-hidden="true" />
              <div className="vm-matrix" aria-hidden="true">{["0101 1100 0010 1011", "copy / voice / copy", "1010 0011 0101 1010", "source ? source ?", "0110 0101 1100 0011"].map((line, i) => <span key={i}>{line}<br />{line}<br />{line}<br />{line}<br />{line}</span>)}</div>
              <PortraitSculpture />
              <span className="vm-question-one" aria-hidden="true">a person?</span>
              <span className="vm-question-two" aria-hidden="true">an imitation?</span>
            </div>
            <figcaption><a href="https://commons.wikimedia.org/wiki/File:Ameca_Generation_1.jpg" target="_blank" rel="noreferrer">Ameca · Willy Jackson.</a> Cropped, recoloured and fragmented.<br />Photo and treatment: <a href="https://creativecommons.org/licenses/by-sa/4.0/" target="_blank" rel="noreferrer">CC BY-SA 4.0</a>. No endorsement.</figcaption>
          </figure>
        </div>
      </section>

      <MessageStory />

      <section className="vm-finale" aria-labelledby="vm-finale-title">
        <h2 id="vm-finale-title">Your voice can<br />change the story.</h2>
        <DownloadLink variant="custom" className="vm-download"><DownloadIcon />Download hush</DownloadLink>
        <p>Verified Messages are optional.</p>
      </section>
    </main>
    <Footer />
  </div>;
}
