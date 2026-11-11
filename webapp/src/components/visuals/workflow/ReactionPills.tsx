import { useEffect, useState } from "react";

const reactions = [
  { emoji: "👀", count: 6, delay: 480 },
  { emoji: "🚀", count: 5, delay: 1060 },
  { emoji: "✨", count: 3, delay: 1640 },
] as const;

export function ReactionPills() {
  return (
    <div
      className="mt-2.5 flex gap-1.5 text-[10px]"
      role="group"
      aria-label="14 reactions"
    >
      {reactions.map((reaction) => (
        <Reaction key={reaction.emoji} {...reaction} />
      ))}
    </div>
  );
}

function Reaction({
  emoji,
  count,
  delay,
}: {
  emoji: string;
  count: number;
  delay: number;
}) {
  const [displayCount, setDisplayCount] = useState(1);

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | undefined;
    const timeout = setTimeout(() => {
      interval = setInterval(() => {
        setDisplayCount((value) => {
          if (value >= count) {
            if (interval) clearInterval(interval);
            return value;
          }
          return value + 1;
        });
      }, 130);
    }, delay + 230);

    return () => {
      clearTimeout(timeout);
      if (interval) clearInterval(interval);
    };
  }, [count, delay]);

  return (
    <span
      className="workflow-reaction-pop min-w-10 rounded-full border border-black/8 bg-stone px-2 py-0.5 text-center tabular-nums"
      style={{ animationDelay: `${delay}ms` }}
      aria-hidden="true"
    >
      <span>{emoji}</span>{" "}
      <span key={displayCount} className="workflow-reaction-count inline-block">
        {displayCount}
      </span>
    </span>
  );
}
