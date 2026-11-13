import { artwork } from "../media/artwork";
import "./verified-story.css";

const pressSource = "https://commons.wikimedia.org/wiki/File:Buchdrucker-1568.png";

export function VerifiedStory() {
  return <section className="story-verified" id="verified-messages" aria-labelledby="verified-story-title">
    <div className="verified-story-inner">
      <div className="verified-story-heading">
        <p>Verified Messages</p>
        <h2 id="verified-story-title">Words travel.<br />Their story should too.</h2>
      </div>
      <div className="verified-story-layout">
        <div className="press-composition">
          <figure className="press-figure">
            <div className="press-art">
              <img src={artwork.printingPress.src} srcSet={artwork.printingPress.srcSet} sizes="(max-width: 760px) calc(100vw - 48px), 540px" width="751" height="879" loading="lazy" decoding="async" alt="Printers setting type and operating a hand press in Jost Amman’s 1568 woodcut." />
              <span className="press-at" aria-hidden="true">@</span>
              <svg className="press-signal" viewBox="0 0 540 560" fill="none" aria-hidden="true"><path d="M94 262H175L220 307H432V364" /><circle cx="94" cy="262" r="5" /><path d="M35 40V20H55M505 40V20H485" /></svg>
            </div>
          <article className="press-proof" aria-label="Illustrative Verified Message">
            <div className="press-proof-top"><span>Example proof</span><svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="6" y="10" width="12" height="10" rx="2" /><path d="M8 10V7A4 4 0 0 1 16 7V10" /></svg></div>
            <p className="press-proof-message">What if we tried<br />something different?</p>
            <p className="press-proof-signature">-typed with hush</p>
            <details>
              <summary>View the signed history <span aria-hidden="true">+</span></summary>
              <ol>
                <li><strong>Voice captured on the Mac</strong><span>Transcribed locally.</span></li>
                <li><strong>Local AI refinement disclosed</strong><span>Punctuation added, wording preserved.</span></li>
                <li><strong>Final wording signed and encrypted</strong><span>Recipient checks the record in their browser.</span></li>
              </ol>
              <p className="press-example-note">Illustration only. This is not a live proof.</p>
            </details>
          </article>
            <figcaption className="art-credit"><a href={pressSource} target="_blank" rel="noreferrer">The Printer</a><span>Jost Amman, 1568. Public domain.<br />Recoloured with digital overlays for hush.</span></figcaption>
          </figure>
        </div>
        <div className="verified-story-copy">
          <p className="verified-history">Gutenberg helped ideas travel through print. Social media put publishing in everyone’s hands. Now bots and AI can fill the feed, too.</p>
          <h3>Keep the freedom.<br />Give trust something<br />to stand on.</h3>
          <p>When a feed feels like machines talking to machines, let your message carry a history someone can check.</p>
          <p>With optional Verified Messages, share how your words were captured, edited and signed. Voice, typing and local AI edits stay distinct.</p>
          <ul className="verified-story-facts">
            <li><strong>Encrypted on your Mac before upload.</strong> Original audio stays local.</li>
            <li><strong>Verified in their browser.</strong> No account needed. hush never receives the key in your private link.</li>
          </ul>
          <a href="/verified-messages" className="verified-story-link">Explore Verified Messages <span aria-hidden="true">↗</span></a>
          <p className="verified-story-limit">Verifies signed capture and edit history. It does not prove identity, human presence or the truth of a claim.</p>
        </div>
      </div>
    </div>
  </section>;
}
