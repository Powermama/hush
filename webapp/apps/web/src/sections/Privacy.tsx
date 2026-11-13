import { Reveal } from "../components/Reveal";

const promises = [
  "No account or sign-up",
  "Original audio is never uploaded",
  "No third-party analytics",
  "Verified Messages are optional",
];

export function Privacy() {
  return (
    <section id="privacy" className="section-shell bg-ink text-white">
      <div className="mx-auto grid max-w-6xl items-center gap-16 lg:grid-cols-2">
        <Reveal>
          <h2 className="text-balance font-display text-5xl font-bold leading-[0.98] tracking-[-0.05em] sm:text-7xl">
            Your voice never leaves your Mac.
          </h2>
          <p className="section-heading-copy max-w-lg text-pretty leading-7 text-white/55">
            Audio, transcription, and local AI stay on-device. If you choose a
            Verified Message, hush publishes only its encrypted proof package.
            The decryption key stays in the private link.
          </p>
        </Reveal>
        <Reveal delay={80}>
          <ul className="grid gap-3">
            {promises.map((item) => (
              <li
                className="flex items-center gap-4 rounded-2xl border border-white/10 bg-white/[0.04] p-4"
                key={item}
              >
                <span className="grid size-7 shrink-0 place-items-center rounded-full bg-success/15 text-success">
                  ✓
                </span>
                <span className="text-sm font-semibold">{item}</span>
              </li>
            ))}
          </ul>
        </Reveal>
      </div>
    </section>
  );
}
