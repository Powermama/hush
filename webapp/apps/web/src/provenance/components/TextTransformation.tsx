import { diffWordsWithSpace } from "diff";
import type { ProofManifest } from "../schema";

export function TextTransformation({ manifest }: { manifest: ProofManifest }) {
  const sourceText = manifest.transcription?.rawText ?? manifest.sourceText;
  if (!sourceText) return null;
  const parts = diffWordsWithSpace(sourceText, manifest.finalText);
  const changed = sourceText !== manifest.finalText;
  const usedLocalAI = manifest.transformations.some((item) => item.kind === "local_ai");
  const manuallyEdited = manifest.transformations.some(
    (item) => item.kind === "manual_hush_edit",
  );
  const finalLabel = usedLocalAI && manuallyEdited
    ? "Signed final message"
    : usedLocalAI
      ? "AI-refined message"
      : manuallyEdited
        ? "Signed edited message"
        : "Signed final message";
  const sourceLabel = manifest.capture.source === "microphone"
    ? "Original transcript"
    : manifest.capture.source === "keyboard"
      ? "First draft"
      : "Previous hush message";
  return (
    <details className="proof-transformation" open>
      <summary>
        {manifest.capture.source === "microphone"
          ? "Original transcript and changes"
          : "Original text and changes"}
        <span className="proof-chevron" aria-hidden="true">⌄</span>
      </summary>
      <div className="proof-wording-content">
        <p className="proof-wording-label">
          {sourceLabel}
        </p>
        <p className="proof-original-text">
          {sourceText}
        </p>
        {changed ? (
          <>
            <p className="proof-wording-label">
              {finalLabel}
            </p>
            <p className="proof-text-diff">
              {parts.map((part, index) => (
                <span
                  key={`${index}-${part.value.slice(0, 8)}`}
                  className={part.added ? "proof-word-added" : part.removed ? "proof-word-removed" : undefined}
                >
                  {part.value}
                </span>
              ))}
            </p>
            <p className="proof-diff-legend"><span className="proof-word-added">Added</span><span className="proof-word-removed">Removed</span></p>
          </>
        ) : (
          <p className="proof-unchanged">No wording changes</p>
        )}
      </div>
    </details>
  );
}
