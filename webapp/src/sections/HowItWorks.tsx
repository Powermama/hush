import { Reveal } from "../components/Reveal";
import { SectionHeading } from "../components/SectionHeading";
import { LocalWorkflowDemo } from "../components/visuals/LocalWorkflowDemo";

export function HowItWorks() {
  return (
    <section id="how" className="section-shell">
      <div className="mx-auto max-w-6xl">
        <SectionHeading
          title={
            <>
              From voice to finished text.
              <span className="block text-soft">Without leaving your Mac.</span>
            </>
          }
          text="Watch hush capture, refine, verify, and insert your thought using only the models and secure hardware already on your Mac."
        />
        <Reveal>
          <LocalWorkflowDemo />
        </Reveal>
      </div>
    </section>
  );
}
