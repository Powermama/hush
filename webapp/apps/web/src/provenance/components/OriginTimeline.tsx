import type { ProofManifest } from "../schema";
import { ProofIcon, type ProofIconKind } from "./ProofIcon";

type HistoryStep = { kind: ProofIconKind; title: string; detail: string; timestamp?: string };

export function OriginTimeline({ manifest }: { manifest: ProofManifest }) {
  const steps = historySteps(manifest);
  return (
    <ol className="proof-timeline" aria-label="Signed message history">
      {steps.map((step, index) => (
        <li key={`${index}-${step.title}`} data-kind={step.kind}>
          <span className="proof-event-icon"><ProofIcon kind={step.kind} /></span>
          <div className="proof-event-content">
            <h3>{step.title}</h3>
            <p>{step.detail}</p>
            {step.timestamp && <time dateTime={step.timestamp} title={step.timestamp}>{formatTimestamp(step.timestamp)}</time>}
          </div>
        </li>
      ))}
    </ol>
  );
}

function historySteps(manifest: ProofManifest): HistoryStep[] {
  const firstStep: HistoryStep = manifest.capture.source === "microphone"
    ? { kind: "voice", title: "Voice captured locally", detail: `${formatDuration(manifest.capture.durationMs!)} of microphone audio.` }
    : manifest.capture.source === "keyboard"
      ? { kind: "text", title: "Typed inside hush", detail: "Created in the private editor on the author's Mac." }
      : { kind: "revision", title: "Edited in hush", detail: "Reopened from the author's local hush history." };
  const legacySteps: HistoryStep[] = [
    firstStep,
    ...(manifest.revision ? [{ kind: "revision" as const, title: "Prior proof matched", detail: "Linked to the previous signed hush record." }] : []),
    ...(manifest.voiceSegments ?? []).map((section, index): HistoryStep => ({
      kind: "voice", title: `Voice section ${index + 1} added`, timestamp: section.capturedAt,
      detail: `${formatDuration(section.durationMs)} transcribed locally with ${section.modelDisplayName}.`,
    })),
    ...(manifest.transcription ? [{ kind: "text" as const, title: "Transcribed on the author's Mac", detail: manifest.transcription.modelDisplayName }] : []),
    ...manifest.transformations.map(describeTransformation),
  ];
  const signedHistory = manifest.provenanceEvents?.map((event, index, events) =>
    describeEvent(event, events.slice(0, index))) ?? legacySteps;
  return [...signedHistory, {
    kind: "signature", title: "Signed and encrypted", timestamp: manifest.createdAt,
    detail: "These exact words and this history are bound to the signature.",
  }];
}

function describeEvent(
  event: NonNullable<ProofManifest["provenanceEvents"]>[number],
  previousEvents: NonNullable<ProofManifest["provenanceEvents"]>,
): HistoryStep {
  const timestamp = event.occurredAt;
  switch (event.kind) {
    case "message_started":
      return { kind: "text", title: "Message started in hush", detail: "Created in the private composer.", timestamp };
    case "voice_capture":
      return { kind: "voice", title: "Voice recorded", detail: `${formatDuration(event.durationMs)} captured and transcribed locally with ${event.modelDisplayName}.`, timestamp };
    case "voice_section_added": {
      const number = previousEvents.filter(item => item.kind === "voice_section_added").length + 1;
      return { kind: "voice", title: `Voice section ${number} added`, detail: `${formatDuration(event.durationMs)} added by voice, transcribed locally with ${event.modelDisplayName}.`, timestamp };
    }
    case "local_ai_refined":
      return { kind: "ai", title: "Refined by local AI", detail: [event.persona && `${event.persona} style.`, `${event.modelDisplayName ?? "Local AI"} ran on the author's Mac.`].filter(Boolean).join(" "), timestamp };
    case "cleanup_applied":
      return { kind: "cleanup", title: "Cleaned up locally", detail: "Automatic spacing and punctuation cleanup. No AI refinement in this step.", timestamp };
    case "manual_edit":
      return { kind: "manual", title: "Edited inside hush", detail: "Manual text changes were included in the signed message.", timestamp };
    case "revision_created":
      return { kind: "revision", title: "Edited and re-signed", detail: "This version is linked to the previous hush proof.", timestamp };
  }
}

function describeTransformation(transformation: ProofManifest["transformations"][number]): HistoryStep {
  switch (transformation.kind) {
    case "cleanup":
      return { kind: "cleanup", title: "Cleaned up locally", detail: "Automatic spacing and punctuation cleanup. No AI refinement in this step." };
    case "local_ai":
      return { kind: "ai", title: "Refined by local AI", detail: [transformation.persona, transformation.provider, transformation.model].filter(Boolean).join(" · ") || "A local model refined the wording." };
    case "manual_hush_edit":
      return { kind: "manual", title: "Edited inside hush", detail: "Manual text changes included in the signature." };
  }
}

function formatDuration(milliseconds: number): string {
  const seconds = Math.max(1, Math.round(milliseconds / 1000));
  return seconds < 60 ? `${seconds} seconds` : `${Math.floor(seconds / 60)} min ${seconds % 60} sec`;
}

function formatTimestamp(value: string): string {
  return new Intl.DateTimeFormat(undefined, {
    month: "short", day: "numeric", year: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit", timeZoneName: "short",
  }).format(new Date(value));
}
