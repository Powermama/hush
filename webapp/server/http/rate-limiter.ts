import type { MiddlewareHandler } from "hono";

type Bucket = { count: number; resetAt: number };

export function rateLimiter(options: {
  windowMs: number;
  limit: number;
}): MiddlewareHandler {
  const buckets = new Map<string, Bucket>();
  return async (context, next) => {
    const now = Date.now();
    const key =
      context.req.header("cf-connecting-ip") ??
      context.req.header("x-forwarded-for")?.split(",")[0]?.trim() ??
      "local";
    const current = buckets.get(key);
    const bucket =
      !current || current.resetAt <= now
        ? { count: 0, resetAt: now + options.windowMs }
        : current;
    bucket.count += 1;
    buckets.set(key, bucket);
    context.header("RateLimit-Limit", String(options.limit));
    context.header(
      "RateLimit-Remaining",
      String(Math.max(0, options.limit - bucket.count)),
    );
    context.header("RateLimit-Reset", String(Math.ceil(bucket.resetAt / 1000)));
    if (bucket.count > options.limit) {
      return context.json(
        {
          error: {
            code: "rate_limited",
            message: "Too many requests. Try again shortly.",
            requestId: context.get("requestId") as string,
          },
        },
        429,
      );
    }
    await next();
    if (buckets.size > 10_000) {
      for (const [candidate, value] of buckets) {
        if (value.resetAt <= now) buckets.delete(candidate);
      }
    }
  };
}

