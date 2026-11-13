import { useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Lines } from "../i18n/Lines";
import { m } from "../paraglide/messages";
import "./download-handoff.css";

// Always share the public landing page, never the current URL or a private proof key.
const publicURL = "https://behu.sh/";
const emailURL = () => `mailto:?subject=${encodeURIComponent(m.handoff_email_subject())}&body=${encodeURIComponent(m.handoff_email_body({ url: publicURL }))}`;

export function DownloadHandoff({ onClose }: { onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const titleId = useId(), descriptionId = useId();
  const [status, setStatus] = useState("");
  const [sharing, setSharing] = useState(false);
  const link = useRef<HTMLInputElement>(null);
  useEffect(() => {
    const element = dialog.current!;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    element.showModal();
    return () => { element.close(); document.body.style.overflow = overflow; };
  }, []);

  async function share() {
    setSharing(true); setStatus("");
    try { await navigator.share({ title: m.handoff_share_title(), text: m.handoff_share_text(), url: publicURL }); }
    catch (error) {
      if (!(error instanceof DOMException && error.name === "AbortError")) setStatus(m.handoff_share_unavailable());
    } finally { setSharing(false); }
  }
  async function copy() {
    try { await navigator.clipboard.writeText(publicURL); setStatus(m.handoff_copied()); }
    catch { link.current?.focus(); link.current?.select(); setStatus(m.handoff_select()); }
  }

  return createPortal(<dialog ref={dialog} className="download-handoff" aria-labelledby={titleId} aria-describedby={descriptionId} onClose={onClose} onClick={event => {
    if (event.target !== event.currentTarget) return;
    const bounds = event.currentTarget.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) event.currentTarget.close();
  }}>
    <button className="handoff-close" type="button" aria-label={m.handoff_close()} onClick={() => dialog.current?.close()}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18" /></svg></button>
    <div className="handoff-device" aria-hidden="true"><svg viewBox="0 0 64 48"><rect x="10" y="5" width="44" height="30" rx="4" /><path d="M4 38h56l-5 5H9zM25 18v6m7-12v18m7-14v10" /></svg></div>
    <h2 id={titleId}>{m.handoff_title()}</h2>
    <p id={descriptionId}>{m.handoff_body()}</p>
    <div className="handoff-actions">
      {typeof navigator.share === "function" && <button type="button" className="handoff-primary" disabled={sharing} onClick={share}>{m.handoff_share()}<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 15V3m-4 4 4-4 4 4M7 11H4v10h16V11h-3" /></svg></button>}
      <a href={emailURL()} className={typeof navigator.share === "function" ? "handoff-secondary" : "handoff-primary"}>{m.handoff_email()}<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2" /><path d="m3 6 9 7 9-7" /></svg></a>
      <div className="handoff-copy"><input ref={link} aria-label={m.handoff_link_label()} value={publicURL} readOnly onFocus={event => event.currentTarget.select()} /><button type="button" onClick={copy}>{m.handoff_copy()}</button></div>
    </div>
    <p className="handoff-status" role="status">{status}</p>
    <p className="handoff-note"><Lines text={m.handoff_note()} /></p>
  </dialog>, document.body);
}
