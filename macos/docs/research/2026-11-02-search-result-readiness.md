# Search result readiness and continuation

## End-user trace and live reproduction

User turn `65A0AA5E-7CD9-4CB7-8FDA-1A20CB52C8AE` requested opening YouTube,
searching for Martin Garrix, and opening the first music video. Permissions were
granted. Qwen3.5-4B, with thinking disabled, navigated correctly and filled the
page search field. It then chose `press` on the observed Search button with
`more=false`. The generic button path dispatched AXPress but had no search
postcondition and returned unverified almost immediately. No result was selected.

The developer repeated the same transcript through the installed app and actual
Safari controls, turn `12AC2E9A-C7AA-4789-A618-331952F1014F`. That run took 29.93s
and also stopped without opening a video. This time Qwen chose `submitSearch`
correctly, but the verifier accepted the new results URL while Accessibility still
exposed the old homepage recommendations. The following model request contained
the results URL and old home content. Qwen then pressed Search again.

This is both an executor readiness bug and a model continuation/selection failure.
The user instruction and transcription were clear. Replacing the model alone
would not correct stale page observations or missing button verification.

## Changes

- Browser verification samples bounded semantic content from the main landmark,
  falling back to document links when no main landmark is exposed. Navigation,
  banners, search inputs and suggestion subtrees do not count as result changes.
- A changed URL requires changed, nonempty content that remains stable for 350ms.
  The existing document/loading checks and 12-second bound remain. This is a
  native readiness heuristic, not proof that every possible web app is ready.
- A captured Search button with one unambiguous populated page search field uses
  the same query/origin postcondition as Return. It sends one event and never
  retries an uncertain press. Other button presses do not gain generic success
  merely because something changed on screen.
- Shared site-search verification decodes form queries correctly, preserves
  literal plus signs, rejects origin changes/ambiguous duplicate query keys and
  requires a destination transition. No YouTube-specific route is constructed.
- The prompt prefers `submitSearch` and explicitly distinguishes submitting a
  search from opening a requested result. It retains the entire original goal
  when choosing continuation and must not repeat a completed search.
- Debug browser probes now record the final page URL, window title and exposed
  Pause buttons. A `/watch` page alone is not proof that audio playback started.

## Follow-up live failure and reference contract

After restoring Accessibility, live run `4FB6A5D5-D8FF-47F3-B42B-A8598BB986B0`
verified search results with fresh content and selected the correct first official
music video: "In The Name Of Love", element 26. It stopped at 33.09 seconds because
Qwen copied the correct video URL without its `pp` tracking parameter, while the
executor required both the ID and the duplicate URL to agree exactly.

The general fix makes the element reference authoritative. `navigate(target:26)`
resolves the complete captured HTTP(S) URL locally; content may be empty. Redundant
model-authored content is ignored, never executed. Unknown IDs and unsafe captured
schemes/credentials still fail. Target zero remains direct address navigation.
This is the same distinction as indexed browser actions: a reference selects an
observed resource, while a URL specifies a direct destination. It does not need a
tracking-parameter allowlist, artist name, website rule or extra model call.

Generic regression tests cover query parameters, fragments, mismatched redundant
content, missing IDs and non-web links. An additional native model replay uses the
actual failed result-selection input, independently of the synthetic fixture.

The final reference-resolution build passed 13 native test executions (zero failures,
one optional tokenizer-profile skip). All [four model regressions](benchmarks/2026-11-02-search-decisions-reference-final.json)
passed, including the exact recorded result input selecting element 26 with `more=false`.
The experimental reference-only prompt regressed search-field selection and was
rejected; its output is retained in `search-decisions-reference-prompt.json`. The
previously passing instructions remain, while native execution no longer depends
on the duplicate URL. Release build and diagnostic-exclusion checks passed again.

The final app is installed and open. Its first live invocation was blocked by the
new development signature's Accessibility permission; the user is preparing to test
after restoring permission. The complete workflow on this final build still requires
live confirmation. Earlier live runs must not be relabeled as successes.

### User confirmation

After the final installed-app probe confirmed Accessibility and a ready Safari
document, the user repeated the full Martin Garrix request and reported "works".
This is user-confirmed success for that live sequence on the final build. It is
separate from the recorded automated failures above and does not establish an
overall accuracy rate or qualification across other websites.

## Validation

- Native checks passed: 12 successful executions, zero failures, one optional
  tokenizer-profile skip. Pure tests cover old-content/new-URL rejection,
  settling/reset behavior, query decoding and search postconditions.
- [Final installed-Qwen regression](benchmarks/2026-11-02-search-decisions-final.json):
  all three cases pass the executor contract. The recorded failed request now returns
  `submitSearch(target:3, more:true)`. The synthetic fresh result returns its exact
  URL with `more:false`; a search-only request returns `submitSearch(more:false)`.
  This is a regression test, not an overall task-accuracy estimate.
- Intermediate model results are retained as `search-decisions-v1`, `v2`, `v3`.
  V1/V2 revealed continuation and link-selection errors. The synthetic result fixture
  initially used an unrelated example.org origin despite the goal naming YouTube;
  it was corrected before V2. V3 chose the correct URL but the test demanded a copied
  element ID. Because the existing direct-navigation contract explicitly allows
  target zero, the final assertion resolves the URL using the actual native policy.
  Original outputs are retained; no model result was silently rewritten.
- Tool-field descriptions now define target IDs, intended-action wording and
  continuation at the schema boundary as well as in prose. No thinking or extra
  model is enabled.
- Required package checks: 27 passed. Required Swift-to-Hono check: 1 passed. The
  temporary local service was stopped after testing. Full Release build passed;
  the binary check confirms development diagnostics are excluded from Release.
- The updated Debug app is installed and open. Its first live rerun stopped before
  acting because the rebuilt app's macOS Accessibility access was false. The user
  must restore it before the live replay can complete. No raw private trace content
  is committed, and the full video workflow is not yet claimed as verified.
