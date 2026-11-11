import { artwork } from "../media/artwork";

import { HushMascotArtwork, HushMascotGrip } from "./HushMascot";
import { ProvenanceStory } from "./ProvenanceStory";
import { FreedomBloom } from "./FreedomBloom";

const aristotleSource = "https://commons.wikimedia.org/wiki/File:Portrait_of_Aristotle,_set_on_a_restored_bust,_Colosseum.jpg";
const geographerSource = "https://commons.wikimedia.org/wiki/File:Johannes_Vermeer_-_The_Geographer_-_Google_Art_Project.jpg";
const libertySource = "https://commons.wikimedia.org/wiki/File:Eug%C3%A8ne_Delacroix_-_Liberty_Leading_the_People.jpeg";

function Portrait({ decorative = false }: { decorative?: boolean }) {
  return <img
    src={artwork.aristotle.src}
    srcSet={artwork.aristotle.srcSet}
    sizes="(max-width: 760px) 95vw, 650px"
    width="960" height="1000" loading="lazy" decoding="async"
    alt={decorative ? "" : "A marble portrait of Aristotle, reinterpreted in blue with offset collage strips."}
  />;
}

export function VisionStory() {
  return <div className="vision-story">
    <svg className="story-filters" aria-hidden="true" width="0" height="0">
      <defs>
        <filter id="hush-art-blue" colorInterpolationFilters="sRGB">
          <feColorMatrix type="saturate" values="0" />
          <feComponentTransfer>
            <feFuncR type="table" tableValues="0.055 0.79" />
            <feFuncG type="table" tableValues="0.20 0.94" />
            <feFuncB type="table" tableValues="0.37 0.93" />
          </feComponentTransfer>
        </filter>
        <filter id="hush-art-coral" colorInterpolationFilters="sRGB">
          <feColorMatrix type="saturate" values="0" />
          <feComponentTransfer>
            <feFuncR type="table" tableValues="0.06 1" />
            <feFuncG type="table" tableValues="0.12 0.73" />
            <feFuncB type="table" tableValues="0.22 0.66" />
          </feComponentTransfer>
        </filter>
      </defs>
    </svg>

    <div className="story-handoff" aria-hidden="true">
      <svg viewBox="0 0 1440 360" preserveAspectRatio="none"><g>{Array.from({ length: 11 }, (_, i) => <path key={i} d={`M${690 + i * 6} 0 C${690 + i * 6} 100 ${-320 + i * 140} 130 ${-260 + i * 175} 360`} />)}</g></svg>
      <span className="handoff-whisper">A thought doesn't fit in a box.</span>
    </div>
    <section className="story-thought" aria-labelledby="thought-title">
      <div className="thought-layout">
        <div className="thought-copy">
          <h2 id="thought-title"><span>Think</span><span>out loud.</span></h2>
          <p>Before the keyboard,<br />there was a voice.<br /><strong>Yours.</strong></p>
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
            <div className="thought-companion" role="img" aria-label="A small hush cameo peeking out from behind the marble collage."><HushMascotArtwork state="listening" peeking /></div>
            <div className="thought-companion-grip" aria-hidden="true"><HushMascotGrip /></div>
          </div>
          <figcaption><a href={aristotleSource} target="_blank" rel="noreferrer">Aristotle, reimagined in colour</a><span>Photograph by Szilas. Public domain.</span></figcaption>
        </figure>
        <div className="thought-annotation" aria-hidden="true"><span>Less input.</span><span>More instinct.</span></div>
      </div>
      <div className="story-bridge" aria-hidden="true"><span>Your voice is the interface.</span><svg viewBox="0 0 1200 170" fill="none"><path d="M0 90H170C220 90 220 20 255 20S300 150 340 150 375 0 420 0 465 165 510 165 545 45 580 45 615 100 660 100H1200" /></svg></div>
    </section>

    <section id="privacy" className="story-freedom" aria-labelledby="freedom-title">
      <figure className="freedom-figure">
        <div className="freedom-art">
          <img
            src={artwork.liberty.src}
            srcSet={artwork.liberty.srcSet}
            sizes="100vw" width="1280" height="1016" loading="lazy" decoding="async"
            alt="Delacroix’s Liberty Leading the People, reinterpreted in coral and ink blue."
          />
          <div className="freedom-image-echo" aria-hidden="true" />
          <span className="freedom-overprint" aria-hidden="true">liberté.</span>
          <div className="freedom-copy">
            <h2 id="freedom-title"><span>Keep your</span><span>mind yours.</span></h2>
            <p>Your ideas don't need permission.<br />Or a server on the other side of the world.</p>
          </div>
        </div>
        <figcaption className="art-credit freedom-credit"><a href={libertySource} target="_blank" rel="noreferrer">Liberty Leading the People</a><span>Eugène Delacroix, 1830. Public domain. Cropped and recoloured for hush.</span></figcaption>
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
              width="960" height="1076" loading="lazy" decoding="async"
              alt="A geographer pausing over a map beside a sunlit window, painted by Johannes Vermeer."
            />
            <div className="local-window-label"><span aria-hidden="true" /><span aria-hidden="true" /><span aria-hidden="true" /><b>your mind, locally</b><div className="window-companion" role="img" aria-label="hush thinking with you, integrated into the personal workspace."><HushMascotArtwork state="thinking" portrait /></div></div>
          </div>
          <figcaption className="art-credit"><a href={geographerSource} target="_blank" rel="noreferrer">The Geographer</a><span>Johannes Vermeer, 1669. Städel Museum. Public domain.<br />Cropped and composed with the hush character.</span></figcaption>
        </figure>
        <div className="intelligence-bloom"><FreedomBloom /></div>
        <div className="intelligence-copy">
          <h2 id="intelligence-title">Intelligence<br />on your terms.</h2>
          <p>Voice and AI, right on your Mac.<br />A place for your mind to wander.<br />And your ideas to grow.</p>
          <p className="privacy-detail">Online tasks still use the internet.<br />Sharing a Verified Message is optional.</p>
          <a href="/verified-messages" className="verified-link">Explore Verified Messages <span aria-hidden="true">↗</span></a>
        </div>
        <span className="bloom-annotation" aria-hidden="true">let it grow.</span>
      </div>
      <div className="open-source-manifesto"><h3>For the people.<br />By the people.</h3><div><p>Open source. Open possibilities.<br />Read it. Remix it. Make it yours.</p><a href="https://github.com/Powermama/hush" target="_blank" rel="noreferrer"><svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m8 6-6 6 6 6m8-12 6 6-6 6M14 3l-4 18" /></svg>Explore the source</a></div></div>
    </section>

    <ProvenanceStory />
  </div>;
}
