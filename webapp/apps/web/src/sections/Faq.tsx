import { SectionHeading } from "../components/SectionHeading";
import { faqs } from "../content/site";

export function Faq() {
  return (
    <section className="section-shell bg-stone">
      <div className="mx-auto max-w-3xl">
        <SectionHeading
          title="Good to know."
          text="The useful details, without the fine-print maze."
        />
        <div className="divide-y divide-black/8 border-y border-black/8">
          {faqs.map(({ question, answer }) => (
            <details className="group py-1" key={question}>
              <summary className="flex cursor-pointer list-none items-center justify-between gap-6 py-5 font-display text-lg font-bold">
                {question}
                <span className="text-2xl font-light text-soft transition group-open:rotate-45">
                  +
                </span>
              </summary>
              <p className="-mt-1 max-w-2xl pb-6 pr-12 text-sm leading-6 text-muted">
                {answer}
              </p>
            </details>
          ))}
        </div>
      </div>
    </section>
  );
}
