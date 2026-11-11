import { createApp } from "./app";
import type { ProofService } from "./services/proof-service";

const app = createApp({
  proofService: {} as ProofService,
  allowedOrigin: "https://hush.example",
});
const response = await app.request("/openapi.json");

if (!response.ok) {
  throw new Error(`OpenAPI export failed with status ${response.status}.`);
}

const document = await response.json();
await Bun.write(
  new URL("../openapi/hush-provenance.json", import.meta.url),
  `${JSON.stringify(document, null, 2)}\n`,
);
