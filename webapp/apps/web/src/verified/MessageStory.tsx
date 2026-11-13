import { artwork } from "../media/artwork";
import { useEffect, useRef, useState, type CSSProperties } from "react";
import { HushMascotArtwork } from "../landing/HushMascot";
import "./message-story.css";

const DURATION = 15_000;
const STAGES = ["Record", "Share", "Verify"] as const;
const TRANSCRIPT = "let’s build something that matters";
const MESSAGE = "Let’s build something that matters, together.";

function Lock() {
  return <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="5" y="10" width="14" height="11" rx="3" /><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3" /></svg>;
}

/** One finite illustration. The clock runs only while the window is visible. */
export function MessageStory() {
  const windowRef = useRef<HTMLDivElement>(null);
  const proofRef = useRef<HTMLElement>(null);
  const focusProof = useRef(false);
  const [reducedMotion, setReducedMotion] = useState(false);
  const [elapsed, setElapsed] = useState(reducedMotion ? DURATION : 0);
  const elapsedRef = useRef(elapsed);
  const [playing, setPlaying] = useState(!reducedMotion);
  const [visible, setVisible] = useState(false);
  const [pageVisible, setPageVisible] = useState(true);
  const phase = Math.min(2, Math.floor(elapsed / 5_000));
  const running = playing && visible && pageVisible && !reducedMotion;

  useEffect(() => {
    const node = windowRef.current;
    if (!node) return;
    const observer = new IntersectionObserver(([entry]) => setVisible(entry.isIntersecting && entry.intersectionRatio >= .45), { threshold: [0, .45] });
    observer.observe(node);
    const motion = matchMedia("(prefers-reduced-motion: reduce)");
    function preference() {
      setReducedMotion(motion.matches);
      if (motion.matches) {
        setPlaying(false);
        elapsedRef.current = DURATION;
        setElapsed(DURATION);
      }
    }
    function visibility() { setPageVisible(!document.hidden); }
    preference();
    visibility();
    motion.addEventListener("change", preference);
    document.addEventListener("visibilitychange", visibility);
    return () => {
      observer.disconnect();
      motion.removeEventListener("change", preference);
      document.removeEventListener("visibilitychange", visibility);
    };
  }, []);

  useEffect(() => {
    if (!running) return;
    let frame = 0;
    let previous = performance.now();
    let published = previous;
    function tick(now: number) {
      elapsedRef.current = Math.min(DURATION, elapsedRef.current + now - previous);
      previous = now;
      if (now - published >= 80 || elapsedRef.current === DURATION) {
        published = now;
        setElapsed(elapsedRef.current);
      }
      if (elapsedRef.current < DURATION) frame = requestAnimationFrame(tick);
      else setPlaying(false);
    }
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [running]);

  useEffect(() => {
    if (phase === 2 && focusProof.current) {
      focusProof.current = false;
      proofRef.current?.focus({ preventScroll: true });
    }
  }, [phase]);

  function selectStage(index: number) {
    setPlaying(false);
    elapsedRef.current = index * 5_000;
    setElapsed(elapsedRef.current);
  }

  function togglePlayback() {
    if (elapsedRef.current >= DURATION) {
      elapsedRef.current = 0;
      setElapsed(0);
      setPlaying(true);
    } else setPlaying(value => !value);
  }

  const playbackLabel = elapsed >= DURATION ? "Replay illustration" : playing ? "Pause illustration" : "Play illustration";
  const wordsVisible = !playing ? 6 : Math.min(6, Math.floor(elapsed / 480) + 1);

  return <section className="message-story" aria-labelledby="message-story-title">
    <div className="message-story-composition">
      <div className="message-story-art">
        <h2 id="message-story-title">Let your words<br />carry their story.</h2>
        <figure>
          <img src={artwork.twitteringMachine.src} srcSet={artwork.twitteringMachine.srcSet} sizes="(max-width: 760px) 100vw, 620px" width="994" height="1350" loading="lazy" decoding="async" alt="Paul Klee’s mechanical birds, recoloured in blue and rose." />
          <figcaption><a href="https://commons.wikimedia.org/wiki/File:Die_Zwitscher-Maschine_(Twittering_Machine),_1922_-_Paul_Klee.jpg" target="_blank" rel="noreferrer">Twittering Machine · Paul Klee, 1922.</a><br />Public domain. Recoloured for hush.</figcaption>
        </figure>
      </div>

      <div className="message-story-player" data-running={running} data-phase={STAGES[phase].toLowerCase()}>
        <div className="message-story-window" ref={windowRef} onFocusCapture={() => setPlaying(false)}>
          <div className="message-story-chrome"><span>{phase === 1 && <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m12 5-7 7 7 7M5 12h15" /></svg>}{["hush", "Post", "Private proof"][phase]}</span><span>Illustration</span></div>
          <div key={phase} className="message-story-scene" id="message-story-scene" role="group" aria-label={`${STAGES[phase]} illustration`}>
            {phase === 0 && <div className="message-record">
              <div className="message-record-state"><span aria-hidden="true" />Listening on your Mac</div>
              <blockquote aria-label={TRANSCRIPT}>{TRANSCRIPT.split(" ").map((word, index) => <span key={index} aria-hidden="true" className={index < wordsVisible ? "is-spoken" : ""}>{word} </span>)}</blockquote>
              <div className="message-wave" aria-hidden="true">{Array.from({ length: 36 }, (_, i) => <span key={i} style={{ "--bar-height": `${8 + Math.sin(i * 1.7) ** 2 * Math.sin(i / 35 * Math.PI) ** 2 * 54}px`, "--bar-delay": `${i * -110}ms` } as CSSProperties} />)}</div>
              <div className="message-record-time"><Lock /><span>Audio stays here<time dateTime="2026-11-04T10:42:08Z">10:42:08 UTC</time></span></div>
            </div>}

            {phase === 1 && <div className="message-social" aria-label="Illustrative shared message">
              <div className="message-social-author"><span className="message-avatar" role="img" aria-label="hushy, the hush mascot"><HushMascotArtwork state="listening" portrait /></span><div><strong>hushy</strong><span>@heyhush</span></div><svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.5" /><circle cx="12" cy="12" r="1.5" /><circle cx="19" cy="12" r="1.5" /></svg></div>
              <p className="message-post-content">{MESSAGE}{" "}<a className="message-signature" href="#message-example-proof" onClick={event => { event.preventDefault(); focusProof.current = true; selectStage(2); }}>
                - verified by hush
                {running && <svg className="message-click-cursor" viewBox="0 0 30 36" aria-hidden="true"><path d="M4 3v26l7-7 6 11 5-3-6-10h10Z" fill="#1c3741" stroke="white" strokeWidth="2" /></svg>}
              </a></p>
              <p className="message-post-meta"><time dateTime="2026-11-04T10:42:27Z">10:42 AM · Nov 4, 2026</time><span aria-hidden="true"> · </span><span><strong>1,204</strong> Views</span></p>
              <div className="message-social-footer" aria-hidden="true"><span><svg viewBox="0 0 24 24" fill="none"><path d="M20 11a8 8 0 0 1-8 8H4l2-4a8 8 0 1 1 14-4Z" /></svg>12</span><span><svg viewBox="0 0 24 24" fill="none"><path d="m7 3-4 4 4 4M3 7h12a4 4 0 0 1 4 4M17 21l4-4-4-4m4 4H9a4 4 0 0 1-4-4" /></svg>3</span><span><svg viewBox="0 0 24 24" fill="none"><path d="m12 20-8-8C-2 5 8 0 12 7c4-7 14-2 8 5Z" /></svg>28</span><svg viewBox="0 0 24 24" fill="none"><path d="M6 3h12v18l-6-4-6 4Z" /></svg><svg viewBox="0 0 24 24" fill="none"><path d="M5 14v6h14v-6M12 16V3m-5 5 5-5 5 5" /></svg></div>
            </div>}

            {phase === 2 && <article ref={proofRef} id="message-example-proof" className="message-proof" tabIndex={-1} aria-label="Illustrative Verified Message">
              <div className="message-proof-status"><span aria-hidden="true">✓</span><div><h3>Verified hush message</h3><p>The signed history matches.</p></div></div>
              <blockquote>{MESSAGE}</blockquote>
              <ol className="message-history">
                <li><span>Voice captured in hush</span><time dateTime="2026-11-04T10:42:08Z">10:42:08 UTC</time></li>
                <li><span>Manual edit recorded</span><time dateTime="2026-11-04T10:42:26Z">10:42:26 UTC</time></li>
                <li><span>Final wording signed</span><time dateTime="2026-11-04T10:42:27Z">10:42:27 UTC</time></li>
              </ol>
              <p className="message-browser-note"><Lock />Decrypted in your browser. No audio attached.</p>
            </article>}
          </div>
        </div>
        <div className="message-story-controls" role="group" aria-label="Message story controls">
          {STAGES.map((stage, index) => <button key={stage} type="button" aria-pressed={phase === index} aria-controls="message-story-scene" onClick={() => selectStage(index)} style={{ "--stage-progress": `${Math.max(0, Math.min(1, (elapsed - index * 5_000) / 5_000)) * 100}%` } as CSSProperties}>{stage}<span aria-hidden="true" /></button>)}
          {!reducedMotion && <button className="message-playback" type="button" aria-label={playbackLabel} onClick={togglePlayback}><svg viewBox="0 0 24 24" fill="none" aria-hidden="true">{elapsed >= DURATION ? <path d="M4 11a8 8 0 1 1 2 7M4 4v7h7" /> : playing ? <path d="M9 6v12M15 6v12" /> : <path d="m9 5 10 7-10 7Z" />}</svg></button>}
        </div>
      </div>
    </div>
    <div className="message-story-privacy">
      <p><Lock /><strong>Your audio stays on your Mac.</strong><span>Only your text and signed history travel, encrypted.</span></p>
    </div>
  </section>;
}
