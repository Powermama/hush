import {
  ProofDisclaimer,
  VerifiedMessagePreview,
} from "../components/VerifiedMessagePreview";
import { Reveal } from "../components/Reveal";
import { SectionHeading } from "../components/SectionHeading";

export function VerifiedMessages() {
  return (
    <section id="verified-messages" className="section-shell bg-canvas">
      <div className="mx-auto max-w-6xl">
        <SectionHeading
          title={
            <>
              Proof when it matters.
              <span className="block text-soft">Private by default.</span>
            </>
          }
          text="Verified Messages let recipients check how a message was captured, refined, and signed. The proof is optional, encrypted on your Mac, and verified in their browser."
        />

        <Reveal>
          <VerifiedMessagePreview />
          <ProofDisclaimer />
        </Reveal>
      </div>
    </section>
  );
}
