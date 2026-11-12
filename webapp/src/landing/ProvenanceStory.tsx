import { artwork } from "../media/artwork";
import "./provenance.css";

const pressSource = "https://commons.wikimedia.org/wiki/File:Buchdrucker-1568.png";

function PrintingPress({ decorative = false }: { decorative?: boolean }) {
  return <img
    src={artwork.printingPress.src}
    srcSet={artwork.printingPress.srcSet}
    sizes="(max-width: 760px) 65vw, 420px"
    width="751" height="879" loading="lazy" decoding="async"
    alt={decorative ? "" : "Printers setting type and working a press in Jost Amman’s 1568 woodcut, reinterpreted in blue ink on a pale collage."}
  />;
}

/** An editorial collage, not a live verification result or an identity claim. */
export function ProvenanceStory() {
  return <section className="story-provenance" aria-labelledby="provenance-title">
    <svg className="story-filters" aria-hidden="true" width="0" height="0">
      <defs>
        <filter id="hush-art-print" colorInterpolationFilters="sRGB">
          <feColorMatrix type="saturate" values="0" />
          <feComponentTransfer>
            <feFuncR type="table" tableValues="0.10 0.90" />
            <feFuncG type="table" tableValues="0.19 0.94" />
            <feFuncB type="table" tableValues="0.38 0.99" />
          </feComponentTransfer>
        </filter>
      </defs>
    </svg>

    <div className="provenance-inner">
      <div className="provenance-opening">
        <h2 id="provenance-title">Reality has<br />a copy problem.</h2>
        <div className="provenance-intro">
          <p>The internet gave everyone a voice.<br />Now everything has an echo.</p>
        </div>
      </div>

      <figure className="provenance-figure">
        <div className="provenance-collage">
          <div className="press-art"><PrintingPress /></div>
          <div className="press-echo" aria-hidden="true"><PrintingPress decorative /></div>

          <div className="provenance-noise" aria-hidden="true">
            <span className="noise-repost">repost / rewrite / repeat / repost</span>
            <span className="noise-human">human?</span>
            <span className="noise-machine">generated.</span>
            <span className="noise-question"><span>Who</span><span>said that?</span></span>
            <span className="noise-copy">copy of a copy of a copy</span>
            <span className="noise-bot">bot?</span>
            <span className="noise-origin">original source unknown</span>
          </div>

          <svg className="provenance-face" viewBox="0 0 240 300" fill="none" aria-hidden="true">
            <defs>
              <clipPath id="provenance-face-cut"><path d="M120 24C66 24 42 65 46 113L54 177C59 218 85 254 120 269C155 254 181 218 186 177L194 113C198 65 174 24 120 24Z" /></clipPath>
            </defs>
            <path className="face-outline" d="M120 24C66 24 42 65 46 113L54 177C59 218 85 254 120 269C155 254 181 218 186 177L194 113C198 65 174 24 120 24Z" />
            <g className="face-wire" clipPath="url(#provenance-face-cut)">
              <path d="M120 24V269M143 24V269M166 24V269M189 24V269M120 58H210M120 83H210M120 108H210M120 133H210M120 158H210M120 183H210M120 208H210M120 233H210" />
              <path d="M120 24 194 113 120 269M120 58 186 177 120 233M120 108 166 208M143 24 120 83 189 158" />
            </g>
            <g className="face-features">
              <path d="M65 121Q83 109 102 121M70 128Q83 136 96 128M111 138 102 176 115 180M89 209Q103 215 120 212M58 164Q70 183 86 188" />
              <path d="M138 119h28v11h-28zM132 207h28" />
            </g>
            <path className="face-offset" d="M181 67h35v15h-29M165 183h46v12h-49M40 94h25" />
          </svg>

          <svg className="provenance-thread" viewBox="0 0 1100 520" preserveAspectRatio="none" fill="none" aria-hidden="true">
            <path className="thread-echo" d="M80 277H340C460 277 430 112 565 112H875C1005 112 1020 365 865 365H675C590 365 550 395 550 462V520" />
            <path className="thread-main" d="M80 270H340C460 270 430 105 565 105H875C1005 105 1020 365 865 365H675C590 365 550 395 550 462V520" />
            <circle cx="80" cy="270" r="4" />
          </svg>
          <span className="press-imprint" aria-hidden="true">From ink to infinity.</span>
        </div>
        <figcaption className="art-credit provenance-credit">
          <a href={pressSource} target="_blank" rel="noreferrer">The printing press, 1568</a>
          <span>Jost Amman. Public domain.</span>
        </figcaption>
      </figure>

      <div className="provenance-resolution">
        <h3>Give your words<br />their story back.</h3>
        <a className="provenance-link" href="/verified-messages">Discover Verified Messages<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M7 17 17 7M7 7h10v10" /></svg></a>
      </div>
    </div>
  </section>;
}
