import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";
import { bodyLimit } from "hono/body-limit";
import { cors } from "hono/cors";
import { secureHeaders } from "hono/secure-headers";
import {
  challengeResponseSchema,
  completeProofSchema,
  completedProofResponseSchema,
  enrollInstallationSchema,
  errorResponseSchema,
  installationResponseSchema,
  publicProofResponseSchema,
  reserveProofSchema,
  proofReservationResponseSchema,
  revokeProofSchema,
  shortProofCodeSchema,
} from "../shared/contracts/proof";
import { rateLimiter } from "./http/rate-limiter";
import { ProofService } from "./services/proof-service";
import { ServiceError } from "./services/service-error";

type Variables = { requestId: string };
type AppEnvironment = { Variables: Variables };

const errorResponses = {
  400: { description: "Invalid request", content: { "application/json": { schema: errorResponseSchema } } },
  401: { description: "Invalid signature or capability", content: { "application/json": { schema: errorResponseSchema } } },
  404: { description: "Not found", content: { "application/json": { schema: errorResponseSchema } } },
  410: { description: "Expired or revoked proof", content: { "application/json": { schema: errorResponseSchema } } },
  409: { description: "State conflict", content: { "application/json": { schema: errorResponseSchema } } },
  422: { description: "Semantically invalid", content: { "application/json": { schema: errorResponseSchema } } },
} as const;

const unavailableResponse = {
  description: "Temporarily unavailable",
  content: { "application/json": { schema: errorResponseSchema } },
} as const;

const resolverErrorResponses = {
  400: errorResponses[400],
  404: errorResponses[404],
} as const;

const enrollmentChallengeRoute = createRoute({
  method: "post",
  path: "/v1/installations/challenges",
  operationId: "createEnrollmentChallenge",
  tags: ["Installations"],
  responses: {
    200: {
      description: "Short-lived enrollment challenge",
      content: { "application/json": { schema: challengeResponseSchema } },
    },
  },
});

const enrollRoute = createRoute({
  method: "post",
  path: "/v1/installations/enroll",
  operationId: "enrollInstallation",
  tags: ["Installations"],
  request: { body: { content: { "application/json": { schema: enrollInstallationSchema } } } },
  responses: {
    201: {
      description: "Registered Hush installation",
      content: { "application/json": { schema: installationResponseSchema } },
    },
    ...errorResponses,
  },
});

const publicationChallengeRoute = createRoute({
  method: "post",
  path: "/v1/proofs/challenges",
  operationId: "createPublicationChallenge",
  tags: ["Proofs"],
  request: {
    body: {
      content: {
        "application/json": {
          schema: z.object({ installationId: z.string().uuid() }),
        },
      },
    },
  },
  responses: {
    200: {
      description: "Short-lived proof publication challenge",
      content: { "application/json": { schema: challengeResponseSchema } },
    },
    ...errorResponses,
  },
});

const reserveRoute = createRoute({
  method: "post",
  path: "/v1/proofs",
  operationId: "reserveProof",
  tags: ["Proofs"],
  request: { body: { content: { "application/json": { schema: reserveProofSchema } } } },
  responses: {
    201: {
      description: "Reserved proof and scoped upload capability",
      content: { "application/json": { schema: proofReservationResponseSchema } },
    },
    ...errorResponses,
  },
});

const completeRoute = createRoute({
  method: "post",
  path: "/v1/proofs/{id}/complete",
  operationId: "completeProof",
  tags: ["Proofs"],
  request: {
    params: z.object({ id: z.string().uuid() }),
    body: { content: { "application/json": { schema: completeProofSchema } } },
  },
  responses: {
    200: {
      description: "Completed proof with a Hush service receipt",
      content: { "application/json": { schema: completedProofResponseSchema } },
    },
    ...errorResponses,
    503: unavailableResponse,
  },
});

const publicProofRoute = createRoute({
  method: "get",
  path: "/v1/proofs/{slug}",
  operationId: "getPublicProof",
  tags: ["Verifier"],
  request: { params: z.object({ slug: z.string().min(16).max(64) }) },
  responses: {
    200: {
      description: "Public metadata required for client-side verification",
      content: { "application/json": { schema: publicProofResponseSchema } },
    },
    ...errorResponses,
  },
});

const revokeRoute = createRoute({
  method: "post",
  path: "/v1/proofs/{slug}/revoke",
  operationId: "revokeProof",
  tags: ["Proofs"],
  request: {
    params: z.object({ slug: z.string().min(16).max(64) }),
    body: { content: { "application/json": { schema: revokeProofSchema } } },
  },
  responses: {
    200: {
      description: "Idempotent proof revocation",
      content: { "application/json": { schema: z.object({ status: z.literal("revoked") }) } },
    },
    ...errorResponses,
  },
});

const resolveProofAliasRoute = createRoute({
  method: "get",
  path: "/s/{code}",
  operationId: "resolveProofAlias",
  tags: ["Verifier"],
  request: { params: z.object({ code: shortProofCodeSchema }) },
  responses: {
    302: {
      description: "Redirect to the canonical private proof page",
      headers: {
        Location: { schema: { type: "string", format: "uri" } },
      },
    },
    ...resolverErrorResponses,
  },
});

export function createApp(input: {
  proofService: ProofService;
  allowedOrigin: string;
  registerRootAlias?: boolean;
}) {
  const app = new OpenAPIHono<AppEnvironment>();

  app.use("*", async (context, next) => {
    const requestId = context.req.header("x-request-id") ?? crypto.randomUUID();
    context.set("requestId", requestId);
    context.header("x-request-id", requestId);
    await next();
  });
  app.use("*", secureHeaders({
    contentSecurityPolicy: {
      defaultSrc: ["'self'"],
      connectSrc: ["'self'"],
      imgSrc: ["'self'", "data:"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      objectSrc: ["'none'"],
      baseUri: ["'none'"],
      frameAncestors: ["'none'"],
    },
    referrerPolicy: "no-referrer",
    xFrameOptions: "DENY",
  }));
  app.use(
    "/v1/*",
    cors({
      origin: input.allowedOrigin,
      allowMethods: ["GET", "POST", "PUT", "OPTIONS"],
      allowHeaders: ["Content-Type", "X-Request-ID"],
      maxAge: 3600,
    }),
  );
  app.use("/v1/*", rateLimiter({ windowMs: 60_000, limit: 120 }));
  app.use("/s/*", rateLimiter({ windowMs: 60_000, limit: 60 }));
  app.use(
    "/v1/proofs/*/content",
    bodyLimit({
      maxSize: 8_000_000,
      onError: (context) =>
        context.json(
          {
            error: {
              code: "body_too_large",
              message: "Encrypted proof exceeds the 8 MB limit.",
              requestId: context.get("requestId"),
            },
          },
          413,
        ),
    }),
  );

  app.openapi(enrollmentChallengeRoute, async (context) =>
    context.json(await input.proofService.createEnrollmentChallenge(), 200),
  );
  app.openapi(enrollRoute, async (context) =>
    context.json(
      await input.proofService.enrollInstallation(context.req.valid("json")),
      201,
    ),
  );
  app.openapi(publicationChallengeRoute, async (context) =>
    context.json(
      await input.proofService.createPublicationChallenge(
        context.req.valid("json").installationId,
      ),
      200,
    ),
  );
  app.openapi(reserveRoute, async (context) =>
    context.json(
      await input.proofService.reserveProof(context.req.valid("json")),
      201,
    ),
  );
  app.put("/v1/proofs/:id/content", async (context) => {
    const token = context.req.query("token") ?? "";
    const contentType = context.req.header("content-type")?.split(";")[0];
    if (contentType !== "application/vnd.hush.proof+encrypted") {
      throw new ServiceError(
        "invalid_content_type",
        "Expected an encrypted Hush proof.",
        422,
      );
    }
    const bytes = new Uint8Array(await context.req.arrayBuffer());
    await input.proofService.uploadProofContent(context.req.param("id"), token, bytes);
    return context.body(null, 204);
  });
  app.openapi(completeRoute, async (context) =>
    context.json(
      await input.proofService.completeProof(
        context.req.valid("param").id,
        context.req.valid("json").completionToken,
      ),
      200,
    ),
  );
  app.openapi(publicProofRoute, async (context) =>
    context.json(
      await input.proofService.getPublicProof(context.req.valid("param").slug),
      200,
    ),
  );
  app.get("/v1/proofs/:slug/content", async (context) => {
    const bytes = await input.proofService.getPublicCiphertext(context.req.param("slug"));
    const body = new Uint8Array(bytes.byteLength);
    body.set(bytes);
    return new Response(body.buffer, {
      status: 200,
      headers: {
        "content-type": "application/vnd.hush.proof+encrypted",
        "cache-control": "private, max-age=60",
      },
    });
  });
  app.openapi(revokeRoute, async (context) => {
    await input.proofService.revokeProof(
      context.req.valid("param").slug,
      context.req.valid("json").revocationSecret,
    );
    return context.json({ status: "revoked" as const }, 200);
  });
  app.openapi(resolveProofAliasRoute, async (context) => {
    const target = await input.proofService.resolveProofAlias(
      context.req.valid("param").code,
    );
    context.header("cache-control", "public, max-age=300, s-maxage=300");
    context.header("x-robots-tag", "noindex, nofollow");
    return context.redirect(target, 302);
  });
  if (input.registerRootAlias !== false) {
    registerRootProofAlias(app, input.proofService);
  }

  app.get("/health/live", (context) => context.json({ status: "ok" }));
  app.get("/health/ready", (context) => context.json({ status: "ok" }));
  app.doc("/openapi.json", {
    openapi: "3.1.0",
    info: {
      title: "Hush Provenance API",
      version: "1.0.0-alpha.1",
      description: "Content-free control plane for encrypted Hush message proofs.",
    },
  });

  app.notFound((context) =>
    context.json(
      {
        error: {
          code: "not_found",
          message: "Route not found.",
          requestId: context.get("requestId"),
        },
      },
      404,
    ),
  );
  app.onError((error, context) => {
    const requestId = context.get("requestId") ?? crypto.randomUUID();
    if (error instanceof ServiceError) {
      return context.json(
        { error: { code: error.code, message: error.message, requestId } },
        error.status,
      );
    }
    console.error(JSON.stringify({ level: "error", requestId, error: error.message }));
    return context.json(
      {
        error: {
          code: "internal_error",
          message: "The proof service could not complete the request.",
          requestId,
        },
      },
      500,
    );
  });

  return app;
}

export function registerRootProofAlias(
  app: OpenAPIHono<AppEnvironment>,
  proofService: ProofService,
) {
  const aliasPath = /^\/[A-Za-z0-9_-]{6}$/;
  const aliasRateLimiter = rateLimiter({ windowMs: 60_000, limit: 60 });
  app.use("*", (context, next) =>
    aliasPath.test(context.req.path)
      ? aliasRateLimiter(context, next)
      : next(),
  );
  app.get("*", async (context, next) => {
    if (!aliasPath.test(context.req.path)) return next();

    const target = await proofService.resolveProofAlias(
      context.req.path.slice(1),
    );
    context.header("cache-control", "public, max-age=300, s-maxage=300");
    context.header("x-robots-tag", "noindex, nofollow");
    return context.redirect(target, 302);
  });
}
