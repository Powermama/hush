# Browser and native Mac control

Research date: 2026-11-01. Recommendation: use semantic browser DOM/tab APIs when a Hush extension is installed, public macOS Accessibility for native apps and extension-free browser control, and grounded visual input only for surfaces those APIs cannot describe. This is a proposed browser adapter, not an implemented extension.

## Supported browser paths

| Browser | Supported DOM and tab access | Hush integration |
| --- | --- | --- |
| Safari | Safari Web Extension content scripts read and change page DOM; extension APIs manage tabs. Safari also supports `do JavaScript` Apple Events when its developer setting is enabled. | Prefer a packaged Safari extension with a Swift native extension and app-group/native messaging bridge. Apple Events are an optional development route, not a portable default. |
| Chrome | Content scripts and `scripting.executeScript`; `tabs.create/update/query`; native messaging via a registered host. | Share a bounded DOM observer/action implementation with Safari and Firefox, with a small browser-specific packaging/transport layer. |
| Firefox | WebExtensions content scripts, tabs API and native messaging. | Same DOM/action schema; account for manifest and native-host differences instead of assuming all extension APIs are identical. |

Official sources: [Safari native messaging](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension), [Safari extension permissions](https://developer.apple.com/documentation/safariservices/managing-safari-web-extension-permissions), [Safari developer settings including JavaScript from Apple Events](https://developer.apple.com/documentation/safari-developer-tools/developer-settings), [Chrome content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts), [Chrome tabs](https://developer.chrome.com/docs/extensions/reference/api/tabs), [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [Firefox content scripts](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Content_scripts), [Firefox tabs](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/tabs/create), [Firefox native messaging](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging).

The local Safari scripting dictionary confirms `do JavaScript` on a specific tab. The installed Chrome scripting dictionary confirms `execute javascript` on a tab. Neither command was executed or enabled during this research. Apple Events are macOS inter-application commands; DOM events such as `input`, `change` and `click` are webpage events. They are different mechanisms.

Safari WebDriver uses isolated automation windows rather than attaching to normal personal browsing windows. That makes it useful for test infrastructure, but a poor default for a coworker operating the user's existing tab. [WebKit's automation model](https://webkit.org/blog/6900/webdriver-support-in-safari-10/).

## Efficiency and reliability

- DOM can supply exact tab/frame/document identity, control role/name/value, links, visibility and form state in one bounded snapshot. This generally offers better targeting for HTML controls than coordinate inference. This is an engineering expectation, not a measured cross-browser latency result.
- AX supplies semantic controls across applications without installing a browser extension. It can be fast, but coverage and traversal quality matter. In the actual YouTube tree, a breadth-first walk reached the search field at node 453; a depth-first walk reached it at node 16. Hush's previous 220-node budget missed it despite Safari exposing it.
- Screenshot capture itself was only tens of milliseconds in the observed Hush traces. Image/prompt inference consumed roughly 6-8 seconds; generation then took roughly 1-1.4 seconds. These are individual M5 development traces, not controlled M2-M5 benchmarks.
- Vision remains necessary for canvas, diagrams, images and custom-drawn surfaces. Coordinates must be bound to the captured window, scale and current frame. A visual click requires fresh evidence; a stale screenshot cannot certify its target.

DOM scripting is not universally equivalent to physical input. Script-dispatched events and `HTMLElement.click()` are untrusted events, and some controls require user activation or native input. Verify the effect; do not equate an accepted JavaScript call with success. Cross-origin frames, closed shadow roots, rich editors and restricted browser pages require explicit handling. [Event semantics](https://developer.mozilla.org/en-US/docs/Web/API/Event/isTrusted).

For voice invocation, `activeTab` must not be assumed to become available merely because the containing Mac app heard a command. Browser permission requires a recognized extension gesture or granted host access. Request appropriate site access and explain it in setup rather than silently expanding permissions.

## Other Mac applications

Use `AXUIElementCopyActionNames` to discover a control's supported actions, `AXUIElementPerformAction` with `AXPress` where exposed, and supported focus/value/selection attributes for editing. Bind the operation to process, window, control identity and the current observation. Use `CGEvent` keyboard or mouse input when semantic execution is unavailable and a target is grounded. Supported application scripting dictionaries can offer richer operations, but they vary by application. [Apple Accessibility action API](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction), [Core Graphics events](https://developer.apple.com/documentation/coregraphics/cgevent).

Hush currently implements only explicit user-pointed coordinate clicks; arbitrary model-grounded pixel clicking is not qualified. Telegram draft insertion works in the user's observed test, while sending and recipient binding remain unimplemented. No real message was sent by these development tools.

## Keep the model contract small

The model selects an observed target and a typed operation. Native code chooses the DOM, AX or event adapter, checks scope and executes. Do not ask the model to generate arbitrary executable JavaScript, selectors invented from memory, or application-specific scripts. The browser observer supplies bounded node references keyed to a tab, frame and document revision; stale references expire after navigation.

Reuse the existing observe, decide, execute and verify responsibilities. Add a browser adapter only after an extension prototype demonstrates better success and latency against the same tasks. A separate planner, skills catalog or per-website recipe library is not required. Sending is a distinct capability: explicit user intent, known conversation/recipient, exact content and a verified outcome are required. Draft requests do not implicitly authorize sending.

Validation should compare the same browser tasks through AX and DOM: tab creation, search, result navigation, form editing, reactive inputs, duplicate labels, page reflow, navigation during a decision, and cancellation. Report completion rate, incorrect actions, interventions, cold/warm latency and memory independently. Do not replace this with tokens-per-second or dictation benchmarks.
# Live transition evidence

The 2026-11-01 installed-agent test `7AA5EDD6-13F2-4DB4-91A9-8D81B0723CC9` prepared its first action in 1.2167 seconds after removing character-count grammar expansion. New Tab and navigation were verified, but the next context still contained Safari's Start Page while YouTube was loading. The model chose a browser search and the run stopped on an unverified destination. Total run: 25.71 seconds. This is a failed complete task, not a YouTube pass.

The subsequent native-controls-only run opened a tab and navigated successfully, then reported an unverified field write after 15 ms. The executor had checked the remote AX value immediately after dispatch. The fix adds bounded read-back without repeating the mutation and requires a single populated, loaded document before continuing navigation. WebKit exposes `AXLoaded` and `AXLoadingProgress` on its web areas; see its [accessibility wrapper source](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/accessibility/mac/WebAccessibilityObjectWrapperMac.mm). These browser-provided attributes are queried through AX; their availability must still be checked at runtime. Fresh live qualification is required after the change.

The next native run verified navigation after 3.313 seconds and correctly exposed YouTube's `Suchen` control as `AXComboBox` / `AXSearchField`. Waiting for read-back was insufficient: the setter still left its value empty after 1.078 seconds. Consequently web fields now use the existing guarded native paste transaction as their primary transport, not a fallback retry. The observed context also spent most of its 48-control budget on sidebar links, motivating deferral of semantic navigation landmarks until after main content. Neither change has a passing end-to-end claim without a new live result.

## Latest live results

The native-controls test with the paste transport verified New Tab (0.162 s), navigation to the loaded YouTube page (2.356 s), filling YouTube's own search field (0.099 s), and submitting that search (0.145 s). The final observed-link navigation failed `invalidLink`. The helper re-reads context between selecting a result and dispatching its ID, so target-ID stability in the helper remains a confound. This run does not establish that the model chooses a music video. [Native report](benchmarks/2026-11-01-youtube-native-controls.json).

The subsequent actual-model/controller run `59238C4A-ACDF-40F0-8864-52966F8B5E35` prepared its first grammar in 1.260 s. It correctly opened a new tab, then incorrectly chose global Google `search` instead of navigating to the user-specified YouTube URL. The global search destination was unverified and the loop stopped. Duration: 28.63 s. Full-task result: **failed**. The distinct remaining issues are semantic action selection and qualification of final result activation. No YouTube-specific recipe or larger model was added to hide this failure. [Agent report](benchmarks/2026-11-01-youtube-agent-run.json).

Both runs used the installed app and real Safari. The native check specifies actions itself; the agent check uses Qwen and the real controller with a fixed transcript, but bypasses microphone recognition and mutes speech. These are explicitly different evidence levels. The updated Release build passed, and the diagnostic-marker check confirmed that the development recorder remains excluded from Release.

