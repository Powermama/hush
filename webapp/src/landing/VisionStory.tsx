import { artwork } from "../media/artwork";

import { HushMascotArtwork, HushMascotGrip } from "./HushMascot";
import { ProvenanceStory } from "./ProvenanceStory";
import { FreedomBloom } from "./FreedomBloom";
import { Lines } from "../i18n/Lines";
import { m } from "../paraglide/messages";

const aristotleSource = "https://commons.wikimedia.org/wiki/File:Portrait_of_Aristotle,_set_on_a_restored_bust,_Colosseum.jpg";
const geographerSource = "https://commons.wikimedia.org/wiki/File:Johannes_Vermeer_-_The_Geographer_-_Google_Art_Project.jpg";
const libertySource = "https://commons.wikimedia.org/wiki/File:Eug%C3%A8ne_Delacroix_-_Liberty_Leading_the_People.jpeg";

function Portrait({ decorative = false }: { decorative?: boolean }) {
  return <img
    src={artwork.aristotle.src}
    srcSet={artwork.aristotle.srcSet}
    sizes="(max-width: 760px) 95vw, 650px"
    width="960" height="1000" loading="lazy" decoding="async" fetchPriority="low"
    alt={decorative ? "" : m.thought_portrait_alt()}
  />;
}

export function VisionStory() {
  return <div className="vision-story">
    <div className="story-handoff" aria-hidden="true">
      <svg viewBox="0 0 1440 360" preserveAspectRatio="none"><g>{Array.from({ length: 11 }, (_, i) => <path key={i} d={`M${690 + i * 6} 0 C${690 + i * 6} 100 ${-320 + i * 140} 130 ${-260 + i * 175} 360`} />)}</g></svg>
      <span className="handoff-whisper">{m.story_whisper()}</span>
    </div>
    <section className="story-thought" aria-labelledby="thought-title">
      <div className="thought-layout">
        <div className="thought-copy">
          <h2 id="thought-title"><span>{m.thought_title_1()}</span><span>{m.thought_title_2()}</span></h2>
          <p><Lines text={m.thought_body()} /><br /><strong>{m.thought_body_strong()}</strong></p>
        </div>
        <figure className="thought-figure">
          <div className="thought-art">
            <div className="thought-selection" aria-hidden="true"><i /><i /><i /><i /><span>human.original</span></div>
            <div className="portrait-base"><Portrait /></div>
            <div className="portrait-slice portrait-slice-one" aria-hidden="true"><Portrait decorative /></div>
            <div className="portrait-slice portrait-slice-two" aria-hidden="true"><Portrait decorative /></div>
            <svg className="thought-wave" viewBox="0 0 680 160" fill="none" aria-hidden="true">
              <path d="M0 80H105C130 80 130 30 145 30S160 130 175 130 190 5 205 5 220 155 235 155 250 38 265 38 280 112 295 112 310 80 330 80H680" />
            </svg>
            <div className="thought-companion" role="img" aria-label={m.thought_companion_label()}><HushMascotArtwork state="listening" peeking saturation={0.65} /></div>
            <div className="thought-companion-grip" aria-hidden="true"><HushMascotGrip /></div>
          </div>
          <figcaption><a href={aristotleSource} target="_blank" rel="noreferrer">{m.thought_credit_link()}</a><span>{m.thought_credit()}</span></figcaption>
        </figure>
        <div className="thought-annotation" aria-hidden="true"><span>{m.thought_annotation_1()}</span><span>{m.thought_annotation_2()}</span></div>
      </div>
      <div className="story-bridge" aria-hidden="true"><span>{m.story_bridge()}</span><svg viewBox="0 0 1200 170" fill="none"><path d="M0 90H170C220 90 220 20 255 20S300 150 340 150 375 0 420 0 465 165 510 165 545 45 580 45 615 100 660 100H1200" /></svg></div>
    </section>

    <section id="privacy" className="story-freedom" aria-labelledby="freedom-title">
      <figure className="freedom-figure">
        <div className="freedom-art">
          <img
            src={artwork.liberty.src}
            srcSet={artwork.liberty.srcSet}
            sizes="100vw" width="1280" height="1016" loading="lazy" decoding="async" fetchPriority="low"
            alt={m.freedom_alt()}
          />
          {/* An image rather than a CSS background, so it loads lazily and after the hero scene. */}
          <div className="freedom-image-echo" aria-hidden="true"><img src={artwork.libertyEcho.src} alt="" loading="lazy" decoding="async" fetchPriority="low" /></div>
          <span className="freedom-overprint" aria-hidden="true">liberté.</span>
          <div className="freedom-copy">
            <h2 id="freedom-title"><span>{m.freedom_title_1()}</span><span>{m.freedom_title_2()}</span></h2>
            <p><Lines text={m.freedom_body()} /></p>
          </div>
        </div>
        <figcaption className="art-credit freedom-credit"><a href={libertySource} target="_blank" rel="noreferrer">{m.freedom_credit_link()}</a><span>{m.freedom_credit()}</span></figcaption>
      </figure>
    </section>

    <section className="story-intelligence" aria-labelledby="intelligence-title">
      <div className="intelligence-layout">
        <figure className="intelligence-figure">
          <div className="intelligence-art">
            <img
              src={artwork.geographer.src}
              srcSet={artwork.geographer.srcSet}
              sizes="(max-width: 760px) 65vw, 380px"
              width="960" height="1076" loading="lazy" decoding="async" fetchPriority="low"
              alt={m.intelligence_alt()}
            />
            <div className="local-window-label"><span aria-hidden="true" /><span aria-hidden="true" /><span aria-hidden="true" /><b>{m.intelligence_window_label()}</b><div className="window-companion" role="img" aria-label={m.intelligence_companion_label()}><HushMascotArtwork state="thinking" portrait /></div></div>
          </div>
          <figcaption className="art-credit"><a href={geographerSource} target="_blank" rel="noreferrer">{m.intelligence_credit_link()}</a><span><Lines text={m.intelligence_credit()} /></span></figcaption>
        </figure>
        <div className="intelligence-bloom"><FreedomBloom /></div>
        <div className="intelligence-copy">
          <h2 id="intelligence-title"><Lines text={m.intelligence_title()} /></h2>
          <p><Lines text={m.intelligence_body()} /></p>
          <p className="privacy-detail"><Lines text={m.intelligence_privacy()} /></p>
          <a href="/verified-messages" className="verified-link">{m.intelligence_link()} <span aria-hidden="true">↗</span></a>
        </div>
        <span className="bloom-annotation" aria-hidden="true">{m.intelligence_annotation()}</span>
      </div>
      <div className="open-source-manifesto"><h3><Lines text={m.manifesto_title()} /></h3><div><p><Lines text={m.manifesto_body()} /></p><a href="https://github.com/Powermama/hush" target="_blank" rel="noreferrer"><svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m8 6-6 6 6 6m8-12 6 6-6 6M14 3l-4 18" /></svg>{m.manifesto_link()}</a></div></div>
    </section>

    <ProvenanceStory />
  </div>;
}
