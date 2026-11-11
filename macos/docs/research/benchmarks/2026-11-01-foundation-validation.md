# Hey Hush foundation validation - 2026-11-01

This record concerns the native implementation, not a model-quality benchmark. See the [journey contract](../../user-journeys/hey-hush.md) for evidence boundaries and release gates.

## Completed checks

- Debug build passed.
- Release build passed with Xcode's existing pinned OpenAPI build plugin enabled (`-skipPackagePluginValidation`).
- Release app passed `codesign --verify --deep --strict` before installation.
- Swift Testing reported 86 tests passing in 17 suites. Existing opt-in live model, speech, and favicon checks were not enabled.
- The three new assistant UI journeys passed: review and native rich paste with a preserved signature; rejection of a changed destination; Escape cancellation and rejection of truncated output.
- The XGrammar test executed native MLX token masks against a synthetic vocabulary, including Unicode and EOS. This verifies the masking integration, not Qwen task accuracy.
- HushProvenance: 27 package tests passed.
- Swift-to-Hono enrollment/publication: the required integration test passed against an isolated localhost test server with temporary storage and an ephemeral service key.

The first assistant UI run reproduced an Escape bug: NSPanel closed before the stopped state could remain visible. The panel now handles cancellation explicitly. The two other initial assertions incorrectly read the accessibility label instead of the value; their insertion and stale-target outcomes were already correct. The revised assistant journeys passed. Light and Dark screenshots were inspected, and the panel was enlarged to give short drafts more space. New assistant screenshot attachments capture only the panel.

## Wider suite follow-up

The complete UI run executed 21 tests and failed three existing journeys (eight assertions in total):

- `TranscriptionModelsJourneyTests.testUserOpensParakeetAndActivatesADownloadedModel`: Redux was not activated or reported Ready. The test requires an installed Redux model and currently continues even when its Use button is absent.
- `TypingBenchmarkJourneyTests.testTypingBenchmarkKeepsThePassageAsThePrimaryTask`: the input field was not found after the passage appeared. The preview startup and hidden input need an isolated reproduction.
- `VerifiedMessageDestinationJourneyTests.testSmartDestinationExceptionsStayCompactAndManageWebsites`: the newly typed host was not shown; the existing `chatgpt.com` exception remained. A separate reproduction is needed to distinguish input/focus behavior from persistence.

These failures are not represented as a green full-suite run or attributed to a cause without reproduction. Further foreground UI automation was deferred when the user requested manual testing and started a model download; restarting the app during that download would interrupt it.

## Installation and model state

The new Release build was installed at `/Applications/hush.app` and launched from that path for manual Accessibility approval. The previous Applications copy was retained temporarily at `/private/tmp/hush-before-assistant-20261101.app` for rollback during the manual test.

Before the user's new download, the Qwen 3.5 4B repository in Hush application data contained configuration and tokenizer files but no weights. After the user downloaded it through Hush, `model.safetensors` was present at 3,034,300,695 bytes in snapshot `0e7ffd5c629ef7719d4cbc04069232580bfa9d9c`. That installed model is user data and must be preserved during temporary benchmark cleanup. No duplicate 2B weights were downloaded for this implementation check.

Real-model constrained generation and cross-process Apple Mail behavior remain unqualified by this automated run. No new task accuracy, tokens-per-second, latency, memory, or M2 claims follow from these fixture results.
