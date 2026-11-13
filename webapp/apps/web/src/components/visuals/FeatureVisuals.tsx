function PrivacyVisual() {
  return (
    <div className="flex items-end gap-3">
      <span className="font-display text-7xl font-bold tracking-[-0.06em]">0</span>
      <span className="pb-2 text-sm text-white/45">
        bytes sent
        <br />
        to the cloud
      </span>
    </div>
  );
}

function ShortcutVisual() {
  return (
    <div className="flex items-center gap-2">
      <span className="rounded-xl border border-black/10 bg-stone px-4 py-3 font-mono text-sm shadow-sm">
        fn
      </span>
      <span className="text-sm text-soft">hold to talk</span>
    </div>
  );
}

function TypingSpeedVisual() {
  return (
    <div className="flex items-end gap-3">
      <span className="font-display text-7xl font-bold tracking-[-0.06em]">
        4×
      </span>
      <span className="pb-2 text-sm leading-5 text-soft">
        faster
        <br />
        than typing
      </span>
    </div>
  );
}

function SpeedVisual() {
  return (
    <div className="flex items-end justify-between">
      <div>
        <span className="font-display text-6xl font-bold tracking-[-0.06em]">
          &lt;1s
        </span>
        <p className="mt-1 text-xs opacity-45">last word to polished text</p>
      </div>
      <div className="flex h-16 items-end gap-1" aria-hidden="true">
        {[18, 32, 50, 28, 62, 42, 56, 24].map((height, index) => (
          <span
            className="w-1.5 rounded-full bg-ink/55"
            style={{ height }}
            key={`${height}-${index}`}
          />
        ))}
      </div>
    </div>
  );
}

const visuals = {
  privacy: PrivacyVisual,
  shortcut: ShortcutVisual,
  typingSpeed: TypingSpeedVisual,
  speed: SpeedVisual,
} as const;

export function FeatureVisual({ name }: { name: keyof typeof visuals }) {
  const Visual = visuals[name];
  return <Visual />;
}
