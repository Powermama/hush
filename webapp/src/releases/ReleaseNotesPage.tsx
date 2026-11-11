import { Link } from "@tanstack/react-router";
import type { HushRelease, ReleaseSection } from "../../shared/releases";
import {
  latestRelease,
  releasePath,
  releases,
} from "../../shared/releases";
import { ButtonLink } from "../components/ButtonLink";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { Footer } from "../layout/Footer";
import { SubpageHeader } from "../layout/SubpageHeader";

const sectionAccent: Record<ReleaseSection["label"], string> = {
  Added: "bg-[#3ba86b]",
  Improved: "bg-[#7668d8]",
  Fixed: "bg-[#5686c6]",
};

function ReleaseHeader() {
  return (
    <SubpageHeader navigationLabel="Release navigation">
      <Link
        to="/releases"
        className="inline-flex min-h-10 items-center rounded-full px-4 text-sm font-semibold text-muted transition hover:bg-black/5 hover:text-ink"
      >
        All releases
      </Link>
    </SubpageHeader>
  );
}

function ReleaseChanges({ release }: { release: HushRelease }) {
  return (
    <div className="mt-10 space-y-10 sm:mt-12">
      {release.sections.map((section) => (
        <section
          key={section.label}
          aria-labelledby={`${release.slug}-${section.label.toLowerCase()}`}
          className="grid gap-4 sm:grid-cols-[112px_minmax(0,1fr)] sm:gap-8"
        >
          <h3
            id={`${release.slug}-${section.label.toLowerCase()}`}
            className="pt-0.5 text-xs font-semibold uppercase tracking-[0.16em] text-soft"
          >
            {section.label}
          </h3>
          <div className="divide-y divide-black/8 border-t border-black/8">
            {section.items.map((item) => (
              <div
                key={item.title}
                className="grid gap-2 py-5 sm:grid-cols-[190px_minmax(0,1fr)] sm:gap-8"
              >
                <h4 className="font-semibold leading-7 text-ink">
                  {item.title}
                </h4>
                <p className="leading-7 text-muted">{item.detail}</p>
              </div>
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}

export function ReleaseIndexPage() {
  const hasPublicRelease = releases.some(
    (release) => release.visibility === "public",
  );

  return (
    <div className="min-h-screen bg-canvas text-ink">
      <DocumentMetadata
        title="hush release notes"
        description="See what is new, improved, and fixed in every hush release."
        canonicalPath="/releases"
        indexable={hasPublicRelease}
      />
      <ReleaseHeader />
      <main className="px-5 pb-28 pt-16 sm:pt-24">
        <div className="mx-auto max-w-4xl">
          <h1 className="font-display text-5xl font-bold tracking-[-0.055em] sm:text-7xl sm:leading-[0.96]">
            Release notes.
          </h1>
          <p className="mt-6 max-w-2xl text-lg leading-8 text-muted sm:text-xl">
            Every meaningful change to hush, in one place.
          </p>

          <div className="mt-16 sm:mt-24">
            {releases.length === 0 && (
              <section className="rounded-3xl border border-black/8 bg-white p-8 sm:p-12">
                <p className="text-xs font-semibold uppercase tracking-[0.16em] text-soft">
                  Coming soon
                </p>
                <h2 className="mt-4 font-display text-3xl font-bold tracking-[-0.04em] sm:text-4xl">
                  The next release is on its way.
                </h2>
                <p className="mt-4 max-w-2xl leading-7 text-muted">
                  We are preparing a new Mac build. Downloads will return here
                  once it is ready. Earlier alpha builds are no longer available
                  from this website.
                </p>
                <ButtonLink href="/" variant="secondary" className="mt-8">
                  Explore hush
                </ButtonLink>
              </section>
            )}
            {releases.map((release) => (
              <article
                key={release.slug}
                id={release.slug}
                className="scroll-mt-8 border-t border-black/10 py-14 first:pt-14 sm:py-20"
              >
                <div className="flex flex-wrap items-center gap-x-3 gap-y-2 text-sm text-soft">
                  <time dateTime={release.releasedAt}>{release.displayDate}</time>
                  <span aria-hidden="true">·</span>
                  <Link
                    to="/releases/$slug"
                    params={{ slug: release.slug }}
                    className="rounded-sm font-mono text-xs transition hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-ink"
                    aria-label={`Open permanent page for ${release.displayVersion}`}
                  >
                    {release.displayVersion}
                  </Link>
                  <span aria-hidden="true">·</span>
                  <span>{release.channel}</span>
                </div>
                <h2 className="mt-5 max-w-3xl font-display text-3xl font-bold tracking-[-0.04em] sm:text-5xl">
                  {release.title}
                </h2>
                <p className="mt-4 max-w-3xl text-base leading-7 text-muted sm:text-lg sm:leading-8">
                  {release.summary}
                </p>
                <ReleaseChanges release={release} />
              </article>
            ))}
          </div>
        </div>
      </main>
      <Footer />
    </div>
  );
}

export function ReleaseDetailPage({ release }: { release: HushRelease }) {
  return (
    <div className="min-h-screen bg-canvas text-ink">
        <DocumentMetadata
          title={`hush ${release.displayVersion} release notes`}
          description={release.summary}
          canonicalPath={releasePath(release)}
          indexable={release.visibility === "public"}
        />
        <ReleaseHeader />
        <main className="px-5 pb-28 pt-12 sm:pt-16">
          <article className="mx-auto max-w-4xl">
            <Link
              to="/releases"
              className="text-sm font-semibold text-muted transition hover:text-ink"
            >
              ← All releases
            </Link>

            <div className="mt-12 flex flex-wrap items-center gap-x-3 gap-y-2 text-sm text-muted">
              <span className="font-semibold text-ink">{release.channel}</span>
              <span aria-hidden="true">·</span>
              <span>{release.displayVersion}</span>
              <span aria-hidden="true">·</span>
              <time dateTime={release.releasedAt}>{release.displayDate}</time>
            </div>
            <h1 className="mt-5 font-display text-5xl font-bold tracking-[-0.055em] sm:text-7xl">
              {release.title}
            </h1>
            <p className="mt-6 max-w-3xl text-xl leading-9 text-muted sm:text-2xl sm:leading-10">
              {release.summary}
            </p>
            <div className="mt-8 text-sm leading-6 text-soft">
              Build {release.build} · {release.systemRequirements}
            </div>

            <div className="mt-16 border-t border-black/10 pt-16 sm:mt-20 sm:pt-20">
              <h2 className="font-display text-4xl font-bold tracking-[-0.04em]">
                What changed
              </h2>
              <p className="mt-3 max-w-2xl leading-7 text-muted">
                The useful details, written for the people using hush.
              </p>
            </div>

            <div className="mt-16 space-y-20">
              {release.sections.map((section) => (
                <section key={section.label}>
                  <div className="flex items-center gap-3">
                    <span
                      className={`size-2.5 rounded-full ${sectionAccent[section.label]}`}
                      aria-hidden="true"
                    />
                    <h2 className="font-display text-2xl font-bold tracking-[-0.03em]">
                      {section.label}
                    </h2>
                  </div>
                  <div className="mt-5 divide-y divide-black/8 border-t border-black/8">
                    {section.items.map((item) => (
                      <div
                        key={item.title}
                        className="grid gap-3 py-7 sm:grid-cols-[240px_1fr] sm:gap-10"
                      >
                        <h3 className="font-display text-lg font-bold tracking-[-0.02em]">
                          {item.title}
                        </h3>
                        <p className="leading-7 text-muted">{item.detail}</p>
                      </div>
                    ))}
                  </div>
                </section>
              ))}

              <section className="border-t border-black/10 pt-14">
                <h2 className="font-display text-3xl font-bold tracking-[-0.04em]">
                  Before you install
                </h2>
                <p className="mt-3 leading-7 text-muted">
                  What to expect from this private alpha.
                </p>
                <ul className="mt-7 space-y-5">
                  {release.knownNotes.map((note) => (
                    <li
                      key={note}
                      className="grid grid-cols-[8px_1fr] gap-4 leading-7 text-muted"
                    >
                      <span className="mt-2.5 size-2 rounded-full bg-peach" />
                      {note}
                    </li>
                  ))}
                </ul>
              </section>
            </div>
          </article>
        </main>
        <Footer />
      </div>
  );
}

export function MissingReleasePage() {
  return (
    <div className="grid min-h-screen place-items-center bg-canvas px-5 text-center text-ink">
      <DocumentMetadata
        title="Release not found - hush"
        description="This hush release could not be found."
        canonicalPath="/releases"
        indexable={false}
      />
      <div>
        <p className="text-sm font-semibold text-muted">Release not found</p>
        <h1 className="mt-3 font-display text-5xl font-bold tracking-[-0.05em]">
          Nothing to install here.
        </h1>
        <ButtonLink href="/releases" className="mt-7">
          View all releases
        </ButtonLink>
      </div>
    </div>
  );
}

export function LatestReleasePage() {
  return latestRelease ? (
    <ReleaseDetailPage release={latestRelease} />
  ) : (
    <ReleaseIndexPage />
  );
}
