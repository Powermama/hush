import { DownloadLink } from "../components/DownloadExperience";
import { DownloadIcon } from "../components/icons/DownloadIcon";
import { Reveal } from "../components/Reveal";
import { latestRelease } from "../../shared/releases";

export function FinalCta() {
  return (
    <section className="relative overflow-hidden px-5 py-28 text-center sm:py-40">
      <div className="final-glow" aria-hidden="true" />
      <Reveal className="relative mx-auto max-w-3xl">
        <h2 className="font-display text-5xl font-bold leading-[0.95] tracking-[-0.055em] sm:text-7xl">
          Your keyboard
          <span className="block text-soft">will miss you.</span>
        </h2>
        <p className="section-heading-copy mx-auto max-w-lg text-pretty leading-7 text-muted">
          {latestRelease
            ? "Download hush. It is free, private, and dangerously satisfying."
            : "The next Mac release is on its way. Free, private, and entirely on-device."}
        </p>
        <DownloadLink className="mt-8 gap-2.5">
          <DownloadIcon className="size-4" />
          Download for Mac
        </DownloadLink>
        <p className="mt-4 text-xs text-soft">
          Private alpha · macOS 15+ · Apple silicon · Core dictation stays local
        </p>
      </Reveal>
    </section>
  );
}
