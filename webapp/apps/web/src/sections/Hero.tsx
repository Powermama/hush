import { ButtonLink } from "../components/ButtonLink";
import { DownloadLink } from "../components/DownloadExperience";
import { DownloadIcon } from "../components/icons/DownloadIcon";
import { FeatureAnnouncement } from "../components/FeatureAnnouncement";
import { Reveal } from "../components/Reveal";
import { ProductDemo } from "../components/visuals/ProductDemo";

export function Hero() {
  return (
    <section id="top" className="bg-white px-5 pb-24 pt-[158px]">
      <div className="mx-auto max-w-[1080px] text-center">
        <Reveal>
          <FeatureAnnouncement
            href="/verified-messages"
            label="New"
            title="Verified Messages"
            ariaLabel="Explore Verified Messages"
          />
        </Reveal>
        <Reveal delay={80}>
          <h1 className="font-display text-[clamp(3rem,7.6vw,5.75rem)] font-bold leading-none tracking-[-0.045em]">
            <span>Talk and your Mac</span>
            <br />
            <span className="text-soft">does the typing.</span>
          </h1>
        </Reveal>
        <Reveal delay={160}>
          <p className="mx-auto mt-6 max-w-[600px] text-base leading-7 text-muted sm:text-[19px]">
            hush turns your voice into polished text{" "}
            <strong className="font-semibold text-ink">
              anywhere you type on your Mac
            </strong>
            , transcribed and refined entirely on-device.
          </p>
        </Reveal>
        <Reveal delay={240}>
          <div className="mt-8 flex flex-col items-center justify-center gap-3.5 sm:flex-row">
            <DownloadLink className="w-full gap-2.5 sm:w-auto">
              <DownloadIcon />
              Download for Mac
            </DownloadLink>
            <ButtonLink
              className="w-full sm:w-auto"
              href="#demo"
              variant="secondary"
            >
              See it work
            </ButtonLink>
          </div>
          <p className="mt-4 text-[13px] text-soft">
            Private alpha · <span className="font-medium text-muted">macOS 15+</span> ·
            Apple silicon · No account
          </p>
        </Reveal>
        <ProductDemo />
      </div>
    </section>
  );
}
