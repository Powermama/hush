import { z } from "zod";
import { publicProofResponseSchema } from "../../shared/contracts/proof";

const provenanceEventBase = {
  id: z.string().uuid(),
  occurredAt: z.string().datetime(),
};

const provenanceEventSchema = z.discriminatedUnion("kind", [
  z.object({ ...provenanceEventBase, kind: z.literal("message_started") }),
  z.object({
    ...provenanceEventBase,
    kind: z.literal("voice_capture"),
    durationMs: z.number().int().positive(),
    modelDisplayName: z.string().min(1),
  }),
  z.object({
    ...provenanceEventBase,
    kind: z.literal("voice_section_added"),
    voiceSegmentId: z.string().uuid(),
    durationMs: z.number().int().positive(),
    modelDisplayName: z.string().min(1),
  }),
  z.object({ ...provenanceEventBase, kind: z.literal("cleanup_applied") }),
  z.object({
    ...provenanceEventBase,
    kind: z.literal("local_ai_refined"),
    modelDisplayName: z.string().min(1).optional(),
    persona: z.string().min(1).optional(),
  }),
  z.object({ ...provenanceEventBase, kind: z.literal("manual_edit") }),
  z.object({
    ...provenanceEventBase,
    kind: z.literal("revision_created"),
    parentProofId: z.string().uuid(),
    parentCommitment: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
  }),
]);

export const proofManifestSchema = z.object({
  version: z.union([z.literal(1), z.literal(2)]),
  proofId: z.string().uuid(),
  commitmentNonce: z.string().min(32),
  createdAt: z.string().datetime(),
  expiresAt: z.string().datetime(),
  author: z
    .object({
      displayName: z.string().min(1).max(120).optional(),
      identityKind: z.enum(["anonymous", "self_declared"]),
    })
    .optional(),
  capture: z.object({
    source: z.enum(["microphone", "keyboard", "hush_history"]),
    durationMs: z.number().int().positive().optional(),
    sampleRate: z.number().int().positive().optional(),
    audioSha256: z.string().optional(),
    audio: z
      .object({
        mimeType: z.enum(["audio/mp4", "audio/aac", "audio/wav"]),
        base64: z.string().min(1),
        durationMs: z.number().int().positive(),
      })
      .optional(),
  }),
  transcription: z
    .object({
      rawText: z.string().min(1),
      modelId: z.string().min(1),
      modelDisplayName: z.string().min(1),
      language: z.string().min(1),
    })
    .optional(),
  sourceText: z.string().min(1).optional(),
  voiceSegments: z
    .array(
      z.object({
        id: z.string().uuid(),
        capturedAt: z.string().datetime(),
        durationMs: z.number().int().positive(),
        sampleRate: z.number().int().positive(),
        audioSha256: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
        transcript: z.string().min(1),
        modelId: z.string().min(1),
        modelDisplayName: z.string().min(1),
        language: z.string().min(1),
      }),
    )
    .min(1)
    .optional(),
  revision: z
    .object({
      parentProofId: z.string().uuid(),
      parentCommitment: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
    })
    .optional(),
  provenanceEvents: z.array(provenanceEventSchema).min(1).optional(),
  transformations: z.array(
    z.object({
      kind: z.enum(["cleanup", "local_ai", "manual_hush_edit"]),
      provider: z.string().optional(),
      model: z.string().optional(),
      persona: z.string().optional(),
      algorithmVersion: z.string().min(1),
    }),
  ),
  finalText: z.string().min(1),
  aiEditShare: z.number().min(0).max(1).optional(),
  activitySnapshot: z
    .object({
      estimatedTimeSavedSeconds: z.number().nonnegative(),
      totalWordsSpoken: z.number().int().nonnegative(),
      capturedAt: z.string().datetime(),
    })
    .optional(),
}).superRefine((manifest, context) => {
  const events = manifest.provenanceEvents ?? [];
  const hasEvent = (kind: (typeof events)[number]["kind"]) =>
    events.some((event) => event.kind === kind);
  if (manifest.capture.source === "microphone") {
    if (!manifest.capture.durationMs || !manifest.capture.sampleRate) {
      context.addIssue({
        code: "custom",
        path: ["capture"],
        message: "Microphone capture requires duration and sample rate.",
      });
    }
    if (!manifest.transcription) {
      context.addIssue({
        code: "custom",
        path: ["transcription"],
        message: "Microphone capture requires a transcription record.",
      });
    }
  } else if (!manifest.sourceText) {
    context.addIssue({
      code: "custom",
      path: ["sourceText"],
      message: "Text-origin proofs require the signed source text.",
    });
  }
  if (
    manifest.capture.source !== "microphone" &&
    (manifest.capture.durationMs !== undefined ||
      manifest.capture.sampleRate !== undefined ||
      manifest.capture.audioSha256 !== undefined ||
      manifest.capture.audio !== undefined ||
      manifest.transcription !== undefined)
  ) {
    context.addIssue({
      code: "custom",
      path: ["capture"],
      message: "Text-origin proofs cannot claim voice or transcription evidence.",
    });
  }
  if (manifest.revision && manifest.capture.source !== "hush_history") {
    context.addIssue({
      code: "custom",
      path: ["revision"],
      message: "Only a reopened hush message can declare a prior proof revision.",
    });
  }
  if (manifest.capture.source === "microphone" && manifest.sourceText !== undefined) {
    context.addIssue({
      code: "custom",
      path: ["sourceText"],
      message: "Microphone proofs use the signed transcription as their source.",
    });
  }
  if (manifest.version === 1) return;

  if (manifest.capture.source === "microphone") {
    const captureEvent = events.find((event) => event.kind === "voice_capture");
    if (
      !captureEvent ||
      captureEvent.durationMs !== manifest.capture.durationMs ||
      captureEvent.modelDisplayName !== manifest.transcription?.modelDisplayName
    ) {
      context.addIssue({
        code: "custom",
        path: ["provenanceEvents"],
        message: "Microphone proofs require a matching initial voice event.",
      });
    }
  }
  if (manifest.capture.source === "keyboard" && !hasEvent("message_started")) {
    context.addIssue({
      code: "custom",
      path: ["provenanceEvents"],
      message: "Keyboard proofs require a message-started event.",
    });
  }
  if (
    manifest.transformations.some((item) => item.kind === "cleanup") &&
    !hasEvent("cleanup_applied")
  ) {
    context.addIssue({
      code: "custom",
      path: ["provenanceEvents"],
      message: "Cleanup transformations require a matching chronology event.",
    });
  }
  if (
    manifest.transformations.some((item) => item.kind === "local_ai") &&
    !hasEvent("local_ai_refined")
  ) {
    context.addIssue({
      code: "custom",
      path: ["provenanceEvents"],
      message: "Local AI transformations require a matching chronology event.",
    });
  }
  if (
    manifest.transformations.some((item) => item.kind === "manual_hush_edit") &&
    !hasEvent("manual_edit")
  ) {
    context.addIssue({
      code: "custom",
      path: ["provenanceEvents"],
      message: "Manual hush edits require a matching chronology event.",
    });
  }
  if (manifest.revision) {
    const revisionEvent = events.find((event) => event.kind === "revision_created");
    if (
      !revisionEvent ||
      revisionEvent.parentProofId !== manifest.revision.parentProofId ||
      revisionEvent.parentCommitment !== manifest.revision.parentCommitment
    ) {
      context.addIssue({
        code: "custom",
        path: ["provenanceEvents"],
        message: "Revisions require a matching signed chronology event.",
      });
    }
  }
  for (const segment of manifest.voiceSegments ?? []) {
    if (!events.some(
      (event) => event.kind === "voice_section_added" &&
        event.voiceSegmentId === segment.id &&
        event.durationMs === segment.durationMs &&
        event.modelDisplayName === segment.modelDisplayName,
    )) {
      context.addIssue({
        code: "custom",
        path: ["provenanceEvents"],
        message: `Voice section ${segment.id} is missing from the signed chronology.`,
      });
    }
  }
});

export const encryptedProofPackageSchema = z.object({
  version: z.literal(1),
  manifest: z.string().min(1),
  manifestSignature: z.string().min(1),
  installationPublicKey: z.string().min(1),
  signatureAlgorithm: z.literal("ES256"),
});

export type ProofManifest = z.infer<typeof proofManifestSchema>;
export type PublicProof = z.infer<typeof publicProofResponseSchema>;

export function parsePublicProof(value: unknown): PublicProof {
  return publicProofResponseSchema.parse(value);
}
