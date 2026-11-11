# Hush AI settings

## Contextual model controls revision

The landing page now contains only Personas and Assistant. No model catalogue and no separate System page. Each native card shows its real readiness, a clear action, and a restrained SF Symbol illustration. SF Pro, semantic canvas/ink colors and Hush violet remain the visual system. Use two equal columns with generous interior space, left-aligned text, native buttons and a quiet privacy footer. Readiness is text plus an icon, never color alone.

Personas restores an expandable Writing engine group. Its downloaded engines have Use and Remove controls; missing engines have Download with actual progress. Assistant owns its intelligence, listening and voice controls, alongside one guided setup and permissions. Shared files are still shared, with removal consequences explained before deleting. This keeps model management attached to its purpose rather than making people understand a global catalogue. Remove Hey Hush from the menu bar panel and reclaim its space.

Kokoro uses actual URLSession transfer counters for the current file, plus the SDK's pronunciation-download callback. Label file percentages explicitly; loading and voice warming are separate named stages, without invented progress.

### Native model controls refinement

Rollback checkpoint: `99d76a3`. Preserve SF Pro, semantic neutral surfaces and the existing layout. Replace disabled Active buttons with medium-weight green text, using darker green in light appearance and mint green in dark appearance. Use borderless accent-colored Download and Use actions. Put removal inside a standard macOS ellipsis menu with the existing confirmation sheet. This separates status from actions and keeps destructive controls secondary in both workflows. Remove Test voice from Assistant. No decorative badge, glow or continuous animation.

Validation: [all 7 native UI journeys passed](benchmarks/2026-11-03-native-model-controls-ui.json), including both model-removal menus and cancelled confirmation sheets. Reviewed the expanded Writing engine in light and dark appearance and the Assistant model rows. Debug and Release builds passed; the Release diagnostic-marker check passed. Installed and opened the refined Debug build, with matching executable SHA-256 `2b23f730fe90058cce3eb04007633dcaae133e32ee44f7ad92cb0ac37ca8c143`. Cleared superseded temporary test bundles after preserving their summaries and final screenshots.

### Contextual revision verification

- [19 domain tests passed](benchmarks/2026-11-03-contextual-ai-domain.json), including setup cancellation/resume, actual bundled-model availability, isolated voice-file removal, and progress reporting. The progress observer was tested against a real local HTTP transfer with intermediate byte percentages.
- [7 native UI journeys passed](benchmarks/2026-11-03-contextual-ai-ui.json): workflow navigation, expandable engines, style editing, light/dark appearance, compact sizing, setup cancellation/resume, removal confirmation cancellation, and explicit Kokoro file percentage. Reviewed the final AppKit screenshots.
- Setup-state and percentage screenshots use explicit Debug fixtures. Tests do not delete the user's installed models. First-time full Kokoro downloads and interrupted remote transfers were not exercised.
- HushProvenance: 27 package tests and one real Swift-to-Hono integration test passed. Temporary HTTP services were stopped.
- Final Debug and Release builds passed. Development recorder markers were confirmed absent from Release and present in Debug.
- Installed and opened `/Applications/hush.app` at Hush AI. Its executable SHA-256 matched the tested Debug build: `a9cd66470e1f90b55d464060d24869fc8d395125de83c216fef485d30922f4b7`.

## Superseded hub revision

After checkpoint `70a9e02`, the requested hierarchy is Workflow > Hush AI, with Personas and Assistant as drill-in pages and the model library on the hub itself. Preserve the native SF Pro typography, semantic colors and violet accent above. Two quiet navigation tiles introduce the workflows; a grouped model list owns download/remove controls and actual disk usage. This removes duplicate model-management surfaces. Assistant has one resumable setup action with visible progress, cancel/retry, and sequential native permission requests. The system permission switches remain controlled by the user. Native confirmation before removing shared files explains which workflows need setup afterward. Bundled app/system models are clearly distinguished from removable downloads.

One Workflow > Hush AI sidebar entry opens a hub for two independent experiences: Personas for dictation styles and Assistant (Beta) for the voice coworker. General Permissions covers dictation; screen access belongs to Assistant.

Design tokens: canvas #F5F5F7, ink #1D1D1F, secondary #6E6E73, Hush violet #796DE8, soft violet #A89DFF, ready green #43835A. Use semantic AppKit colors for canvas, ink, secondary text and status so dark mode and accessibility remain native. SF Pro sets titles (26 semibold), section headings (14 semibold), controls (13) and help (12). SF Symbols supply the cursor and writing icons.

Layout: left-aligned content in the existing macOS settings shell. Personas puts a compact enable row above a two-column style library, with the engine behind a disclosure. Assistant leads with its cursor and shortcut, followed by real model readiness and permissions. The cursor illustration is the expressive moment; controls remain quiet, standard AppKit components. No continuous animation or simulated model activity.

Brief review: replaced the old engine-first hierarchy and nested list cards with the user's primary choices. Keep the familiar Personas name; Hush AI is the umbrella, not another product name. Model downloads are explicit and reuse the existing stores. Do not equate a partially populated cache with a tested runtime, and do not claim a global offline guarantee for web browsing.

## Checkpoint verification (before contextual revision)

- Five native UI journeys passed: persona edit/add cancellation and engine disclosure, Assistant permission ownership and speech setup routing, light/dark appearance, minimum 880 x 600 window, and real Kokoro preparation using the installed local assets.
- Three readiness-domain tests passed. Missing intelligence or unverified voice cannot produce a Ready setup state.
- HushProvenance: 27 package tests and one Swift-to-Hono integration test passed. Temporary local service stopped.
- Debug and Release app builds passed. Final Debug build installed at /Applications/hush.app; running executable checksum matched the tested build.
- Reviewed actual AppKit screenshots. Sidebar scrolls at minimum size; persona edit controls stay reachable. Screen permissions are accessible on the Assistant page.
- UI result summary: [test evidence](benchmarks/2026-11-02-ai-settings-ui.json). First-time multi-GB downloads and network interruption recovery were not exercised; controls reuse the existing model download implementation.
