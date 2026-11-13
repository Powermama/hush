# Private proof recipient journey

This document is the recipient-side product contract for `Typed with Hush` links. It gives humans and coding agents a stable map from user intent to executable evidence.

## Goal

A recipient can open a private proof link and independently verify the signed message record in the browser. The server never receives the fragment decryption key.

## State flow

```text
Private URL opened
  -> first-party short alias redirects to the canonical proof path
  -> private key remains in the browser-only URL fragment
Metadata and ciphertext fetched
  -> service receipt verified
  -> ciphertext digest and size verified
  -> proof decrypted locally
  -> Mac signature and manifest commitment verified
Verified Hush message shown
```

Any missing key, invalid signature, mismatched commitment, altered ciphertext, expired proof, or ambiguous metadata produces a non-green fail-closed state.

## Trust invariants

- Never show `Verified Hush message` until every verification step succeeds.
- Never send the URL fragment or decryption key to Hush.
- Keep the decryption capability in the URL fragment so reload, bookmark, copy, and browser sharing preserve the complete proof link.
- Treat the complete URL as private: anyone with the link can decrypt the proof until it expires or is revoked.
- The alias service stores only an opaque proof relationship and never an arbitrary destination or decryption key.
- Redirect responses omit a fragment so the browser preserves the private key client-side.
- Compare RFC 3339 timestamps by exact instant and preserve millisecond precision through storage.
- Verify exact proof ID, ciphertext hash, ciphertext size, commitment, Mac signature, service receipt, and expiry.
- Verify each service receipt with the public key its `keyId` names. The service keeps every public key it has signed with and publishes them at `/.well-known/jwks.json`; replacing the private signing key never invalidates earlier receipts, and an unknown `keyId` fails verification.
- Original audio is not part of the MVP proof payload.
- The verified page must distinguish microphone capture, text typed inside Hush, and retained Hush output reopened for editing.
- A text-origin proof must never display microphone, transcription, or audio claims.
- A revision displays the signed prior proof ID and commitment without exposing or requiring the previous proof's private key.
- Composer voice sections display as locally transcribed evidence, not as a claim that the entire message originated from one microphone recording.
- A revision page shows the complete privacy-minimized signed event chronology carried by the latest proof, beginning with the original standalone voice recording when one exists. It distinguishes deterministic cleanup, later composer recordings, local AI, and manual typing. It does not claim access to earlier private message text.
- Manifest version 2 requires this complete chronology and validates it against capture, transformations, voice sections, and revision metadata. Previously signed version 1 proofs remain verifiable, but the page never invents history that was absent from their signed payload.

## Recipient presentation

Use the shared site header with the existing download destination. The verified message is the page's focal point, followed by a connected visual chronology. Distinct icons and labels identify recordings, typed origins, deterministic cleanup, local AI, manual text edits, revisions, and signing. Recorded event times include seconds and a timezone; their exact signed values remain in `datetime` attributes. Do not add timestamps to legacy events without them.

Show local AI and manual edits in the message summary only when disclosed in the signed record. Show original wording and the source-to-final diff by default. This aggregate diff cannot attribute individual words to intermediate steps. The comparison tool remains local and expandable. Self-declared names and the limits of signature verification remain visible beside the message.

Exploring the history scrolls and focuses it without changing the private URL fragment. Below the evidence, a small static hushy illustration and direct download invite the recipient to try hush. On phones and iPads, the invitation opens the shared Mac-download handoff. Its share, email and copy payload is only the public homepage, never the current proof URL, fragment key or message. The current private URL remains intact. No extra trackers, remote avatars, real audio visualization, or WebGL scenes are introduced. Missing, expired, revoked, and invalid states use the same header but never show the successful message, history, or verified invitation.

## Scenarios

### VM-004 - Verify a complete proof

Given a recipient has a complete private link, when the page opens, reloads, is bookmarked, or is forwarded, then the fragment remains client-side and the proof decrypts in the browser. The verified final message, voice origin, author disclosure, and technical details appear.

### VM-005 - Reject an incomplete link

Given the URL has no valid fragment key, when the page opens, then it explains that the private proof link is incomplete and never shows a verified state.

### VM-006 - Reject mismatched expiry instants

Given the signed manifest uses `12:00:00.789Z` and the receipt uses `12:00:00.000Z`, when verification compares them, then it rejects the proof because they are different signed instants.

### VM-007 - Resolve a private short proof link

Given a recipient has a complete short proof link with a 6-character alias, when the Hush alias service resolves either the public root path or the compatibility `/s/` path, then it redirects to the immutable canonical proof path without receiving or returning the fragment key. The browser preserves the fragment and the normal fail-closed verification journey continues.

Production derives its canonical `/s/` short-link base from the single public Hush origin. Deployment configuration must not maintain a second independent short-link origin that can drift from the client contract.

### VM-008 - Verify a text-origin proof

Given a message was completed inside the Hush editor, when the recipient verifies its private link, then the page labels its real origin and shows the signed source-to-final wording. A keyboard or reopened-history proof never claims a single voice capture or displays the missing-audio card.

### VM-009 - Verify an edited message with voice sections

Given an original voice message is opened in the Hush composer, receives two more recorded sections and manual typing, and is then updated, when the recipient verifies the new private link, then the page shows the complete signed flow: the original recording with its timestamp, duration, and local transcription model, deterministic cleanup, each numbered composer voice section, manual editing, and the final immutable re-sign event. The wording comparison labels manual edits as an edited message, never as an AI refinement. Technical details expose the signed prior proof ID and commitment. The previous proof remains independently valid at its original private URL.

### VM-010 - Understand the record and try hush

Given a valid private proof, the recipient can distinguish recorded voice, cleanup, disclosed AI, and manual edits without opening technical details. They can compare received text locally, explore the history without losing the key fragment, and download the current app through the same release flow as the landing page. A long message or name remains readable on mobile. An unavailable proof never shows a green verification result or claims to have decrypted a message.

## Test mapping

| Journey | Automated evidence |
| --- | --- |
| VM-004 | `tests/proof.spec.ts` verifies initial decryption, fragment preservation, reload, and the recipient UI on desktop and mobile. `server/app.test.ts` verifies enrollment, publication, upload, completion, retrieval, receipt verification (also after the signing key is replaced, with the key set listing both keys), and revocation. `server/config.test.ts` verifies key generation, reuse and rotation. |
| VM-005 | `tests/proof.spec.ts` verifies the fail-closed missing-key state on desktop and mobile. |
| VM-006 | `tests/proof.spec.ts` verifies a precision mismatch fails closed. `server/app.test.ts` verifies SQLite preserves a nonzero millisecond expiry through publication and receipt creation. |
| VM-007 | `tests/proof.spec.ts` publishes through the real API, verifies the complete public root-alias redirect, and opens the forwarded canonical URL in a fresh page. `server/app.test.ts` verifies both alias paths, redirect destination, security headers, idempotency, and rejection of malformed or unknown codes. `server/config.test.ts` verifies that the production `/s/` base is derived from the canonical public origin. |
| VM-008 | `tests/proof.spec.ts` decrypts a keyboard-origin proof and asserts typed-origin copy, source changes, and the absence of voice and audio claims. Schema validation requires signed source text and rejects microphone evidence on every text-origin proof. |
| VM-009 | `tests/proof.spec.ts` decrypts a later version 2 revision and asserts the original recording, cleanup, timestamped composer sections, manual edit, prior-proof lineage, truthful wording label, and technical commitments on desktop and mobile. It also proves that signed version 1 messages remain verifiable without invented history. Schema validation restricts revision metadata to Hush-history proofs and validates every signed chronology event. |
| VM-010 | `tests/proof.spec.ts` checks the redesigned voice, typed, revision, and legacy views; source-to-final wording; private text comparison; no key/text in network requests; history navigation and reload; current download links and the download flow; long text layout; and unavailable states. |

## Change rule

Reproduce recipient bugs in Playwright with the exact malformed or cross-platform representation first. Fix the narrow verification rule, then run type checking, backend tests, OpenAPI drift checks, and all browser projects.

### VM-011 - End access and remove retained proof data

Revocation and expiry immediately block encrypted-content retrieval and new
completion or upload attempts. A cleanup worker runs at startup and every minute
in non-overlapping batches of at most 100 proofs and 100 challenges. Once a
proof has been expired or revoked for 24 hours, it claims the record, deletes
the encrypted object, then removes the metadata and cascading short alias.
Uncompleted reservations are eligible 24 hours after creation. Active completed
proofs are preserved. The terminal-state interval outlives five-minute presigned
uploads and briefly lets recipients see an explicit revoked/expired state.
After physical cleanup, requests return the existing unavailable/not-found state.

A failed storage deletion leaves a claimed, inaccessible record for retry.
Storage outages or a backlog can delay physical deletion. Installation public
keys remain registered so an existing Mac can publish again; they are not
message content. Expired enrollment/publication challenges are removed in the
same worker. In-memory IP rate limits expire independently of incoming requests,
within two minutes for the current one-minute windows, with a 10,000-entry cap
per limiter. Backups and recipient copies are outside live-storage deletion.

Evidence: `server/app.test.ts` exercises publication, revocation, rejected
completion, cleanup and unavailable aliases through the API.
`server/services/proof-cleanup.test.ts` uses real SQLite/local files and optionally
Postgres to verify expiry, abandonment, bounded batches, retries and completion
races. `server/http/rate-limiter.test.ts` verifies HTTP limits, capacity and idle
expiry. Existing `tests/proof.spec.ts` covers unavailable recipient presentation.


## Upload and storage compatibility

Encrypted uploads remain limited to 8,000,000 bytes. Both fixed-length and
chunked oversized HTTP bodies must return `413` with `body_too_large` without
storing an object. `server/app.test.ts` covers both wire formats over loopback.
`server/storage/s3-object-store.test.ts` checks presigned upload parameters,
byte-preserving storage, deletion and missing-object XML responses against a
local S3-compatible fixture using dummy credentials. No live bucket is accessed.
