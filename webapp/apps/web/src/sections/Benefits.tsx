import { Reveal } from "../components/Reveal";
import { SectionHeading } from "../components/SectionHeading";
import { FeatureVisual } from "../components/visuals/FeatureVisuals";
import { benefits } from "../content/site";

export function Benefits() {
  return (
    <section id="features" className="section-shell bg-stone">
      <div className="mx-auto max-w-6xl">
        <SectionHeading
          title={
            <>
              Everything you need.
              <span className="block text-soft">Nothing you don’t.</span>
            </>
          }
          text="No accounts to create, browser tabs to manage, or workflows to relearn."
        />
        <div className="grid gap-4 lg:grid-cols-3">
          {benefits.map((benefit, index) => (
            <Reveal
              className={benefit.gridClassName}
              delay={(index % 2) * 80}
              key={benefit.title}
            >
              <article
                className={`flex min-h-[360px] flex-col overflow-hidden rounded-[2rem] border border-black/6 p-7 sm:p-9 ${benefit.surfaceClassName}`}
              >
                <p className="text-xs font-bold uppercase tracking-[0.14em] opacity-55">
                  {benefit.eyebrow}
                </p>
                <h3 className="mt-3 max-w-lg font-display text-3xl font-bold leading-tight tracking-[-0.035em]">
                  {benefit.title}
                </h3>
                <p className="mt-3 max-w-lg text-sm leading-6 opacity-65">
                  {benefit.text}
                </p>
                <div className="mt-auto pt-8">
                  <FeatureVisual name={benefit.visual} />
                </div>
              </article>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
