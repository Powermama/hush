# Desktop orchestration: lessons from OpenClaw and native Mac agents

Research date: 2026-11-01. Status: source review and implementation contract. This document does not claim that Hush now executes multi-step tasks, that an upstream SDK has been integrated, or that a new desktop benchmark has passed.

## Decision

Keep the installed local model stack as the experimental baseline while improving the execution system. The immediate gap is concrete: Hush's `submit` generates one `CoworkerReply`; `applyPending` executes it, records a text outcome, speaks, and schedules dismissal. It never observes the resulting page and requests the next action. Replacing Qwen cannot supply a missing execution loop.

Product decision after review: keep Hush's own open-source native implementation. OpenClaw, Peekaboo, AXorcist, and Cua are behavioral references, not dependencies. Use one bounded action loop around the existing generator, context capture, and native controls. No skill library, recipe store, or plugin framework is planned. This supersedes the initial proposal to qualify a Peekaboo backend.

Model quality still matters when selecting a control, interpreting a request, or deciding whether a result satisfies a goal. Holding the model fixed first lets us measure how much the surrounding system improves those tasks.

## What the repositories actually provide

| Project | Useful behavior or component | Fit for Hush and limits |
| --- | --- | --- |
| [OpenClaw](https://github.com/openclaw/openclaw) | Session-scoped runs; tool results become input to subsequent inference; cancellation and queued user input; loop detection | Reference for task lifecycle and tool-result feedback. Its Gateway and broad integration system are unnecessary dependencies for our native local app. |
| [Peekaboo](https://github.com/openclaw/Peekaboo) | Native Mac observation and actions; exact window targeting; opaque snapshot references; structured action outcomes; bounded agent runs | Native automation behavior reference only; no package adoption. |
| [AXorcist](https://github.com/openclaw/AXorcist) | Swift Accessibility wrappers, typed attributes, queries, actions, notifications | Reference for typed AX reads, actions, and notifications; no package adoption. It does not itself solve planning, task completion, or recovery. |
| [Cua Driver](https://github.com/trycua/cua/tree/main/libs/cua-driver) | Native control, explicit capture identity, background operation, a native SDK boundary | Control-contract reference only; the default driver and optional perception extension have different licenses. |
| [Agent S](https://github.com/simular-ai/Agent-S) | Agent-computer interfaces, task trajectories, reusable capabilities, held-out evaluation | Research reference for improving the tools around a model. Current S4 experiments use a 27B model and external benchmark infrastructure, outside Hush's device budget. |
| [OpenFelix](https://github.com/fspecii/openfelix) | Voice-first Mac assistant with skills and OpenClaw integration | Relevant product reference. Its README calls it an early prototype, requires a Python local engine, and recommends cloud backends for consistent quality. Not evidence of a qualified native 4B desktop controller. |
| [macOS-use](https://github.com/browser-use/macOS-use) | Earlier AX-based desktop-agent approach | Historical reference. GitHub marks it archived on September 25, 2026; its README still lists local-model support as unfinished. Avoid making it our maintained foundation. |

OpenClaw, Peekaboo, and AXorcist have inspected MIT license files; preserve their notices if incorporating code. Agent S has an inspected Apache-2.0 license. Cua's driver README identifies the default driver as MIT and the optional OmniParser detector as AGPL-3.0-only. The latter is a separate integration decision. No upstream implementation was copied or installed during this review. [OpenClaw license](https://github.com/openclaw/openclaw/blob/main/LICENSE), [Peekaboo license](https://github.com/openclaw/Peekaboo/blob/main/LICENSE), [AXorcist license](https://github.com/openclaw/AXorcist/blob/main/LICENSE), [Agent S license](https://github.com/simular-ai/Agent-S/blob/main/LICENSE), [Cua component boundary](https://github.com/trycua/cua/blob/main/libs/cua-driver/README.md).

## How the chaining works

This does not require a different model for every step. One model can be called repeatedly with a short task state, current evidence, and the currently available tools.

```text
Voice -> Parakeet -> goal + conversation
                       |
                       v
             Fresh app/window observation
                       |
                       v
            Qwen proposes one next action
                       |
                       v
             Validate -> native execution
                       |
                       v
              Verify -> record outcome
                       |
                 continue / finish
                       |
              Cursor state + brief voice
```

OpenClaw's core loop retains messages, executes tool calls, incorporates their outcomes, and checks cancellation before continuing. Its session controller serializes turns; steering and follow-up queues distinguish input that changes ongoing work from a later turn. These are lifecycle patterns, not a requirement to spawn multiple agents. For Hush, one desktop mutation lane is the simplest ownership rule. [Core loop](https://github.com/openclaw/openclaw/blob/main/packages/agent-core/src/agent-loop.ts), [lifecycle](https://github.com/openclaw/openclaw/blob/main/docs/concepts/agent-loop.md), [queue semantics](https://github.com/openclaw/openclaw/blob/main/docs/concepts/queue.md).

Peekaboo's inspected `runStreamingLoopBody` iterates up to `maxSteps`, checks cancellation, refreshes desktop context, requests model output, and passes tool calls to the executor. `executeToolCall` appends a typed tool result to the conversation. A `continueNextStep` boundary invalidates the cached desktop fingerprint. Step exhaustion remains failure. That is the specific continuation behavior missing from Hush today. [Streaming loop source](https://github.com/openclaw/Peekaboo/blob/653645cbddb596c8077940fce2506a32cb48f580/Core/PeekabooCore/Sources/PeekabooAgentRuntime/Agent/PeekabooAgentService%2BStreaming.swift), [execution source](https://github.com/openclaw/Peekaboo/blob/653645cbddb596c8077940fce2506a32cb48f580/Core/PeekabooCore/Sources/PeekabooAgentRuntime/Agent/PeekabooAgentService%2BExecution.swift).

## Behaviors to adopt

1. **A persistent task with fresh observations.** Preserve the original request, user corrections, completed subgoals, and verified outcomes. Re-read the UI after an action. Conversation continuity must not make an old element reference actionable.
2. **Typed, contextual capabilities.** Expose operations relevant to the current surface: opening a tab, navigating, filling an observed field, pressing an observed control, reading a document, or updating a bound document. The model supplies choices and content; native code supplies identity and execution semantics.
3. **Separate dispatch from success.** Return a typed receipt with action ID, target, dispatch state, postcondition evidence, and retry safety. A successful AX call, changed screenshot, or model sentence is insufficient proof of the user's goal.
4. **Inspect before recovery.** If input may already have happened, read the result before another mutation. An uncertain paste must never be replayed merely because the model asks again.
5. **One owner of desktop mutations.** A single cancellable run owns mutations. Spoken corrections stop further dispatch, settle any in-flight action, then re-observe within the same conversation. Escape cancels queued work as well as the active turn.
6. **Reusable native actions.** The same press, fill, navigate, and read operations serve different tasks. Each checks its target and result. The model chooses their order from fresh context; no stored task recipes are required.

Peekaboo's automation contract prefers observed element IDs, binds snapshots to their producer, and preserves uncertainty after possible dispatch. Its architecture separates automation, model providers, transport, and visual feedback. These are particularly useful standards for Hush. [Automation contract](https://github.com/openclaw/Peekaboo/blob/main/docs/automation.md), [package boundaries](https://github.com/openclaw/Peekaboo/blob/main/docs/ARCHITECTURE.md).

OpenClaw also detects repeated outcomes and alternating calls with no progress. Hush should detect lack of progress using semantic state and action identity, excluding volatile timestamps or generated IDs. A page with an animated thumbnail is not progress toward playing the requested video. Use a small fixed recovery budget instead of relying on a prompt that says not to loop. [Detector implementation](https://github.com/openclaw/openclaw/blob/main/src/agents/tool-loop-detection.ts).

## Reference-only package review

The inspected Peekaboo root `Package.swift` exports Foundation, Protocols, AutomationKit, and Bridge separately from its model runtime. It directly declares AXorcist and Apple's Algorithms package. This makes focused Swift integration plausible without importing the complete app, MCP server, or hosted model configuration. This was considered during research; the product decision above rejects this dependency. The package manifest's platform declaration and released app requirements differ; qualify our exact build rather than assuming a deployment floor. [Package manifest](https://github.com/openclaw/Peekaboo/blob/653645cbddb596c8077940fce2506a32cb48f580/Package.swift).

Do not import every behavior unchanged. Peekaboo's optional `ActionVerifier` can make a model-based screenshot check and defaults to a hosted model. Hush should use deterministic field, URL, selected-tab, and control-state reads wherever possible. A local visual judgment can supplement those reads but cannot upgrade an uncertain mutation to a verified one by confidence alone. [Verifier source](https://github.com/openclaw/Peekaboo/blob/653645cbddb596c8077940fce2506a32cb48f580/Core/PeekabooCore/Sources/PeekabooAgentRuntime/Agent/ActionVerifier.swift).

Cua's embedding guide distinguishes direct native runtime hosting from daemon-backed hosting and notes that its cursor overlay is unavailable in an arbitrary direct runtime without a suitable UI adapter. Embedding and TCC behavior must be tested with Hush's signed bundle; the guide is not a substitute for our permission checks. [Embedding contract](https://github.com/trycua/cua/blob/main/libs/cua-driver/rust/Skills/cua-driver/EMBEDDING.md).

## Safari is a separate backend concern

OpenClaw's browser tool controls Chromium-family profiles, including an explicitly attached Chrome session. Its browser model uses tab identity and fresh element references. Peekaboo's browser MCP integration is also Chrome-specific; native Mac tools cover Safari's application UI. Therefore a Chromium demo cannot qualify our user's existing Safari session. [OpenClaw browser](https://github.com/openclaw/openclaw/blob/main/docs/tools/browser.md), [browser action contract](https://github.com/openclaw/openclaw/blob/main/docs/tools/browser/agent-tools.md), [Peekaboo browser boundary](https://github.com/openclaw/Peekaboo/blob/main/docs/browser-mcp.md).

For Hush's Safari adapter, first qualify AX controls and native menus, explicit app/window/tab ownership, page URL reads, and field read-back. If a required page control is unavailable through AX, declare that capability unavailable and evaluate a permissioned Safari Web Extension separately. Do not silently replace Safari with Chromium or turn on debugging settings. Any future extension must use the same semantic capability/result contract.

The requested YouTube task supplies a concrete acceptance journey:

| Subgoal | Required evidence before continuing |
| --- | --- |
| Create a new Safari tab | Exactly one new owned tab in the intended Safari window |
| Navigate to youtube.com | That tab's observed destination is YouTube; needed page controls are ready |
| Search for David Guetta | Observed search field contains the query; results correspond to it |
| Open the first music video | Select from current observed results, preserving their order; distinguish ads and non-video surfaces |
| Report completion | The selected video's page/title is observed; claim playback only if playback state is actually verified |

Login, consent, region restrictions, ambiguous results, or missing controls may require one spoken question. Hush retains the goal and completed steps while waiting. Follow-up such as "the second one instead" refers to the observed result list, with freshness checked again. Ordinary browsing steps execute under the original request without preview/copy/execute buttons.

## Minimal Hush implementation

Extend three existing responsibilities instead of introducing a framework:

- **Observe:** `CoworkerContext` and `CoworkerScreenObserver` provide the current app, window, controls, text, and an on-demand still image.
- **Decide:** `CoworkerGenerating` accepts the original goal, conversation, fresh observation, and completed checkpoints. Model-specific loading and inference remain behind this protocol.
- **Act and check:** the controller continues one request; native controls validate the target, execute once, and return a structured verified or uncertain result. A small in-memory progress value retains checkpoints, action count, and the deadline.

The request/action/result format is shared across model adapters. Future compact models can be evaluated through the same native journeys without changing Mac controls. Input capabilities, context budget, exact artifact revision, quantization, runtime compatibility, and measured quality must be qualified per model. No model can label its own mutation as natively verified.

Start qualification with eight mutating steps, one recovery per blocked subgoal, and an overall monotonic deadline. Limits are tunable design defaults, not measured performance guarantees. Native-call timeout does not imply native-call cancellation: keep ownership until the call settles and block a new mutation meanwhile. Terminals distinguish completed, needs voice input, cancelled, uncertain effect, failed, and budget exhausted.

Keep the user's cursor-following companion, short action state, optional speech bubble, and automatic fade. Presentation consumes executor events. Model-generated narration must not announce success before the receipt. A follow-up hotkey pauses dispatch and opens voice input; it does not create another independent desktop worker. Developer traces remain opt-in Debug-only; production task state is bounded in memory, with no automatic transcript or screen recording.

## Evidence for improving the system around a fixed model

MacAgentBench reports the following Pass@1 values using Claude Opus 4.6: baseline 39.2%, Agent-S3 66.9%, and OpenClaw 73.7%. Crucially, the authors attribute OpenClaw's advantage mainly to its skill library. The benchmark contains 676 tasks across 25 apps, with almost 60% involving GUI and CLI interaction. This is evidence about that configuration, not a requirement for a Hush skill library or an accuracy prediction for local Qwen. Its VM/CLI setup is not our foreground Safari environment. [Reported comparison](https://github.com/JetAstra/MacAgentBench/blob/main/README.md), [paper and qualification](https://arxiv.org/abs/2606.22557).

Agent S4 reports 21.3% binary success on OSWorld V2 with evolved interfaces, 3.8 times its fixed-interface result using the same Qwen3.8-27B. ScienceBoard improves from 41.4% to 58.6%. This is further evidence that tool design matters; the model size, benchmark, and interface-generation setup differ substantially from Hush. Use development traces to improve reviewed adapters and validate on held-out tasks, rather than letting the production assistant rewrite its own execution code. [Research paper](https://arxiv.org/abs/2610.28601), [experiment implementation](https://github.com/simular-ai/Agent-S/blob/main/agent_s4/README.md).

Neither study establishes that models are irrelevant. Neither gives a measured small-model accuracy gain for Hush. No new local benchmark was run for this research note.

## Implementation and validation order

1. Reproduce the current single-step failure in a native journey fixture using the same controller entry point. Preserve the successful Mail follow-up regression suite.
2. Extend the controller with one bounded action loop, in-memory progress, and structured native results. Verify goal retention, fresh observations, no duplicate dispatch, cancellation during every phase, and honest completion using injected test doubles.
3. Extend Hush's existing Apple-native controls. Require target ownership, partial-effect reporting, and clipboard preservation; add no external automation package.
4. Add generic browser navigation, observed-field entry/submit, observed-link activation, and state checks. Run the actual Safari journey separately from mocked planner and fixture tests. Test changed focus, delayed navigation, multiple tabs, duplicate submissions, and missing AX controls.
5. Compare fixed Qwen4B weights across: current single-action baseline, action loop, and action loop with scoped capabilities and checkpoint verification. Hold prompts/tasks, sampling, time budgets, and hardware constant where applicable. Report completed goals, partial subgoals, unintended writes, false success, recovery, p50/p95 latency, model calls, and peak memory. Count skips and permission blocks separately.
6. Use held-out tasks across Mail, Notes/TextEdit, Safari, and native settings so a successful YouTube demo cannot masquerade as general desktop control. Confirm behavior on a 16 GB M2 and a newer 16 GB Mac before making hardware-wide claims.

Research source revisions recorded at review: Peekaboo `653645cbddb596c8077940fce2506a32cb48f580`; OpenClaw `2be13a6bdc761deaf59efceccb343852bbaee3c1`. Additional links to `main` describe the reviewed online state and should be pinned before code adoption. Temporary source downloads are removed after recording their hashes; installed models and the current Hush app are untouched.


## Implementation update: standard actions without workflow recipes

The Hush-owned loop now passes the original goal, fresh context and compact checkpoints through `CoworkerGenerating`, and accepts a native verified/unverified result. No third-party automation package, skill store, second planner model or persistent memory system was added. Browser operations share public AX and native event code. Available actions narrow the model's action enum for the current surface; native bindings and result checks remain authoritative. Per-step development artifacts retain each observation rather than overwriting it.

The cursor shows real stages and elapsed time, including initial action-control preparation. Verification is part of executing an action, not an extra user-requested action. The first revised prompt confused that distinction and regressed on unfamiliar tasks. Its failed A/B evidence is retained in `benchmarks/2026-11-01-sequence-contract-v1.json`; it must not be presented as a general quality improvement. The further termination-rule evaluation includes a new holdout split declared before observing its outputs.

### Is a second tool-calling model necessary?

Not established. IBM reports Granite 4.2 3B BFCL-v4 52.41 and tau3-bench 45.78; Qwen reports Qwen3.5-4B BFCL-v4 50.3. These are publisher results, not a controlled Hush comparison, not percentages of successful desktop workflows, and not evidence that a Q4 Granite router will improve this app. Greedy decoding does not make a learned router semantically deterministic. [IBM model card](https://huggingface.co/ibm-granite/granite-4.2-3b), [Qwen model card](https://huggingface.co/Qwen/Qwen3.5-4B).

IBM publishes an Apache-2.0 MLX Q4 conversion, but its documented runtime is Python `mlx-lm`. Hush's pinned Swift package contains a Granite implementation; that alone does not validate this checkpoint, tokenizer, tool format or native load path. No Granite weights were downloaded and no Granite performance was measured. Qualify it as a replaceable decision adapter first; add a second resident model only if paired held-out task completion and latency/memory measurements justify it. [Official MLX conversion](https://huggingface.co/ibm-granite/granite-4.2-3b-q4-mlx).

Keep the baseline voice stack: Parakeet Ultra via FluidAudio/CoreML and Kokoro via FluidAudio ANE. Qwen3.5-4B uses native MLXVLM for text and optional screenshots. The action loop does not need to know the model family. A model upgrade must earn promotion on the same task and interruption tests.
