import { Reveal } from "../components/Reveal";
import { SectionHeading } from "../components/SectionHeading";

const menu = ["General", "Models", "Personas", "Dictionary", "History"];
const rows = [
  {
    name: "whisper-large-v3-turbo",
    meta: "TRANSCRIPTION · WHISPERKIT · 1.6 GB",
    badge: "ready",
  },
  {
    name: "Qwen 3 · 4B",
    meta: "REFINEMENT · MLX · 2.5 GB",
    badge: "ready",
  },
  {
    name: "Apple Intelligence",
    meta: "REFINEMENT · SYSTEM MODEL",
    badge: "system",
  },
] as const;

export function Showcase() {
  return (
    <section className="section-shell bg-stone">
      <div className="mx-auto max-w-6xl">
        <SectionHeading
          title={
            <>
              One small window
              <span className="block text-soft">runs the whole thing.</span>
            </>
          }
          text="Pick your models, shape your writing styles, and teach hush your words. Then close it and forget it exists."
        />
        <Reveal>
          <div className="overflow-hidden rounded-[2rem] border border-black/8 bg-white shadow-[0_24px_70px_rgb(31_32_30/0.1)] md:grid md:grid-cols-[210px_1fr]">
            <aside className="flex gap-1 overflow-x-auto border-b border-black/8 bg-[#e9e9e6] p-3 md:block md:border-b-0 md:border-r md:p-4">
              {menu.map((item) => (
                <div
                  className={`flex shrink-0 items-center gap-2 rounded-xl px-3 py-2.5 text-sm font-semibold ${
                    item === "Models"
                      ? "bg-white text-ink shadow-sm"
                      : "text-muted"
                  }`}
                  key={item}
                >
                  <span className="size-3 rounded-full border border-current opacity-50" />
                  {item}
                </div>
              ))}
            </aside>
            <div className="p-6 sm:p-9">
              <h3 className="font-display text-2xl font-bold">Models</h3>
              <p className="mt-1 text-xs text-soft">
                All inference runs locally on this Mac · Neural Engine
              </p>
              <div className="mt-7 divide-y divide-black/8 border-y border-black/8">
                {rows.map((row) => (
                  <div
                    className="flex items-center justify-between gap-4 py-4"
                    key={row.name}
                  >
                    <div>
                      <p className="text-sm font-semibold">{row.name}</p>
                      <p className="mt-1 font-mono text-[10px] tracking-wide text-soft">
                        {row.meta}
                      </p>
                    </div>
                    <div className="flex items-center gap-3">
                      <span className="rounded-full bg-stone px-2.5 py-1 text-[10px] font-bold text-muted">
                        {row.badge}
                      </span>
                      <span className="relative h-6 w-10 rounded-full bg-success">
                        <span className="absolute right-1 top-1 size-4 rounded-full bg-white shadow" />
                      </span>
                    </div>
                  </div>
                ))}
                <div className="flex items-center justify-between gap-4 py-4">
                  <div>
                    <p className="text-sm font-semibold">Global hotkey</p>
                    <p className="mt-1 font-mono text-[10px] tracking-wide text-soft">
                      HOLD TO TALK · ANY APP
                    </p>
                  </div>
                  <kbd className="rounded-lg border border-black/10 bg-stone px-3 py-2 font-mono text-xs">
                    fn
                  </kbd>
                </div>
                <div className="flex items-center justify-between gap-4 py-4">
                  <div>
                    <p className="text-sm font-semibold">Cloud fallback</p>
                    <p className="mt-1 font-mono text-[10px] tracking-wide text-soft">
                      THERE ISN’T ONE
                    </p>
                  </div>
                  <span className="relative h-6 w-10 rounded-full bg-black/12">
                    <span className="absolute left-1 top-1 size-4 rounded-full bg-white shadow" />
                  </span>
                </div>
              </div>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
