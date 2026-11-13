import type { MiddlewareHandler } from "hono";

type Bucket = { count: number; resetAt: number };
type Options = { windowMs: number; limit: number; maxEntries?: number; now?: () => number };

// Expiry runs even when traffic stops. The timer releases its store when empty.
export class RateLimitStore {
  private readonly buckets = new Map<string, Bucket>();
  private timer: ReturnType<typeof setTimeout> | undefined;
  private readonly now: () => number;
  private readonly capacity: number;

  constructor(private readonly options: Options) {
    this.now = options.now ?? Date.now;
    this.capacity = options.maxEntries ?? 10_000;
  }

  get size() { return this.buckets.size; }

  consume(key: string) {
    const now = this.now();
    let bucket = this.buckets.get(key);
    if (bucket && bucket.resetAt <= now) {
      this.buckets.delete(key);
      bucket = undefined;
    }
    if (!bucket) {
      if (this.buckets.size >= this.capacity) this.sweep();
      if (this.buckets.size >= this.capacity) {
        // Do not evict a live entry and reset another client's limit.
        return { allowed: false, remaining: 0, resetAt: now + this.options.windowMs };
      }
      bucket = { count: 0, resetAt: now + this.options.windowMs };
      this.buckets.set(key, bucket);
    }
    bucket.count = Math.min(bucket.count + 1, this.options.limit + 1);
    this.schedule();
    return {
      allowed: bucket.count <= this.options.limit,
      remaining: Math.max(0, this.options.limit - bucket.count),
      resetAt: bucket.resetAt,
    };
  }

  sweep() {
    const now = this.now();
    for (const [key, bucket] of this.buckets) {
      if (bucket.resetAt <= now) this.buckets.delete(key);
    }
    if (this.buckets.size === 0 && this.timer) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
  }

  dispose() {
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
    this.buckets.clear();
  }

  private schedule() {
    if (this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = undefined;
      this.sweep();
      if (this.buckets.size) this.schedule();
    }, Math.min(this.options.windowMs, 60_000));
    this.timer.unref();
  }
}

export function rateLimiter(options: Options): MiddlewareHandler {
  const store = new RateLimitStore(options);
  return async (context, next) => {
    const key =
      context.req.header("cf-connecting-ip") ??
      context.req.header("x-forwarded-for")?.split(",")[0]?.trim() ??
      "local";
    const result = store.consume(key);
    context.header("RateLimit-Limit", String(options.limit));
    context.header("RateLimit-Remaining", String(result.remaining));
    context.header("RateLimit-Reset", String(Math.ceil(result.resetAt / 1000)));
    if (!result.allowed) {
      return context.json(
        { error: {
          code: "rate_limited",
          message: "Too many requests. Try again shortly.",
          requestId: context.get("requestId") as string,
        } },
        429,
      );
    }
    await next();
  };
}
