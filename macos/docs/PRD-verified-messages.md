# PRD: Hush Verified Messages

**Status:** Product and technical decision draft

**Branch:** `feat/proof-of-origin`

**Owners:** Product, macOS, Web, Security

**Target:** Alpha research spike, then staged beta

**Working name:** Hush Origin

## 1. Executive decision

Hush will turn its local voice-to-text pipeline into a recipient-visible trust and growth loop.

When a user enables Verified Messages, every eligible message created by Hush receives a small Apple Mail-style signature:

> - Alex · Typed with Hush

`Typed with Hush` is a link when a valid proof exists. It opens a privacy-preserving proof page showing that:

1. Hush captured audio for this message.
2. Hush transcribed that capture locally.
3. The displayed raw transcript and final message belong to the same signed creation record.
4. Any local AI refinement is disclosed as a measured edit share, with the profile and model when the author chooses to disclose them.
5. The signed record has not changed since it was created.

The proof page may also show the author's self-declared Hush profile, optional original audio, and a signed snapshot of time saved. Each disclosure is under the author's control.

This is not a general AI detector and not a proof of legal identity or biological humanity. The defensible product claim is:

> This exact message has a cryptographically signed voice-origin and edit history created through Hush.

The launch system consists of:

- A local macOS proof generator and Secure Enclave-backed signing key.
- A Bun runtime with a Hono API.
- A client-encrypted proof bundle stored in object storage.
- A recipient proof page that decrypts and verifies in the browser.
- A small signature appended to eligible Hush output.

## 2. Product thesis

Hush already knows more about a message's origin than a conventional writing tool. During one dictation it temporarily holds:

- microphone samples;
- the raw local transcript;
- the locally refined final text;
- the active persona;
- the local AI provider and model;
- the destination application;
- capture and processing timing.

Today that chain disappears after insertion. Hush Origin lets the author selectively turn it into a tamper-evident receipt.

The recipient sees the benefit before installing Hush. Every verified message demonstrates three product values at once:

- Voice is faster than typing.
- AI assistance can be transparent instead of hidden.
- Privacy and provenance can coexist because processing remains local and the published proof is client encrypted.

This creates a product-led loop:

```text
Author speaks
    -> Hush creates and signs a proof
    -> recipient sees linked "Typed with Hush"
    -> recipient opens the proof
    -> recipient understands the product and trust model
    -> recipient tries Hush
    -> recipient sends another verified message
```

## 3. Naming and copy decision

### 3.1 One brand line with an honest proof state

The message line should feel like `Sent from my iPhone`: quiet, understandable, and memorable. The verification claim belongs on the destination where Hush can explain and substantiate it.

| Mode | Signature treatment | Meaning | Network required |
| --- | --- | --- | --- |
| Brand signature | `Typed with Hush` as plain text | Marketing attribution only | No |
| Verified Message | `Typed with Hush` as a link | Opens the signed canonical message | Yes |

The HUD and Hush history must distinguish these modes even though their visible words match. Never render a link unless a valid proof exists. Never show a verified badge on the destination when the proof is absent, invalid, expired, revoked, or tampered.

### 3.2 Recommended launch copy

For a published proof, link `Typed with Hush`:

> - Alex · Typed with Hush

For brand-only mode:

> - Alex · Typed with Hush

For users who do not want a name:

> Typed with Hush

`Typed with Hush` is the launch signature. It describes the delivered text artifact while keeping the attribution compact and recognizable across messaging surfaces.

### 3.3 Proof-page badge

Use on the proof page:

> Verified Hush message

Supporting text:

> Hush verified the signed capture and edit record for this message. The record has not changed.

Never use these claims:

- `Verified human`
- `100% human`
- `Human-written`
- `No AI used`, unless the signed record explicitly contains no Hush AI transformation and the copy is scoped to Hush
- `Identity verified`, unless an independent identity credential actually supports the claim

## 4. What verification means

### 4.1 Guarantees at launch

A valid proof guarantees that:

1. A registered Hush installation submitted the proof.
2. The local proof record was signed by that installation's non-exportable signing key where supported.
3. The raw transcript, final text, transformation metadata, and optional audio hash are bound to one immutable record.
4. The Hush service countersigned a salted commitment to that record.
5. The proof bundle shown in the browser matches those signatures.
6. The record is not expired or revoked at verification time.

### 4.2 Claims requiring qualification

The existence of captured audio is strong evidence that text was not pasted directly into Hush's normal dictation pipeline. It does not alone prove that:

- the named author is the speaker;
- the speaker is physically live;
- the audio was not replayed or synthetically generated;
- the author did not edit the final text outside Hush after insertion;
- every fact in the message is true;
- the visible signature in another application was not copied from another message.

The proof page resolves the last risk by displaying the canonical signed final message. A recipient can compare it with the message they received. Hush does not claim that an external application has verified the surrounding conversation.

### 4.3 Future assurance levels

Verification should be represented as assurance levels rather than one misleading binary:

| Level | Label | Evidence |
| --- | --- | --- |
| 0 | Typed with Hush | Brand attribution only |
| 1 | Hush record valid | Device signature and Hush service receipt |
| 2 | Voice origin verified | Level 1 plus audio-origin record from the capture pipeline |
| 3 | App-attested Hush record | Level 2 plus supported platform app attestation |
| 4 | Identity attached | Level 3 plus optional CAWG-compatible verified identity |

The launch UI exposes a simple status, while technical details disclose the exact assurance level.

## 5. Goals

- Make message provenance understandable in under five seconds.
- Create a tasteful viral touchpoint on every eligible Hush message after the author enables it.
- Demonstrate local AI transparency with an exact before-and-after view.
- Preserve Hush's privacy promise through selective disclosure and client-side encryption.
- Use open provenance standards where mature enough, with a clear interoperability path.
- Keep normal dictation insertion fast and reliable.
- Make invalid, expired, revoked, and tampered proofs visibly different from valid ones.
- Give recipients a compelling, contextual path to try Hush.

## 6. Non-goals

- Detecting whether arbitrary text was written by a human or AI.
- Monitoring global keyboard input.
- Claiming biometric identity from ordinary dictation audio.
- Storing proof audio by default.
- Publicly indexing message contents.
- Building a public social profile or searchable message feed.
- Requiring an account before a user can create a private proof.
- Delaying message insertion while a slow upload completes.
- Calling Hush output a conforming Content Credential before Hush passes the relevant conformance work.

## 7. Core user stories

### 7.1 Author

- As an author, I can enable Verified Messages once and have Hush apply the mode to future eligible messages.
- As an author, I can preview exactly what recipients will see before enabling it.
- As an author, I can choose whether to show my name, profile, local AI details, time-saved snapshot, raw transcript, or audio.
- As an author, I can suppress verification for one sensitive message without changing my default.
- As an author, I can exclude applications and personas from automatic proof creation.
- As an author, I can revoke a published proof from Hush.
- As an author, I can see whether Hush inserted a verified link, a brand-only fallback, or no signature.

### 7.2 Recipient

- As a recipient, I can click a short link and immediately see whether the proof is valid.
- As a recipient, I can see the exact final message that was signed.
- As a recipient, I can understand how voice capture and local AI contributed without needing cryptography knowledge.
- As a recipient, I can inspect the raw transcript, edit diff, model, signature details, and optional audio when disclosed.
- As a recipient, I can distinguish verified identity, self-declared identity, and no identity.
- As a recipient, I can try Hush without the proof page becoming an advertisement first.

## 8. Author experience

### 8.1 Onboarding

Add a `Verified Messages` setup card after the user has completed at least five successful dictations. Do not interrupt first-run microphone or accessibility onboarding.

Title:

> Let recipients see where your words came from

Body:

> Add a small proof link to messages created from your voice. Hush signs the capture and local edit history. You decide what each proof reveals.

Preview:

```text
Perfect, let's lock in Thursday at 10.

- Alex · Typed with Hush
```

Actions:

- `Set up verified messages`
- `Not now`

Setup steps:

1. Choose a linked Verified Message or brand attribution only.
2. Choose a display name or anonymous mode.
3. Select default disclosures.
4. Select expiry.
5. Review one realistic message preview.
6. Confirm with `Enable verified messages`.

### 8.2 Default state

- Existing users: off after upgrade.
- New users: visibly proposed after demonstrated product value, not silently enabled.
- Audio sharing: off.
- Raw transcript sharing: on for Verified Messages, but explicitly visible in setup.
- Exact AI diff: on when local AI was used.
- AI provider/model name: on.
- Persona name: on.
- Time-saved snapshot: on.
- Public name/avatar: off until supplied.
- Proof expiry: 30 days.

Brand attribution may be offered independently because it does not upload message data. It must still be a visible choice, never a hidden paid-plan default.

### 8.3 Persistent mode with per-message control

Once enabled, Verified Messages apply to every eligible Hush insertion. The HUD shows a compact proof state during processing:

- `Preparing proof`
- `Verified link added`
- `Typed with Hush - proof unavailable`
- `No signature - excluded app`

The user can hold an additional modifier while releasing the dictation hotkey to suppress the proof for that message. The HUD must confirm `Sent without proof` before hiding.

Add application and persona rules:

- Always verify
- Brand signature only
- Never add a signature

Default exclusions:

- password managers;
- terminals;
- code editors;
- secure text fields;
- applications the user manually excludes.

### 8.4 Settings

Add a `Verified Messages` destination containing:

- master mode switch;
- exact signature preview;
- display identity;
- default disclosure toggles;
- proof expiry;
- app/persona rules;
- proof history with status and revoke action;
- storage and privacy explanation;
- signing-key status;
- `Rotate signing identity` action;
- `Delete all published proofs` action with confirmation.

## 9. Recipient proof page

### 9.1 Information hierarchy

Use progressive disclosure inspired by C2PA and CAWG guidance.

Level 1, visible immediately:

- verification status;
- author's self-declared or verified name, if disclosed;
- canonical signed final message;
- `Created from voice`;
- AI edit share, or `No local AI refinement`;
- proof creation time and expiry;
- subtle `Try Hush` action.

Level 2, one disclosure action:

- original transcript;
- token-level before-and-after diff;
- a browser-local comparison against text pasted by the recipient;
- optional audio player;
- persona and local model;
- time-saved snapshot;
- explanation of what Hush verified.

Level 3, technical details:

- proof version;
- assurance level;
- content commitment;
- signature algorithms;
- Hush service receipt;
- signer status;
- C2PA validation report when applicable;
- creation timestamp;
- revocation status;
- privacy and limitations.

### 9.2 Reference layout

```text
┌──────────────────────────────────────────────────────────────┐
│ Hush                                             Try Hush     │
├──────────────────────────────────────────────────────────────┤
│ ✓ Verified Hush message                                    │
│   Valid signed record · created 2 minutes ago                │
│                                                              │
│ "Perfect, let's lock in Thursday at 10."                    │
│                                                              │
│ Alex                                                         │
│ Created from voice · 12% changed by local AI                 │
├──────────────────────────────────────────────────────────────┤
│ How this message was made                                    │
│ 1  Voice captured on Alex's Mac                              │
│ 2  Transcribed locally with Large v3                         │
│ 3  Refined locally with Business · Apple Intelligence        │
│ 4  Signed and published as an encrypted proof                │
│                                                              │
│ [Compare received text]  [Original vs refined]  [Play voice]│
├──────────────────────────────────────────────────────────────┤
│ Alex has saved 42 hours with Hush                            │
│ Signed activity snapshot · optional disclosure               │
├──────────────────────────────────────────────────────────────┤
│ What was verified?                         Technical details  │
└──────────────────────────────────────────────────────────────┘
```

### 9.3 Status states

| State | Treatment | Copy |
| --- | --- | --- |
| Valid | Green check, calm | `Verified Hush message` |
| Valid without audio disclosure | Green check | `Hush capture record verified` |
| Expired | Neutral clock | `This proof expired` |
| Revoked | Neutral/amber | `The author revoked this proof` |
| Tampered | Red warning | `This record does not match its signature` |
| Unknown signer | Amber warning | `The signature is valid, but its signer is not trusted by Hush` |
| Missing key fragment | Locked state | `This private proof link is incomplete` |
| Not found | Neutral | `This proof is unavailable` |

Do not place a green verification icon next to a self-declared name. Identity and content-origin status must remain visually separate.

### 9.4 Canonical-message comparison

The proof page always shows the exact final message covered by the signatures. This is the source of truth if someone edits an Instagram caption, email, direct message, or post while leaving the same proof link attached.

Add `Compare the message you received` below the canonical message. It opens a local text area where the recipient can paste the surrounding message. The browser normalizes only platform line endings and then reports:

- `Exact match` when every signed character matches;
- `Formatting differs` when only approved whitespace normalization differs;
- `Message changed` with a character-level diff for any substantive difference.

The pasted comparison text must never leave the browser, enter analytics, persist to storage, or become part of the URL. Explain this directly beside the input:

> Compared privately in your browser. Nothing you paste is uploaded.

Hush cannot automatically inspect the surrounding Instagram, Slack, email, or web page because the verifier is isolated from that application's content. Manual paste is the honest cross-platform comparison mechanism.

### 9.5 Growth without compromising trust

The proof must lead with recipient value. The product CTA appears only after the verified message and origin summary.

Recommended CTA:

> Speak it. Keep it private. Send it with proof.

Button:

> Try Hush for Mac

Do not add referral popups, countdowns, forced email collection, or deceptive download controls.

## 10. AI transparency

### 10.1 Use `AI edit share`, not `AI percentage`

An objective percentage of authorship does not exist. Hush can measure only the transformation it performed between its raw transcript and final output.

Define:

```text
changedTokens = substitutions + insertions + deletions
referenceTokens = max(rawTokenCount, finalTokenCount, 1)
aiEditShare = min(changedTokens / referenceTokens, 1)
```

Use a deterministic, Unicode-aware tokenization and minimum-edit alignment. Store the algorithm identifier and version in the proof.

Display:

- `12% changed by local AI`
- `Light local refinement`
- `See exact changes`

Do not display:

- `88% human`
- `12% AI-generated`

Those phrases make a stronger authorship claim than the data supports.

### 10.2 Separate transformations

The signed action chain distinguishes:

1. local speech transcription;
2. deterministic punctuation or formatting cleanup;
3. local LLM refinement;
4. explicit manual edit inside Hush, if such an editor is added later.

The proof page can summarize these actions but must preserve exact details in the technical view.

### 10.3 No passive AI detector

Hush must not scan arbitrary pasted or typed text and present a human/AI badge. Research shows that current detectors can be defeated by paraphrasing and can misclassify human text. Provenance is stronger because it records the process Hush actually observed instead of guessing from style.

## 11. Privacy model

### 11.1 Privacy promise

The Hush service must not receive plaintext message content, raw transcripts, or audio for a private proof.

The app performs locally:

- transcription;
- AI refinement;
- diff calculation;
- proof construction;
- signing;
- encryption.

The backend stores:

- encrypted proof bytes;
- a salted commitment;
- ciphertext hash;
- timestamps and expiry;
- revocation state;
- signing-key enrollment metadata;
- coarse operational metrics that contain no message content.

### 11.2 Capability link

Use a URL whose fragment contains the decryption key:

```text
https://hush.app/p/7nQ4kP#k=<base64url-key>
```

The URL fragment is not sent in the HTTP request. Browser JavaScript reads it locally, downloads ciphertext, decrypts the bundle, and verifies the signatures.

Anyone who receives the complete URL can open the proof. The UI must call this a private share link, not access control. Forwarding the message forwards access.

### 11.3 Encryption

- Generate a random 256-bit content-encryption key per proof.
- Encrypt with AES-256-GCM.
- Generate a fresh 96-bit nonce per encrypted object.
- Bind proof version, slug, and ciphertext content type as additional authenticated data.
- Never log keys, fragments, plaintext, or decrypted manifests.
- Keep the decryption key only in the inserted URL and the user's local proof history.
- Store audio as a separately encrypted object so the user can revoke or omit it independently.

### 11.4 Disclosure controls

Each proof records explicit booleans for:

- final message;
- raw transcript;
- exact diff;
- AI edit share;
- persona;
- provider/model;
- original audio;
- display name/avatar;
- activity snapshot.

Changing defaults affects future proofs only. A published proof is immutable. To remove data, revoke it and create a new proof.

### 11.5 Linkability

A stable public signing fingerprint can allow recipients to correlate proofs. The recipient-facing bundle must therefore expose a Hush service receipt and a per-proof public key, not the installation root fingerprint.

The per-proof key is certified by the local installation key. The backend validates that chain before issuing a Hush receipt. The public proof omits the installation certificate unless the author chooses a persistent public identity.

The security design review must confirm that no stable installation identifier appears in recipient-visible bytes, URLs, headers, or analytics.

## 12. Cryptographic design

### 12.1 Key hierarchy

1. On supported Macs, create an installation P-256 signing key in the Secure Enclave.
2. Store only its persistent reference in Keychain.
3. Enroll the public key with the Hush API through a challenge-response flow.
4. Generate a fresh per-proof P-256 key pair.
5. Have the installation key certify the per-proof public key and proof metadata.
6. Use the per-proof key to sign the canonical inner manifest.
7. Have the Hush service validate the enrollment signature and countersign a salted commitment.

On unsupported hardware, use a Keychain-protected software P-256 key and lower the displayed assurance level. Never silently present it as hardware backed.

### 12.2 Canonical inner manifest

The manifest must use deterministic canonical serialization. Prefer C2PA structures where the official SDK proves production-ready during the standards spike. If a Hush envelope is required for the first beta, use deterministic CBOR or RFC 8785 JSON canonicalization and version it from the first byte.

Required fields:

```text
proof_version
proof_id
created_at
expires_at
capture:
  source = microphone
  duration_ms
  sample_rate
  audio_sha256?
transcription:
  raw_text
  model_id
  model_display_name
  language
transformations[]:
  kind
  provider?
  model?
  persona?
  algorithm_version
final_text
ai_edit_share?
disclosures
activity_snapshot?
per_proof_public_key
installation_certificate
nonce
```

Do not store destination application or bundle identifier in a published proof unless a future user-visible disclosure explicitly adds it.

### 12.3 Commitment and Hush receipt

The app computes:

```text
innerCommitment = SHA256(canonicalManifest || randomCommitmentNonce)
```

The random commitment nonce remains inside the encrypted bundle. The backend sees only the commitment, which prevents practical dictionary attacks against short common messages.

The Hush service receipt covers:

- proof ID;
- inner commitment;
- ciphertext SHA-256;
- created and expiry times;
- assurance level;
- Hush receipt version;
- repository object identifier.

The browser verifies:

1. Hush service receipt signature.
2. Ciphertext hash.
3. AES-GCM authentication.
4. Per-proof manifest signature.
5. Recomputed inner commitment.
6. Manifest consistency and expiry.
7. Online revocation state.

### 12.4 Replay and ordering

- Every enrollment and proof request uses a server challenge.
- Challenges are single use and expire after five minutes.
- Proof IDs are 128-bit or stronger random values.
- The server rejects duplicate commitments and stale challenges.
- When App Attest is available, validate assertion counters server-side.

### 12.5 App attestation

Hush currently targets macOS 15. App Attest support for native macOS arrives only on macOS 27+, so launch verification cannot depend on it.

Launch wording must therefore describe a signature from a registered Hush installation, not Apple-attested application integrity. Add App Attest as a higher assurance level for eligible systems without removing support for older Macs.

### 12.6 Original audio disclosure

Original audio is the strongest understandable optional disclosure because it lets a recipient hear what Hush captured and compare it with both the transcript and refined message.

When enabled, the proof page shows:

- an audio player labeled `Original voice capture`;
- duration and capture time;
- a sentence stating that the file was encrypted before upload;
- transcript highlighting synchronized to the audio when word timestamps are available;
- the signed audio hash in technical details.

Audio sharing remains off by default. The author must see the exact audio duration and proof expiry before publishing. The proof must never infer consent from the global message-verification switch because audio has a materially higher privacy impact than text provenance.

### 12.7 Human presence and synthetic-audio boundary

Ordinary dictation is not a liveness ceremony. macOS can expose both hardware and virtual capture devices, and replayed or generated audio can enter through a physical speaker or virtual audio driver. A signature can prove which audio bytes Hush bound to the record, but cryptography cannot determine whether those bytes came from a live biological speaker.

Use three separate concepts:

| Signal | Defensible label | What it means |
| --- | --- | --- |
| Normal Hush capture | `Voice origin verified` | Hush signed the audio-to-text creation record |
| Original audio disclosed | `Original capture available` | Recipient can hear the exact signed audio |
| Interactive challenge completed | `Live challenge completed` | The speaker responded to a fresh prompt during capture |

Do not rename any of these states `Human verified`.

A future explicit `Live proof` mode may add:

1. A server-issued random challenge bound to the proof nonce.
2. Two or three unpredictable words shown immediately before capture.
3. A requirement that the speaker says those words and then continues the message in one uninterrupted recording.
4. On-device timing, replay, and synthetic-speech risk signals.
5. Capture-device classification, with virtual devices rejected for this mode.
6. Optional local speaker matching against a separately consented voice enrollment.

Even this mode is evidence of interactive presence, not certainty. Real-time speech synthesis can answer challenges, detection models have false positives and false negatives, virtual-device classification can be bypassed, and voice biometrics are sensitive personal data. Any anti-spoof model result is a risk signal shown in technical details, never the sole basis of a green verified state.

Recommendation:

- Ship signed origin and optional original audio first.
- Research `Live proof` only for high-assurance, user-initiated messages.
- Never add a liveness challenge to the everyday viral message flow.
- Do not collect or upload a reusable voiceprint in the launch product.

## 13. Standards and SDK decision

### 13.1 C2PA

C2PA 2.4 is the correct long-term provenance model. It provides cryptographically bound manifests, action history, AI-related assertions, audio support, and an emerging unstructured-text embedding method.

Decision:

- Model the Hush action chain so it maps cleanly to C2PA from day one.
- Run a production spike using the official `c2pa-swift` package.
- Store a detached C2PA manifest in the proof bundle if signing and validation meet the quality gate.
- Do not rely on invisible Unicode variation-selector embedding at launch. The specification marks that mechanism as under review, and message platforms may normalize or strip it.
- Keep the visible HTTPS proof link as the durable discovery mechanism.
- Do not display the Content Credentials mark until Hush meets the applicable conformance and trust-list requirements.

### 13.2 C2PA Swift quality gate

The official Swift SDK supports macOS, native signing/verification, stream APIs, custom manifests, and Secure Enclave signing. It is still young and currently documents a `0.0.1` package release.

The spike must prove:

- deterministic output for text and audio sidecars;
- macOS 15 support in the signed Hush app;
- Intel fallback behavior;
- Secure Enclave key lifecycle;
- no main-thread stalls;
- release binary size impact;
- successful validation in official tools;
- malformed-manifest safety;
- API stability behind a Hush-owned adapter.

Create a `ProvenanceSigner` protocol so C2PA can be replaced or upgraded without coupling `DictationCoordinator` to an SDK.

### 13.3 CAWG identity

CAWG identity assertions may later attach a verified individual or organization identity. They are optional and distinct from content provenance.

Launch supports:

- anonymous author;
- self-declared display name;
- self-declared profile image.

Self-declared identity must be labeled as such. A verified identity badge requires a real CAWG-compatible credential and issuer relationship.

## 14. macOS architecture

### 14.1 Existing integration point

`DictationCoordinator.runTranscription` currently has all required inputs before insertion:

- `samples`;
- `raw`;
- `processed`;
- active profile;
- provider;
- transcription model;
- duration;
- destination application.

Create proof preparation after post-processing and before final insertion. Do not move cryptography or networking directly into `DictationCoordinator`.

### 14.2 Proposed modules

```text
VerifiedMessages/
  VerifiedMessageCoordinator.swift
  VerifiedMessagePolicy.swift
  ProofManifest.swift
  ProofDisclosure.swift
  ProofPublisher.swift
  ProofHistoryStore.swift
  SignatureFormatter.swift
  Crypto/
    InstallationKeyStore.swift
    PerProofSigner.swift
    ProofEncryptor.swift
    ProvenanceSigner.swift
    C2PAProvenanceSigner.swift
  Network/
    ProofAPIClient.swift
    ProofUploadClient.swift
```

Responsibilities:

- `VerifiedMessagePolicy`: decides whether this app/persona/message is eligible.
- `VerifiedMessageCoordinator`: orchestrates manifest, signature, encryption, upload, and fallback.
- `ProofManifest`: immutable canonical data model.
- `ProofPublisher`: owns API and object-upload state machine.
- `ProofHistoryStore`: stores local URL key, revocation secret, expiry, and status.
- `SignatureFormatter`: produces plain-text and rich-text signatures.

### 14.3 Audio lifecycle

Today Hush discards samples after transcription. Verified Messages must preserve that default.

- If audio disclosure is off, hash a versioned canonical audio representation in memory, bind the hash to the manifest, and release samples after proof creation.
- If audio disclosure is on, encode mono AAC locally, encrypt it, upload it, then zero and release temporary buffers as practical.
- Never write unencrypted audio to a persistent temporary file.
- Enforce a launch limit of two minutes and 5 MB encrypted audio per proof.

The audio hash proves which bytes were bound to the proof. It does not provide recipients audio when disclosure is off.

### 14.4 Text insertion

`TextInserter` currently writes only `.string` to `NSPasteboard`. Extend it to accept an insertion payload:

```swift
struct TextInsertionPayload {
    let plainText: String
    let html: Data?
    let rtf: Data?
}
```

Provide:

- HTML anchor for compatible rich editors;
- RTF link for native macOS editors;
- plain-text fallback containing the short proof URL;
- original plain message when no signature is allowed.

Test the full compatibility matrix in Mail, Messages, Slack, LinkedIn in Safari and Chrome, Gmail, Notion, Notes, TextEdit, Microsoft Word, and common terminals/editors. Rich insertion must never paste raw HTML into a plain-text field.

### 14.5 Latency and fallback

Proof publication must not make voice insertion feel slow.

Budgets on a typical broadband connection:

- manifest, diff, signing, and encryption: p95 below 100 ms;
- API receipt before insertion: p95 below 300 ms;
- no-audio proof completion: p95 below 700 ms;
- total added time before text insertion: hard cap 500 ms.

If a valid proof URL is unavailable at the cap:

1. Insert the message with `Typed with Hush`, if enabled.
2. Show `Proof unavailable - message inserted normally`.
3. Do not create or append a verification link.
4. Do not edit the destination later without explicit user action.

Offline mode always follows this fallback. Never create a dead or misleading verification link.

### 14.6 Local proof history

Store in Application Support using a versioned database:

- proof ID;
- complete private URL;
- final-text preview;
- created/expiry time;
- upload state;
- revocation capability;
- disclosed fields;
- recipient-visible identity mode.

This history is private local data and follows its own retention setting. Clearing local proof history must warn that it removes the user's ability to open and revoke proofs unless server-side account recovery is added later.

## 15. Web architecture

### 15.1 Repository direction

The current website is a static Vite and React application using pnpm. Verified Messages requires a backend. Standardize the web repository on Bun rather than operating two package managers.

Recommended workspace:

```text
webapp/
  apps/
    web/              # existing Vite, React, TanStack Router
    api/              # Hono application running on Bun
  packages/
    contracts/        # schemas, OpenAPI types, shared errors
    provenance/       # browser/server verification primitives
    ui/               # shared visual components when justified
  bun.lock
  package.json
```

Migration requirements:

- preserve current website routes and visual output;
- replace pnpm scripts and lockfile in one atomic migration;
- use Bun workspaces;
- run TypeScript in strict mode;
- keep API and web deployment independently scalable;
- generate clients from one contract rather than duplicating request types.

### 15.2 Backend stack

- Runtime: Bun
- HTTP framework: Hono
- Validation/OpenAPI: `@hono/zod-openapi` or an equally typed Hono-native contract
- Database: PostgreSQL
- Object storage: private Cloudflare R2 bucket or S3-compatible equivalent
- Crypto: Web Crypto APIs where available, with audited libraries only for missing canonicalization/C2PA support
- Browser verification: official current C2PA web packages when applicable
- Observability: structured logs, OpenTelemetry traces, content-free metrics
- Deployment: containerized Bun service behind a managed TLS edge

Hono is appropriate because it uses Web Standards and officially supports Bun. Keep runtime-specific code at the storage, database, and process boundaries.

### 15.3 Canonical domain

The website currently mixes `hush.app` email addresses with `hush.dmg` referral links. Verified proof links require one stable, trustworthy origin.

Decision:

- Use `https://hush.app/p/:slug` as the product default unless domain ownership dictates otherwise.
- Configure it through `HUSH_PUBLIC_BASE_URL` in every environment.
- Redirect every legacy proof domain permanently to the canonical domain without dropping the fragment.
- Never use a link shortener or third-party redirector for proofs.

### 15.4 API surface

```text
POST   /v1/installations/challenges
POST   /v1/installations/enroll
POST   /v1/proofs/challenges
POST   /v1/proofs
POST   /v1/proofs/:id/complete
GET    /v1/proofs/:slug
GET    /v1/proofs/:slug/status
POST   /v1/proofs/:slug/revoke
DELETE /v1/proofs/:slug
GET    /health/live
GET    /health/ready
```

`POST /v1/proofs` accepts only:

- challenge ID;
- installation certificate/assertion;
- per-proof public key;
- salted inner commitment;
- ciphertext hash and size;
- expiry;
- requested assurance metadata;
- signature over the request.

It returns:

- proof ID and slug;
- short-lived single-object PUT URL;
- expected headers and checksum;
- Hush service receipt or a receipt challenge completed after upload;
- revocation capability.

The upload URL is a bearer capability. Restrict content type, object key, size, checksum, and expiry. A proof is not readable until `/complete` confirms the exact object and receipt.

### 15.5 Data model

`installation_keys`

```text
id UUID PK
public_key BYTEA UNIQUE
key_kind ENUM(secure_enclave, keychain, app_attest)
app_version TEXT
platform_version TEXT
created_at TIMESTAMPTZ
last_seen_at TIMESTAMPTZ
revoked_at TIMESTAMPTZ NULL
attestation_metadata JSONB NULL
```

`proofs`

```text
id UUID PK
slug TEXT UNIQUE
installation_key_id UUID FK
object_key TEXT UNIQUE
inner_commitment BYTEA UNIQUE
ciphertext_sha256 BYTEA
ciphertext_size BIGINT
assurance_level SMALLINT
receipt_version SMALLINT
created_at TIMESTAMPTZ
expires_at TIMESTAMPTZ
completed_at TIMESTAMPTZ NULL
revoked_at TIMESTAMPTZ NULL
deleted_at TIMESTAMPTZ NULL
```

`challenges`

```text
id UUID PK
purpose ENUM(enroll, publish)
nonce BYTEA UNIQUE
installation_key_id UUID NULL
expires_at TIMESTAMPTZ
consumed_at TIMESTAMPTZ NULL
```

Store revocation capabilities as an Argon2id hash, never plaintext.

### 15.6 Proof-page delivery

The server renders a content-free HTML shell for `/p/:slug` with:

- `noindex, nofollow, noarchive`;
- no message-specific Open Graph content;
- a strict Content Security Policy;
- no third-party analytics or advertising scripts;
- Subresource Integrity for any static cross-origin resource;
- a generic title such as `Private Hush proof`.

The browser:

1. reads the decryption key from the fragment;
2. fetches metadata and ciphertext;
3. checks the ciphertext hash;
4. verifies the Hush receipt;
5. decrypts locally;
6. verifies the inner manifest;
7. renders only escaped structured data;
8. clears the key from visible URL state with `history.replaceState` after loading.

The page must work without cookies or an account.

## 16. Security and abuse model

### 16.1 Threats

- copied or spoofed signature text;
- modified encrypted object;
- malicious or modified Hush client;
- replayed proof-publication request;
- replayed or synthetic microphone audio;
- stolen private proof URL;
- public-key correlation across proofs;
- abusive or illegal encrypted content;
- oversized audio uploads;
- XSS through decrypted message fields;
- proof-page phishing or domain impersonation;
- server or object-store breach;
- accidental leakage through logs, analytics, previews, or referrers.

### 16.2 Required mitigations

- Canonical signed final text shown on the proof page.
- Hardware-backed local keys where supported.
- App Attest on eligible macOS versions.
- Single-use server challenges.
- Hush countersigned commitment receipts.
- Client-side authenticated encryption.
- Private object bucket and short-lived upload URLs.
- Strict schema and size limits before rendering.
- Text-only rendering by default, with no decrypted HTML interpretation.
- CSP, Trusted Types where supported, and no third-party scripts.
- `Referrer-Policy: no-referrer`.
- Rate limits by installation, IP risk score, and proof size.
- Maximum expiry and object lifecycle deletion.
- Recipient-visible report action that can revoke public serving of ciphertext without requiring decryption.
- Automated conformance, fuzz, malformed-input, and dependency security testing.

### 16.3 Encrypted-content moderation boundary

End-to-end encryption prevents server-side content moderation. Compensating controls are:

- small object and duration limits;
- finite default expiry;
- no public index or discovery;
- no anonymous bulk upload API;
- registered installation key required;
- rate and abuse controls;
- report-and-disable by proof slug;
- terms that prohibit unlawful use;
- auditable deletion processes.

Disabling a reported object is not a statement about the decrypted content. The service can stop serving its ciphertext while preserving privacy.

## 17. Reliability and operations

### 17.1 Service objectives

- Proof metadata API availability: 99.95% monthly.
- Proof-page shell availability: 99.99% monthly.
- Valid no-audio proof publish latency: p95 below 700 ms.
- Proof metadata read latency: p95 below 150 ms at the edge.
- Verification correctness: no known false-valid state.
- Expired object deletion: within 24 hours of expiry.

Cryptographic correctness takes priority over availability. Any ambiguous validation result fails closed and never shows a green verified state.

### 17.2 Observability

Allowed metrics:

- publish success/failure by coarse reason;
- latency by phase;
- encrypted byte size buckets;
- proof assurance level;
- expiry bucket;
- verification status counts;
- CTA click counts only with privacy-preserving first-party aggregation.

Forbidden telemetry:

- message text or hashes without salting;
- transcript or diff;
- audio;
- decryption key or URL fragment;
- profile/persona names;
- destination app per proof;
- stable recipient identifiers.

## 18. Rollout plan

### Phase 0: standards and threat-model spike

- Prototype Secure Enclave signing.
- Validate `c2pa-swift` text/audio sidecar flow.
- Validate browser verification.
- Test C2PA tooling and malformed payloads.
- Complete an external security design review.
- Decide Hush envelope versus C2PA-first implementation behind `ProvenanceSigner`.
- Resolve the canonical product domain.

Exit gate: one locally generated proof verifies across app, API, and browser, and every displayed claim maps to evidence.

### Phase 1: internal end-to-end proof

- Bun workspace migration.
- Hono API, Postgres, and private R2 integration.
- Installation enrollment.
- Client-encrypted no-audio proof.
- Plain-text proof signature.
- Browser status, final text, raw transcript, and diff.
- Local proof history and revocation.

Exit gate: internal adversarial review and full failure-state UX.

### Phase 2: private alpha

- Rich-text insertion compatibility.
- Settings, per-app rules, and HUD states.
- Optional self-declared profile and time-saved snapshot.
- Optional encrypted audio.
- Expiry and deletion jobs.
- Recipient feedback and comprehension research.

Exit gate: at least 90% of test recipients accurately explain what is and is not verified after viewing the page.

### Phase 3: public beta

- App Attest for eligible macOS versions.
- C2PA conformance work if the implementation is mature.
- CAWG identity prototype.
- Abuse operations and incident playbooks.
- Privacy and security documentation.
- Growth experiment comparing `Typed with Hush` with `Voice-verified by Hush`.

## 19. Success metrics

Primary:

- Eligible messages with a valid proof after users enable the mode.
- Proof-page open rate.
- Proof-page verification completion rate.
- Recipient-to-install conversion attributed without cross-site tracking.
- Verified Message mode retention after 30 days.

Trust and quality guardrails:

- Signature disable rate.
- Per-message suppression rate.
- Proof publish failure and fallback rate.
- Recipient comprehension score.
- Privacy support contacts.
- Abuse reports per 10,000 proofs.
- Proof-page tamper or ambiguous-validation incidents.
- Added insertion latency.

Do not optimize signature prevalence at the expense of explicit consent, correct verification claims, or message quality.

## 20. Acceptance criteria

### 20.1 macOS

1. A user can enable and disable Verified Messages with an exact preview.
2. Every eligible successful dictation receives a valid proof or an honest non-verified fallback.
3. Linked `Typed with Hush` is never inserted before the API has issued a valid proof receipt.
4. The signed manifest binds raw transcript, final text, capture metadata, transformation data, and disclosed audio hash.
5. AI edit share is deterministic and covered by unit fixtures.
6. Audio is never persistently written unencrypted.
7. Proof creation does not break normal raw-transcript fallback when local AI fails.
8. Offline and timeout paths insert the message within the hard latency cap.
9. App/persona exclusions and one-message suppression work.
10. The HUD announces the actual signature outcome.
11. Proof history supports open, copy, revoke, and local deletion.
12. Clearing history cannot crash with proof mode in any state.

### 20.2 API

1. Every mutation validates a typed schema and bounded payload.
2. Enrollment and publish challenges are single use.
3. Invalid installation or per-proof signatures are rejected.
4. Upload capabilities are limited to one object, content type, checksum, size, and short expiry.
5. Incomplete uploads never become readable proofs.
6. Revocation requires the capability secret and is idempotent.
7. Expiry is enforced at read time and by object lifecycle cleanup.
8. Logs and traces contain no plaintext, keys, fragments, or stable recipient identifiers.
9. Database and object-store failure modes are covered by integration tests.
10. API compatibility is versioned and documented through OpenAPI.

### 20.3 Web verifier

1. Decryption and inner verification happen in the browser.
2. The page shows no valid state until every required check passes.
3. The canonical signed final message is always visible for a valid proof.
4. A recipient can paste received text and get an exact local match, formatting-only result, or substantive diff without a network request.
5. Self-declared identity is not styled as independently verified.
6. Missing key, expired, revoked, tampered, unknown signer, and unsupported versions each have distinct accessible states.
7. Message data is escaped and never interpreted as HTML.
8. The page sends no referrer and uses no third-party scripts.
9. The page is responsive, keyboard accessible, screen-reader clear, and visually correct at 320 px through desktop widths.
10. The page is not indexed and does not expose message content in metadata.
11. A recipient can understand the verification boundary without opening technical details.

## 21. Test strategy

### 21.1 End-to-end journeys

1. Fresh user enables verification and sends a Mail message.
2. User sends to Slack, Gmail, LinkedIn, Messages, Notes, and a plain-text editor.
3. User refines with each local AI provider and with AI off.
4. User enables audio, opens the recipient page, plays it, and revokes it.
5. User goes offline before dictation and receives a truthful brand-only fallback.
6. API times out after signing but before upload completion.
7. Object upload succeeds but completion fails, then safely retries.
8. Recipient opens a link with a missing or altered fragment.
9. Ciphertext, receipt, manifest, final text, or signature is modified one byte at a time.
10. Proof expires while the recipient page is open.
11. User rotates installation keys and old proofs remain verifiable but show the correct status.
12. User clears local proof history, app history, and all app data in every order.

### 21.2 Security tests

- Known-answer cryptographic vectors.
- Canonicalization cross-language fixtures between Swift and TypeScript.
- Fuzz manifest parsing and decrypted field rendering.
- Replay and race tests for challenges and completion.
- Oversized, compressed, malformed, and polyglot objects.
- XSS corpus in every string field.
- URL-fragment and referrer leakage checks.
- Dependency and supply-chain scanning.
- C2PA attack-tool suite when C2PA manifests are enabled.
- Red-team copied-signature and modified-client scenarios.

### 21.3 Visual QA

Capture reference screenshots for every verifier state on:

- iPhone Safari widths;
- Android Chrome widths;
- macOS Safari and Chrome;
- Windows Chrome and Edge;
- light and dark system preferences;
- increased contrast;
- 200% browser zoom;
- long messages, long names, RTL text, CJK, emoji, and combining characters.

Any clipped proof text, ambiguous status color, layout jump after decryption, or CTA that visually outranks the proof is a release blocker.

## 22. Product decisions still requiring validation

These are research questions, not reasons to weaken the architecture:

1. Whether `Typed with Hush` or `Voice-verified by Hush` produces better comprehension without reducing sharing.
2. Whether raw transcript should default on or require a second explicit toggle.
3. Whether a 7-day or 30-day default expiry better matches real message lifetimes.
4. Whether recipients value optional audio enough to justify the privacy and storage surface.
5. Whether the signed time-saved snapshot helps discovery or distracts from message trust.
6. Which rich-text formats survive each target application without visual artifacts.

The following are already decided:

- No `verified human` claim.
- No arbitrary AI-text detector.
- No plaintext proof storage.
- No audio by default.
- No linked verification signature when publishing fails.
- Bun and Hono are the backend foundation.
- The canonical signed message is shown on the verifier.
- Proof content is not indexed.

## 23. Research basis

- [C2PA 2.4 explainer](https://spec.c2pa.org/specifications/specifications/2.4/explainer/Explainer.html) defines Content Credentials as cryptographically bound provenance and explicitly separates provenance from factual truth.
- [C2PA 2.4 technical specification](https://spec.c2pa.org/specifications/specifications/2.4/specs/C2PA_Specification.html) specifies the trust model, content binding, AI-related actions, privacy controls, audio formats, and unstructured-text embedding.
- [C2PA Conformance Program](https://c2pa.org/conformance/) explains the official trust list and why Hush must not imply interoperable conformance before completing that process.
- [C2PA Swift](https://github.com/contentauth/c2pa-swift) is the official Apple-platform wrapper, with macOS support, native signing and verification, stream APIs, and Secure Enclave support.
- [CAWG identity framework](https://cawg.io/about/identity-framework/) separates creator identity from the underlying content-provenance framework.
- [CAWG UX guidance](https://cawg.io/ux-guidance/1.0/) recommends progressive disclosure, clear verification scope, and explicit control over personally identifying information.
- [Apple Secure Enclave P-256 signing](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/signing) provides hardware-backed ECDSA signing on supported Macs.
- [Apple App Attest guidance](https://developer.apple.com/documentation/DeviceCheck/establishing-your-app-s-integrity) describes server-verified app and request integrity. [Apple's WWDC26 update](https://developer.apple.com/videos/play/wwdc2026/201/) places native macOS support at macOS 27+, so it cannot be a launch dependency for Hush's macOS 15 baseline.
- [Can AI-Generated Text be Reliably Detected?](https://arxiv.org/abs/2303.11156) demonstrates fundamental and practical weaknesses in passive AI-text detection, supporting the decision to record provenance instead of guessing authorship.
- [ASVspoof](https://www.asvspoof.org/) documents the continuing research challenge of distinguishing bona fide, replayed, synthesized, converted, and deepfake speech. It supports treating audio anti-spoofing as a probabilistic risk signal rather than cryptographic proof of humanity.
- [Apple AVFoundation capture setup](https://developer.apple.com/documentation/avfoundation/capture-setup) explicitly models capture inputs as hardware or virtual devices, which is why an ordinary microphone capture cannot by itself establish physical liveness.
- [Hono documentation](https://hono.dev/docs) and [Bun's official Hono guide](https://bun.sh/docs/guides/ecosystem/hono) support the selected Bun and Hono backend.
- [Cloudflare R2 presigned URL guidance](https://developers.cloudflare.com/r2/api/s3/presigned-urls/) documents scoped direct-upload capabilities and warns that presigned URLs are bearer tokens.
- [C2PA Attacks](https://github.com/contentauth/c2pa-attacks) provides a security test tool for Content Credentials implementations.

## 24. Final product position

Hush should not try to win trust by claiming it can detect humanity from prose. It should show the creation evidence it uniquely possesses.

The signature is the viral entry point:

> - Alex · Typed with Hush

The click earns that claim by revealing a signed, privacy-preserving chain:

> voice captured locally -> transcribed locally -> optionally refined locally -> exact final message signed -> encrypted proof published

That is stronger, more useful, and more defensible than an AI detector. It makes local-first privacy visible to the recipient and turns every verified message into a live demonstration of Hush.
