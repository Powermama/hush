import { useEffect, useState } from "react";
import { decodeBase64 } from "../crypto";
import type { ProofManifest } from "../schema";

export function AudioCapture({
  audio,
}: {
  audio: NonNullable<ProofManifest["capture"]["audio"]>;
}) {
  const [url, setUrl] = useState<string>();

  useEffect(() => {
    const bytes = decodeBase64(audio.base64);
    const objectUrl = URL.createObjectURL(new Blob([bytes], { type: audio.mimeType }));
    setUrl(objectUrl);
    return () => URL.revokeObjectURL(objectUrl);
  }, [audio.base64, audio.mimeType]);

  return (
    <div className="rounded-2xl bg-stone p-4">
      <div className="flex items-center justify-between gap-3">
        <div>
          <p className="text-sm font-bold">Original voice capture</p>
          <p className="mt-0.5 text-xs text-muted">
            {formatDuration(audio.durationMs)} · encrypted before upload
          </p>
        </div>
        <span className="grid size-9 place-items-center rounded-full bg-peach/15 text-peach">
          ♪
        </span>
      </div>
      {url ? (
        <audio className="mt-4 w-full" controls preload="metadata" src={url}>
          Your browser does not support audio playback.
        </audio>
      ) : null}
    </div>
  );
}

function formatDuration(milliseconds: number): string {
  const seconds = Math.round(milliseconds / 1000);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

