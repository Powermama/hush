# Browser navigation contract

## Reproduction

The actual Hush controller and installed Qwen3.5-4B, with thinking disabled, received:
"Open YouTube, search for David Guetta, and open the first video."
The Debug browser probe injected the transcript, so this checks model/native browser
execution rather than microphone transcription or spoken playback.

The 2026-11-02 run E88DE982-5968-4D74-85DC-AADDE70F7B89 had Accessibility permission.
It opened a blank Safari tab, searched Google for David Guetta, then stopped after
30.81 seconds. The final destination was a populated Google search page. The URL
checker rejected Safari's normal `client`, `rls`, `ie`, `oe` parameters and the query's
form-encoded spaces. That consumed the 12-second verification deadline. No video opened.

The prompt and native policy only permitted supplied URLs or captured links. A named
site without a literal address therefore had no direct navigation route. This was a
tool contract limitation in addition to the model's incorrect choice of Google search.

## Primary-source comparison, checked 2026-11-02

- [Browser Use action schema](https://github.com/browser-use/browser-use/blob/main/browser_use/tools/views.py):
  `NavigateAction(url, new_tab=False)` takes a destination directly; indexed clicks
  and text input refer to browser state. Navigation is distinct from selecting a link.
- [Playwright MCP](https://github.com/microsoft/playwright-mcp): `browser_navigate(url)`;
  click/type target a snapshot reference or unique selector. Typing can submit with
  Enter. This groups deterministic input work while keeping the selected control explicit.
- [OpenClaw browser agent tools](https://docs.openclaw.ai/tools/browser/agent-tools):
  explicit navigation/tab actions, a compact fresh snapshot returned after navigation,
  and current snapshot references for actions. A disappeared reference requires a
  fresh snapshot. The docs distinguish a committed usable page from a full load timeout.

These are tool/observation patterns, not evidence that any model has perfect task
accuracy. Their browser backends are not a drop-in replacement for controlling the
user's existing Safari window. Hush keeps its native AX adapter and permission identity.

## Change

- `navigate` (and the existing experimental `openPage`) accepts an HTTP(S) destination
  at target zero. No site whitelist, workflow script, model switch or framework is added.
- A nonzero element target must still resolve to its exact observed link. Scheme and
  credential checks, focus binding, Escape, verification and uncertain-action stops remain.
- Prompt distinguishes a known named-site homepage from invented result/video URLs,
  requests clarification for unknown addresses, and uses the current tab unless asked
  for a new one. Search-result selection still requires fresh observation.
- Google web-search verification compares the specific endpoint and exact single `q`
  after form decoding. Added browser metadata is accepted; wrong queries, duplicate `q`,
  lookalike hosts and unexpected endpoints are rejected. Arbitrary navigation URL
  equivalence is not weakened by stripping every query parameter.
- Existing combined-action experiment stays off. This patch does not promote a
  candidate that failed to improve accuracy on the fresh decision set.

## Validation

- Focused Debug checks: 10 successful executions (including two grammar parameters),
  zero failures, one optional tokenizer-profile skip. Model measurement completing
  successfully is distinct from all its predictions passing.
- [Six installed-Qwen decisions](benchmarks/2026-11-02-navigation-decisions.json):
  4/6 meet the predeclared strict expectations. Qwen navigates directly to YouTube,
  Apple and the supplied documentation URL; it asks for the unknown private dashboard.
  Wikipedia uses the legitimate `en.wikipedia.org` address rather than the fixture's
  expected root and incorrectly sets `more=true` for a one-step request. The observed
  result uses its exact supplied URL but returns target zero rather than the element ID.
  These are synthetic decisions with no thinking, not end-to-end browser accuracy.
  First measured decision includes model loading (6.75 seconds); later cases take
  3.63-3.73 seconds on the development M5.
- Required package tests: 27 passed. Swift-to-Hono integration: 1 passed using a
  temporary local service, stopped afterward. Full Release build passed; development
  recorder markers are absent from Release and present in Debug. Diff whitespace clean.
- Updated Debug app installed and opened. The first live rerun was blocked before any
  browser action because macOS returned `AXIsProcessTrusted=false` after the rebuild.
  A subsequent read-only probe from the installed app confirmed Accessibility true
  and a ready Safari document. The user is testing the fresh build. A completed Safari
  run is still required to qualify the full sequence; do not present permission
  readiness or the synthetic decision result as an end-to-end success.
