import { AppleIcon } from "../components/AppleIcon";
import { DownloadLink } from "../components/DownloadExperience";
import { HushMascotArtwork } from "../landing/HushMascot";
import { Header } from "../layout/Header";
import { AudioCapture } from "./components/AudioCapture";
import { MessageComparison } from "./components/MessageComparison";
import { OriginTimeline } from "./components/OriginTimeline";
import { ProofIcon } from "./components/ProofIcon";
import { TechnicalDetails } from "./components/TechnicalDetails";
import { TextTransformation } from "./components/TextTransformation";
import { VerificationBadge } from "./components/VerificationBadge";
import type { VerifiedProof } from "./crypto";
import { useProofVerification } from "./useProofVerification";
import "./proof.css";

export function ProofPage({ slug }: { slug: string }) {
  const state = useProofVerification(slug);
  return (
    <div className="proof-page">
      <Header />
      <main className="proof-main">
        {state.status === "loading" && <LoadingState />}
        {state.status === "valid" && <ValidProof proof={state.proof} />}
        {state.status === "expired" && <UnavailableState tone="warning" title="This proof expired" detail="The author chose a limited lifetime and the encrypted message is no longer available." />}
        {state.status === "revoked" && <UnavailableState tone="warning" title="The author revoked this proof" detail="hush no longer serves this encrypted message." />}
        {state.status === "missing_key" && <UnavailableState tone="neutral" title="This private proof link is incomplete" detail="Ask the sender to copy the complete private hush link, including everything after the # symbol." />}
        {state.status === "invalid" && <UnavailableState tone="invalid" title="This message could not be verified" detail={state.message} />}
      </main>
      <footer className="proof-footer">
        <p>Proof contents decrypt in this browser. hush does not receive the message key.</p>
        <a href="/datenschutz">Privacy</a>
      </footer>
    </div>
  );
}

function ValidProof({ proof }: { proof: VerifiedProof }) {
  const { manifest } = proof;
  const source = manifest.capture.source;
  const hasAI = manifest.transformations.some(item => item.kind === "local_ai") || manifest.provenanceEvents?.some(event => event.kind === "local_ai_refined");
  const hasManualEdit = manifest.transformations.some(item => item.kind === "manual_hush_edit") || manifest.provenanceEvents?.some(event => event.kind === "manual_edit");
  const hasVoice = source === "microphone" || Boolean(manifest.voiceSegments?.length) || manifest.provenanceEvents?.some(event => event.kind === "voice_capture" || event.kind === "voice_section_added");
  const sourceLabel = source === "microphone" ? "Created from voice" : source === "keyboard" ? "Typed in hush" : "Edited in hush";
  return (
    <>
      <section className="proof-message" aria-label="Verified message">
        <div className="proof-message-top">
          <VerificationBadge tone="valid" title="Verified hush message" detail="The signed capture and edit record matches." />
          <span className="proof-private-label"><ProofIcon kind="lock" />Private proof</span>
        </div>
        <div className="proof-author-row">
          <span className="proof-author-avatar" aria-hidden="true">{manifest.author?.displayName?.trim().slice(0, 1).toLocaleUpperCase() || "?"}</span>
          <Author manifest={manifest} />
        </div>
        <blockquote className="proof-message-text">{manifest.finalText}</blockquote>
        <div className="proof-message-bottom">
          <ul className="proof-facts" aria-label="Recorded message attributes">
            <li data-kind={source === "microphone" ? "voice" : "text"}><ProofIcon kind={source === "microphone" ? "voice" : source === "keyboard" ? "text" : "revision"} />{sourceLabel}</li>
            {hasAI && <li data-kind="ai"><ProofIcon kind="ai" />Local AI disclosed</li>}
            {hasManualEdit && <li data-kind="manual"><ProofIcon kind="manual" />Manual edits recorded</li>}
          </ul>
          <button type="button" className="proof-history-link" onClick={() => {
            const history = document.getElementById("message-history");
            history?.focus({ preventScroll: true });
            history?.scrollIntoView({ block: "start" });
          }}>Explore its history <span aria-hidden="true">↓</span></button>
        </div>
      </section>

      <p className="proof-trust-note">Verifies the signed history, not the author's identity or the truth of the message.</p>

      <div className="proof-evidence">
        <section className="proof-history" id="message-history" tabIndex={-1} aria-labelledby="history-title">
          <h2 id="history-title">How this message was made</h2>
          <p className="proof-section-intro">{manifest.version === 2 ? "The complete history recorded in this signed proof." : "The steps preserved in this older proof. Individual event times may be unavailable."}</p>
          <OriginTimeline manifest={manifest} />
        </section>
        <aside className="proof-wording" aria-label="Message wording and comparison">
          <h2>Follow the wording.</h2>
          <p className="proof-section-intro">See what changed before these words were signed.</p>
          <TextTransformation manifest={manifest} />
          {manifest.aiEditShare !== undefined && hasAI && <p className="proof-ai-share">Recorded AI edit share <strong>{Math.round(manifest.aiEditShare * 100)}%</strong></p>}
          {manifest.capture.audio ? <AudioCapture audio={manifest.capture.audio} /> : hasVoice ? <p className="proof-audio-note"><ProofIcon kind="lock" /><span>Original audio was not shared.<br />The signed recording history is included.</span></p> : null}
          <MessageComparison signedText={manifest.finalText} />
        </aside>
      </div>

      <section className="proof-invitation" aria-labelledby="invitation-title">
        <div className="proof-hushy" aria-hidden="true"><HushMascotArtwork state="listening" /></div>
        <div className="proof-invitation-copy">
          <h2 id="invitation-title">Give your words<br />a story, too.</h2>
          <p>Speak on your Mac. Share your words with a private record of how they came to be.</p>
        </div>
        <div className="proof-invitation-action">
          <DownloadLink variant="custom" className="proof-download"><AppleIcon />Download for Mac</DownloadLink>
          <span>Free alpha · Apple silicon · macOS 15+</span>
          <a href="/verified-messages">Discover verified messages</a>
        </div>
      </section>

      {manifest.activitySnapshot && <details className="proof-profile">
        <summary>Author's signed hush activity</summary>
        <p>{manifest.activitySnapshot.totalWordsSpoken.toLocaleString()} words spoken. {formatSavedTime(manifest.activitySnapshot.estimatedTimeSavedSeconds)} saved.</p>
        <p>This optional snapshot was signed when the message was created.</p>
      </details>}
      <TechnicalDetails proof={proof} />
    </>
  );
}

function Author({ manifest }: { manifest: VerifiedProof["manifest"] }) {
  return (
    <div className="proof-author">
      <p>{manifest.author?.displayName || "Anonymous author"}{manifest.author?.displayName && manifest.author.identityKind === "self_declared" && <> <span>self-declared</span></>}</p>
      <time dateTime={manifest.createdAt}>Signed {new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(manifest.createdAt))}</time>
    </div>
  );
}

function LoadingState() {
  return (
    <section className="proof-unavailable" aria-busy="true">
      <VerificationBadge tone="neutral" title="Verifying private proof" detail="Checking signatures and decrypting this message in your browser." />
      <div className="proof-loading-lines" aria-hidden="true"><span /><span /></div>
    </section>
  );
}

function UnavailableState({ tone, title, detail }: { tone: "warning" | "invalid" | "neutral"; title: string; detail: string }) {
  return (
    <section className="proof-unavailable">
      <VerificationBadge tone={tone} title={title} detail={detail} />
      <div className="proof-unavailable-help">
        <p>Only a complete, valid signed record receives a verified status.</p>
        <a href="/verified-messages">Learn how hush verification works</a>
      </div>
    </section>
  );
}

function formatSavedTime(seconds: number): string {
  if (seconds >= 3600) {
    const hours = seconds / 3600;
    return `${hours >= 10 ? Math.round(hours) : hours.toFixed(1)} hours`;
  }
  return `${Math.max(1, Math.round(seconds / 60))} minutes`;
}
