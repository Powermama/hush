import { useEffect, useId, useRef } from "react";
import { m } from "../paraglide/messages";
import "./mascot.css";

export type MascotState = "listening" | "thinking" | "recording" | "sad";

const descriptions: Record<MascotState, () => string> = {
  listening: m.mascot_listening,
  thinking: m.mascot_thinking,
  recording: m.mascot_recording,
  sad: m.mascot_sad,
};

/** A character in the editorial artwork, never a live microphone or app control. */
export function HushMascot({ state }: { state: MascotState }) {
  const host = useRef<HTMLDivElement>(null);
  useEffect(() => {
    let cancelled = false;
    let dispose: (() => void) | null = null;
    const node = host.current;
    if (!node) return;
    const observer = new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) return;
      observer.disconnect();
      void import("./MascotScene").then(({ mountMascotScene }) => {
        if (cancelled) return;
        dispose = mountMascotScene(node, state);
        if (!dispose) node.dataset.scene = "fallback";
      }).catch(() => { if (!cancelled) node.dataset.scene = "fallback"; });
    }, { rootMargin: "150px" });
    observer.observe(state === "listening" ? node.closest(".thought-art") ?? node : node);
    return () => { cancelled = true; observer.disconnect(); dispose?.(); };
  }, [state]);
  return <div ref={host} className={`hush-mascot hush-mascot-${state}`} role="img" aria-label={descriptions[state]()}>
    <HushMascotArtwork state={state} />
  </div>;
}

/**
 * Applies the CSS saturate() matrix to an sRGB colour, as the Filter Effects
 * specification defines it, so tinted artwork needs no runtime filter.
 */
function saturate(color: string, amount: number) {
  if (amount === 1) return color;
  const hex = color === "white" ? "#fff" : color;
  const full = hex.length === 4 ? `#${[...hex.slice(1)].map(digit => digit + digit).join("")}` : hex;
  const [r, g, b] = [1, 3, 5].map(index => parseInt(full.slice(index, index + 2), 16));
  const s = amount;
  const channels = [
    (0.213 + 0.787 * s) * r + (0.715 - 0.715 * s) * g + (0.072 - 0.072 * s) * b,
    (0.213 - 0.213 * s) * r + (0.715 + 0.285 * s) * g + (0.072 - 0.072 * s) * b,
    (0.213 - 0.213 * s) * r + (0.715 - 0.715 * s) * g + (0.072 + 0.928 * s) * b,
  ];
  return `#${channels.map(value => Math.round(Math.min(255, Math.max(0, value))).toString(16).padStart(2, "0")).join("")}`;
}

/** Shared vector artwork also serves small avatars without a WebGL context. */
export function HushMascotArtwork({ state, portrait = false, peeking = false, saturation = 1 }: { state: MascotState; portrait?: boolean; peeking?: boolean; saturation?: number }) {
  const id = useId().replaceAll(":", "");
  const tone = (color: string) => saturate(color, saturation);
  const paint = (name: string) => `url(#${id}-${name})`;
  return <svg className="mascot-fallback" viewBox={portrait ? "40 45 122 112" : "0 0 200 190"} fill="none" aria-hidden="true">
    <defs>
      <linearGradient id={`${id}-body`} x1="55" y1="55" x2="149" y2="147" gradientUnits="userSpaceOnUse">
        <stop stopColor={tone("#535c62")} /><stop offset=".45" stopColor={tone("#282f35")} /><stop offset="1" stopColor={tone("#151c22")} />
      </linearGradient>
      <linearGradient id={`${id}-silver`} x1="67" y1="68" x2="126" y2="114" gradientUnits="userSpaceOnUse">
        <stop stopColor={tone("#fff")} /><stop offset="1" stopColor={tone("#d7e6e7")} />
      </linearGradient>
    </defs>
    <ellipse cx="101" cy="173" rx="49" ry="7" fill={tone("#173a4e")} opacity=".13" />
    <g className="mascot-character">
      <g stroke={tone("#28434d")} strokeWidth="6" strokeLinecap="round" strokeLinejoin="round">
        {!peeking && <path d="M78 142L73 165H62M122 142L129 165H140" />}
        {peeking && <path d="M55 111Q34 108 35 132M149 111Q172 108 167 132" />}
        {state === "listening" && !peeking && <><path d="M54 111Q28 113 31 88" /><path d="M149 109Q175 96 161 71" /><path d="M158 77Q151 72 157 64Q164 61 168 69" stroke={tone("#86b7be")} strokeWidth="8" /></>}
        {state === "thinking" && <><path d="M55 112Q35 122 45 139" /><path d="M149 112Q169 131 137 135" /><path d="M137 135L131 128" stroke={tone("#86b7be")} strokeWidth="8" /></>}
        {state === "recording" && <><path d="M55 111Q32 131 27 108" /><path d="M149 112Q173 126 176 107" /><path d="M174 108L179 104" stroke={tone("#86b7be")} strokeWidth="8" /></>}
        {state === "sad" && <><path d="M55 112Q42 124 45 143" /><path d="M149 112Q162 124 158 143" /></>}
      </g>
      <g className="mascot-body">
        <rect x="59" y="49" width="99" height="96" rx="28" fill={tone("#bfe7e8")} stroke={tone("#f3fffd")} strokeWidth="2" />
        <rect x="51" y="55" width="100" height="96" rx="28" fill={paint("body")} stroke={tone("#a8bdc5")} strokeWidth="2" />
        <path d="M66 64Q101 55 135 65" stroke={tone("#fff")} strokeOpacity=".16" strokeWidth="2" strokeLinecap="round" />
        <g className="mascot-eyes">
          {[82, 117].map(x => <g key={x}>
            <ellipse cx={x} cy="93" rx="12" ry="17" fill={paint("silver")} />
            <ellipse cx={x + (state === "thinking" ? 2 : -1)} cy={state === "thinking" ? 89 : state === "sad" ? 99 : 94} rx="7" ry="10" fill={tone("#367d99")} />
            <ellipse cx={x + (state === "thinking" ? 2 : -1)} cy={state === "thinking" ? 89 : state === "sad" ? 99 : 94} rx="4.5" ry="7" fill={tone("#102330")} />
            <circle cx={x - 2} cy="88" r="3" fill={tone("white")} />
            <circle cx={x + 3} cy="98" r="1.5" fill={tone("white")} />
          </g>)}
        </g>
        <ellipse cx="67" cy="110" rx="6" ry="3" fill={tone("#efa5a2")} /><ellipse cx="133" cy="110" rx="6" ry="3" fill={tone("#efa5a2")} />
        {state === "sad" ? <>
          {/* Worried brows, a frown, a tear and resting dots where the voice bars usually move. */}
          <path d="M72 70L90 66M110 66L128 70" stroke={tone("#d9efec")} strokeWidth="2.5" strokeLinecap="round" />
          <path d="M94 119Q100 113 106 119" stroke={tone("#d9efec")} strokeWidth="2" strokeLinecap="round" />
          <path d="M124 112Q120 119 124 122Q128 119 124 112Z" fill={tone("#bfe7e8")} />
          <path d="M86 134V134.5M95 134V134.5M104 134V134.5M113 134V134.5" stroke={paint("silver")} strokeWidth="3" strokeLinecap="round" />
        </> : <>
          <path d="M94 114Q100 120 106 114" stroke={tone("#d9efec")} strokeWidth="2" strokeLinecap="round" />
          <path d="M86 132V136M95 127V141M104 130V139M113 133V136" stroke={paint("silver")} strokeWidth="3" strokeLinecap="round" />
        </>}
      </g>
    </g>
    {state === "listening" && !peeking && <g className="mascot-sound" stroke={tone("#578f9d")} strokeWidth="2.5" strokeLinecap="round">
      <path d="M28 58Q18 70 25 81M16 51Q1 69 11 88" />
    </g>}
    {state === "thinking" && <g className="mascot-idea" stroke={tone("#6e9fa9")} strokeWidth="2">
      <circle cx="153" cy="44" r="3" fill={tone("#bfe7e8")} /><circle cx="165" cy="30" r="5" fill={tone("#d9efec")} />
      <path d="M177 4L180 13L189 16L180 19L177 28L174 19L165 16L174 13Z" fill={tone("#fff5e9")} />
    </g>}
    {state === "recording" && <g className="mascot-microphone" stroke={tone("#32565d")} strokeWidth="2.5" strokeLinecap="round">
      <rect x="18" y="78" width="14" height="23" rx="7" fill={tone("#c7efdf")} />
      <path d="M13 93V96A12 12 0 0037 96V93M25 108V116M19 117H31" />
      <path className="mascot-record-wave" d="M5 77V69M16 68V56M28 64V59M40 73V64" stroke={tone("#e89684")} strokeWidth="3" />
    </g>}
  </svg>;
}

/** Foreground fingers share the character's coordinates while the artwork occludes its body. */
export function HushMascotGrip() {
  return <svg viewBox="0 0 200 190" fill="none" aria-hidden="true">
    {[35, 167].map(x => <g key={x}>
      <ellipse cx={x + 2} cy="141" rx="13" ry="4" fill="#263d61" opacity=".24" />
      <rect x={x - 10} y="126" width="21" height="15" rx="7" fill="#e7f0f3" stroke="#8ba5b4" strokeWidth="1.5" />
      <path d={`M${x - 3} 132v6M${x + 3} 132v6`} stroke="#a0b9c5" strokeWidth="1.5" strokeLinecap="round" />
    </g>)}
  </svg>;
}
