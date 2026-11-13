import { diffChars } from "diff";
import { useMemo, useState } from "react";

type Comparison =
  | { kind: "empty" }
  | { kind: "exact" }
  | { kind: "formatting" }
  | { kind: "changed"; parts: ReturnType<typeof diffChars> };

export function MessageComparison({ signedText }: { signedText: string }) {
  const [receivedText, setReceivedText] = useState("");
  const comparison = useMemo(
    () => compareMessages(signedText, receivedText),
    [signedText, receivedText],
  );

  return (
    <details className="proof-comparison">
      <summary>Compare the message you received<span className="proof-chevron" aria-hidden="true">⌄</span></summary>
      <p className="proof-section-intro">Compared privately in your browser. Nothing you paste is uploaded.</p>
      <label className="proof-comparison-label">
        Received text
        <textarea
          className="proof-comparison-input"
          value={receivedText}
          maxLength={20_000}
          onChange={(event) => setReceivedText(event.target.value)}
          placeholder="Paste the Instagram, Slack, email, or message text here"
        />
      </label>
      <ComparisonResult comparison={comparison} />
    </details>
  );
}

function ComparisonResult({ comparison }: { comparison: Comparison }) {
  if (comparison.kind === "empty") return null;
  if (comparison.kind === "exact") {
    return (
      <p className="mt-4 rounded-xl bg-success/10 px-4 py-3 text-sm font-bold text-success">
        ✓ Exact match with the signed message
      </p>
    );
  }
  if (comparison.kind === "formatting") {
    return (
      <p className="mt-4 rounded-xl bg-amber-500/10 px-4 py-3 text-sm font-bold text-amber-700">
        Formatting differs, but the words match
      </p>
    );
  }
  return (
    <div className="mt-4 rounded-xl border border-red-500/15 bg-red-500/5 p-4">
      <p className="text-sm font-bold text-red-700">Message changed</p>
      <p className="mt-3 whitespace-pre-wrap break-words text-sm leading-6">
        {comparison.parts.map((part, index) => (
          <span
            key={`${index}-${part.value.slice(0, 8)}`}
            className={
              part.added
                ? "rounded bg-red-200/70 text-red-900 underline decoration-red-400"
                : part.removed
                  ? "rounded bg-emerald-100 text-emerald-900 line-through decoration-emerald-500"
                  : undefined
            }
          >
            {part.value}
          </span>
        ))}
      </p>
      <p className="mt-3 text-xs text-muted">
        Green struck text is in the signed original. Red underlined text is in the
        received version.
      </p>
    </div>
  );
}

function compareMessages(signed: string, received: string): Comparison {
  if (!received) return { kind: "empty" };
  const normalizedSigned = normalizeLineEndings(signed);
  const normalizedReceived = normalizeLineEndings(received);
  if (normalizedSigned === normalizedReceived) return { kind: "exact" };
  if (normalizeFormatting(normalizedSigned) === normalizeFormatting(normalizedReceived)) {
    return { kind: "formatting" };
  }
  return { kind: "changed", parts: diffChars(normalizedSigned, normalizedReceived) };
}

function normalizeLineEndings(value: string): string {
  return value.replace(/\r\n?/g, "\n").trim();
}

function normalizeFormatting(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

