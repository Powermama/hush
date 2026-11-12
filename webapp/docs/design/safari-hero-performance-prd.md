# PRD: smooth 3D entrance across browsers, devices and networks

Status: resolved on physical Safari 26.3 (macOS 26.3, Apple M5) on November 12.
See [Root cause and resolution](#root-cause-and-resolution). Earlier
investigation notes below are retained as history.
See the [executive brief](safari-hero-executive-brief.md).

## Root cause and resolution

Sampling Safari's processes during a hitching reload showed the web content main
thread blocked in `WebGLRenderingContextBase::prepareForDisplay()`, waiting on a
synchronous reply from the GPU process. The GPU process was busy rendering CSS
and SVG filters on the CPU (`vBoxConvolve`, `vMatrixMultiply`,
`FEComponentTransferSoftwareApplier`). Those filters tinted the story artwork
just below the hero, which Safari paints ahead of the viewport. The page's own
JavaScript and WebGL calls were idle; Chrome rasterizes filters elsewhere and
was unaffected.

The same filters existed in the November 10 build. That build kept the page
hidden while lighting was generated at runtime, so filtered painting finished
before the entrance. Precomputed lighting and the removed import delay started
the 3D entrance earlier, into the filtered paint.

The fix bakes every colour treatment and the hero icons' shadow into WebP files
with `scripts/bake-artwork.mjs` and removes runtime filters (LANDING-PAINT-001).
Reloads in physical Safari through the production server:

| Build | Reloads | Stalls over 100 ms | Worst frame |
| --- | --- | --- | --- |
| `main` before the fix | 13 | 4 | 198 ms |
| Baked artwork | 18 | 0 | 56 ms |

Removing the story section or all filters on production bytes also removed the
stall (11 of 11 clean), while unchanged production stalled in 7 of 8
interleaved reloads. Pixel comparison against the filtered originals in Chromium
and WebKit at DPR 2 shows mean channel differences of 0.9-3.6 out of 255.

## Problem and outcome

The live `behu.sh` homepage's 3D hero entrance stutters severely in Safari while
Chrome remains smooth. The user remembers a smooth entrance before the recent
slow-network loading work. Restore that experience while keeping the improved
first-paint behaviour, the original model and materials, and usable navigation
on slow or failed connections.

Treat network readiness, main-thread work, GPU preparation and animation frame
delivery as separate budgets. A small download alone does not make an animation
smooth. Preserve the [visual landing contract](../user-journeys/visual-landing.md).

## Evidence and regression window

| Revision / PR | Relevant change | Assessment |
| --- | --- | --- |
| Archived PR #6, `45cd3a8` -> `e183937`, November 10, 21:13 -03:00; retained PR head `14e8185` | Replaced runtime RoomEnvironment/PMREM generation with a shared 310 KB prefiltered KTX2 download. | Earlier lighting hypothesis discovered in the archived history. Original branch name and deployed last-good SHA are not established. |
| `aa22838`, before PR #12 | Scene import waited 150 ms; scene startup set `data-opening="playing"`; scene completion ended the page entrance. | Candidate earlier baseline, not a confirmed last-good live deployment. |
| `f893df7`, [PR #12](https://github.com/Powermama/hush/pull/12), `fix/landing-first-load` | Removed the import delay; CSS reveals the page independently; added `useLandingEntrance`; moved the fallback deadline to 1.2 seconds; header fade shortened from 1.05 s plus 0.12 s delay to 0.75 s without delay. | Confirmed cause of faster header timing. Scheduling remains a hypothesis for the 3D hitch. |
| `f8a4172`, [PR #13](https://github.com/Powermama/hush/pull/13), `fix/security-dependencies` | Updated vulnerable dependencies and build tooling. | Test independently if scheduling is insufficient to explain the regression. Three.js stayed at `0.187.0`. |
| `cde5ae1`, [PR #14](https://github.com/Powermama/hush/pull/14), `fix/studio-texture-delivery` | Handles two observed gzip layers and versions the lighting URL. | Changed Safari's ability to load live 3D. This is not evidence that the user's earlier smooth animation was a fallback. |
| `5c516aa`, [PR #15](https://github.com/Powermama/hush/pull/15), `feat/versioned-public-images` | Moves public image references into Vite's hashed asset graph. | Changes delivery/cache behaviour, not hero geometry. |

Across `aa22838` and `e0782df`, the hero geometry, physical materials, environment
resolution, capped pixel ratio and three-second pose animation are unchanged.
`HushScene.ts` differs only in three removed page-entrance state assignments.
The pinned Three.js version is `0.187.0` in both revisions. The main changes are
in orchestration, CSS timing, delivery and dependency versions outside Three.js.

### Reproduction completed so far

- Built both source revisions using the same installed dependencies to isolate
  source changes. This is not a byte-for-byte rebuild of the historical lockfile.
- Ran each twice in disposable Chromium and WebKit containers, alternating
  before/current order, at 1440 x 900 CSS pixels and device scale factor 2.
- Recorded actual hero draw calls, WebGL initialization costs, readiness and
  frame intervals. Both versions loaded the real 3D scene and drew eight batches
  per animated frame.
- In that environment, median intervals between hero draws were 28-36 ms for
  current WebKit versus 56-917 ms for the earlier source. Chromium was about
  43 ms current versus 50-51 ms earlier. First-run effects were substantial.
  These results do **not** reproduce the reported direction of regression.
- A controlled shader-readiness experiment confirms that the current first
  render does not wait for non-blocking shader completion. That identifies an
  optimization opportunity, not the cause of the historical regression.

The container uses Linux WebKit, software rendering and amd64 emulation on an
Apple silicon host. Fresh browser profiles do not guarantee cold driver shader
caches. Its absolute timings are not Safari-on-Mac measurements. Native headless
browser launch failed before loading a page, so no native timing claim is made.
The user's existing browsers must not be controlled or inspected. Keep raw
captures, temporary profiles and local measurements outside Git.

### Lighting-history follow-up, November 12

Rebuilt the exact lighting parent `45cd3a8` and result `e183937` with their own
frozen lockfiles and the file set copied by their production Dockerfile. Two
alternating runs per browser exercised the real entrance in disposable WebKit
and Chromium at 1440 x 900, DPR 2. Both loaded actual 3D without page errors.
WebKit's first inter-draw interval was 517/558 ms before lighting precomputation,
679/668 ms after it and 515/536 ms with the published shader-preparation candidate.
Chromium improved substantially after precomputation. Absolute timings reflect
software rendering and emulation, not the user's GPU. This does not establish
that reverting lighting would restore physical Safari smoothness.

Instrumentation confirms the new lighting's 36 face/mip uploads happen during
the first hero draw. Their measured CPU call time is small; the large interval
after submission does not by itself identify a texture, shader or compositor
fault. A controlled experiment rendered while hidden and polled a GPU fence
with zero timeout before revealing or starting motion. Pending work was bounded
to eight seconds and canceled on route unmount or context loss. The user reported
no improvement, so that experiment is no longer in the implementation.
Late readiness retains the existing settled-scene behavior, so skipping the
entrance must not be presented as an animation performance improvement.

A retained November 10 live HTML capture references older client/CSS hashes,
but those assets now return 404. Neither rebuilt revision matches that complete
capture. Deployment records and a physical Safari comparison are still needed
to identify the exact last-good production version.

### Original website choreography

The original `hush-web` Git repository is also retained locally. Revision
`4d3e456` on `feat/local-ai-landing` (November 10) and `1be4bcc` (November 4)
share the same hero entrance code and CSS timings. The November 10 story and
mobile changes did not accelerate that sequence. Its header, background, icons
and downloads start when the scene switches the root from pending to playing.
The header takes 1.05 seconds after a 0.12-second delay, the introduction starts
at 0.55 seconds and lasts 0.9 seconds, icons start at 1 second plus stagger and
last 1.15 seconds, background texture takes 2.4 seconds, and the download starts
at 1.65 seconds and lasts 0.7 seconds. The scene completes the sequence at
3 seconds. PR #12 replaced those timings with an independent, shorter first-paint
sequence. Changing only the header duration cannot restore its original start.

The user reports the hidden-frame candidate at port 4326 still has the hitch and
suggests overlap with the background fade. Treat that candidate as a negative
physical test, despite passing deterministic browser checks. Compare the old
choreography and isolate the masked background's fade/scale before attributing
the regression to lighting or committing additional GPU workarounds as a fix.

### Physical Safari recording, November 12

The user supplied a 29.45-second screen recording containing repeated reloads
of localhost port 4326 and production. The local server uses the current Vite
production build, not Vite's development server. The isolated browser-test
container was stopped before recording to remove its CPU contention.

Analyzed all 1,694 native frames using timestamps and a silhouette-motion
heuristic, then visually inspected consecutive frames around representative
pauses. The heuristic locates candidates; the estimates below are visual motion
observations, not GPU measurements. Times are relative to the whole recording.

| Version | First nearly stationary pose | Second nearly stationary pose | Visible catch-up |
| --- | --- | --- | --- |
| Local candidate | 2.083-2.200 s, about 117 ms | 2.217-2.375 s, about 158 ms | 2.392 s |
| Production | 9.433-9.567 s, about 133 ms | 9.583-9.725 s, about 142 ms | 9.742 s |

Both windows span approximately 292 ms with a small intermediate pose update,
then a substantially larger step. Similar pairs recur across the local and
production reloads. Opacity changes during the pose holds; the image is not
entirely frozen. No obvious mesh corruption or lighting flash appears in these
frames. This supports a pause/catch-up diagnosis and does not establish that the
candidate removed or materially shortened the early hitch. The user nonetheless
prefers its slower, more coordinated overall choreography.

The median capture interval is 16.667 ms and the maximum is 41.667 ms, with no
capture gap above 50 ms. These are recording timestamps, not application FPS.
Composited fades can continue while JavaScript is stalled, so continuing opacity
does not identify the blocked stage. Main-thread, GPU and canvas-presentation
causes remain open; RAM pressure cannot be diagnosed from this recording. Several
reloads interrupt the entrance, so reload transitions and settled poses are
excluded from hitch estimates. Raw video and frame strips stay outside Git.

Publishing a preview can test network/cache ordering and the actual delivered
assets. It will not add a production build optimization missing from localhost.
Next attribution requires a Safari timeline around the visible pause and a
controlled single-factor comparison, not another unmeasured warmup workaround.

### Related upstream reports

- [WebKit #233729](https://bugs.webkit.org/show_bug.cgi?id=233729) reports a
  WebGL cube smooth in Chrome/Firefox but jerky in Safari. It was resolved in
  2022, so it supports the symptom category, not current causal attribution.
- A [Three.js Safari discussion](https://discourse.threejs.org/t/issue-with-orbitcontrols-on-safari/28317)
  reports stutter on particular Apple devices while another maintainer could
  not reproduce it. Device, OS and Safari version matter; hush uses no OrbitControls.
- A [first-hand startup investigation](https://discourse.threejs.org/t/why-a-heavy-three-js-scene-tanks-pagespeed-and-it-is-not-your-javascript/94734)
  describes real-draw warmup and non-blocking fences after shader preparation.
  Its post-processing/software-rendering workload differs from hush and its
  reported gains are not transferred to this project.
- Current WebGPU/PassNode compilation reports are not matches for hush's
  `WebGLRenderer` and must not motivate an unrelated renderer migration.

Three.js explicitly documents `initTexture()` for moving decode/upload costs
before first use. A complete warmup draw also exercises geometry, material setup
and the final drawing buffer. The zero-timeout fence polling follows the pattern
in [MDN's WebGL best practices](https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/WebGL_best_practices),
without `gl.finish()`. Official [Vite llms.txt](https://vite.dev/llms.txt),
[production-build](https://vite.dev/guide/build) and
[asset](https://vite.dev/guide/assets) guidance were checked; Vite's development
server is not a production performance baseline.

### Live deployment reference

Observed on 2026-11-12 UTC: client `index-es3IzbZU.js`, stylesheet
`index-CI3RzlD3.css`, hydration `route-0c26bff4f48d0887.js` and hero
`HushScene-B8wk0zOm.js`. The downloaded hero is byte-for-byte identical to the
baseline build: SHA-256
`30f287c36fab0e3fa14243178f1730dd1754bda0d743509675fbf9b2954a3621`.
This identifies the hero module, not the complete deployed build or an exact
last-good deployment time.

### Required next attribution checks

1. Identify the deployed client/CSS/scene asset hashes and compare them with the
   local builds. Confirm current deployment and previous deployment times.
2. Compare PR #12's parent and result with matching lockfiles on the same actual
   Safari/macOS/device configuration. Repeat with source-only changes and fixed
   dependencies to separate tooling from application behaviour.
3. Change one factor at a time: import scheduling, CSS/3D overlap, shader
   preparation, field rendering and production lighting response encoding.
4. Test cold HTTP cache and warm reload separately. Record shader-cache uncertainty,
   power mode, display refresh rate, viewport and drawing-buffer size.
5. Name a causal PR only when reverting its change removes the symptom and
   reapplying it restores the symptom under the same conditions.

## Research-backed approach

### Prepare graphics before playback

Configure final lights, environment and material features, then evaluate
`WebGLRenderer.compileAsync(scene, camera)` before starting the visible motion.
Three.js recommends it to avoid unnecessary shader compilation stalls.
Feature-detect the parallel-compile extension; its absence is not a failure and
the promise alone does not guarantee a stall-free first draw. Measure texture
uploads, buffer uploads and the first draw separately.
[Three.js renderer documentation](https://threejs.org/docs/pages/WebGLRenderer.html).

Khronos specifies a non-blocking completion query, not faster overall shader
compilation or guaranteed frame delivery. Avoid synchronous status/log reads
while compilation is still pending. Do not use `gl.finish()` as a warmup fix.
[KHR_parallel_shader_compile specification](https://registry.khronos.org/webgl/extensions/KHR_parallel_shader_compile/).

Start the motion clock on the first prepared frame. Preserve elapsed-time
movement, finite completion and input interruption. Abort preparation and release
resources if navigation, context loss or disposal occurs. Break up expensive
JavaScript preparation when measurements show long tasks; a promise microtask
alone does not yield a rendering opportunity.
[Long-task guidance](https://web.dev/articles/optimize-long-tasks).

### Bound rendering cost without changing the design blindly

Keep on-demand rendering and one pending animation frame per scene. Stop once
the entrance and pointer settling finish, and suspend offscreen/hidden work.
[Three.js on-demand rendering](https://threejs.org/manual/pages/rendering-on-demand.html).

Keep CSS dimensions independent of the drawing buffer. Retain the existing
1.5 pixel-ratio cap; do not multiply physical pixel dimensions by DPR twice.
Resize only when dimensions change. If sustained frame cost remains high,
evaluate a bounded resolution tier using measured frame intervals, with
hysteresis to prevent repeated reallocations. Do not classify GPU speed from
browser name or network speed.
[Three.js responsive rendering](https://threejs.org/manual/pages/responsive.html).

Physical material features have a per-pixel cost. Profile clearcoat, transparency
and shader variants before simplifying them. Keep any visually changed material
out of the initial scheduling fix. Do not introduce extra lights, shadow maps,
post-processing, runtime PMREM generation or a new 3D framework for this task.
[Three.js physical materials](https://threejs.org/docs/pages/MeshPhysicalMaterial.html).

Dispose geometries, materials, environment textures, renderer state, observers,
listeners and outstanding callbacks exactly once. Test navigation during every
asynchronous preparation stage.
[Three.js cleanup](https://threejs.org/manual/pages/cleanup.html).

### Optimize transfer and decode separately

Story artwork is already WebP. Mobile variants are approximately 25-91 KB;
larger variants reach approximately 421 KB. App icons are PNGs around 7-12 KB.
The hero is procedural geometry, not a downloaded raster image. The rose GLB
is separate and should remain deferred until near the viewport.

The studio environment is about 310 KB over the wire and contains half-float
faces and mip levels. A `.ktx2.gz` filename does not imply GPU block compression.
Image compression reduces transfer bytes; decoded texture dimensions and format
determine GPU memory. Do not replace the HDR lighting with WebP.
[Three.js texture guidance](https://threejs.org/manual/pages/textures.html).

Keep responsive image candidates, intrinsic dimensions and lazy loading for
below-the-fold story artwork. Avoid lazy loading the initial visible imagery;
do not preload every scene or image. Treat optional connection/save-data hints
as hints, with an equally usable path when Safari exposes none.
[Browser image-loading guidance](https://web.dev/articles/browser-level-image-lazy-loading).

## Vite-aligned modular structure

Read [Vite's official llms.txt](https://vite.dev/llms.txt), then its linked guides.
Vite does not mandate an application folder architecture. The following
boundaries are a hush design decision informed by its guidance.

```text
src/landing/
  Landing.tsx                  page composition
  LocalUniverse.tsx            semantic hero, static fallback, lazy scene mount
  useLandingEntrance.ts        finite HTML/CSS entrance
  entrance/
    landingEntrance.ts         one-shot readiness and CSS fallback clock
  HushScene.ts                preparation and DOM/visibility lifecycle
  hero/
    createHeroScene.ts         geometry, materials, lights, resource ownership
  StudioEnvironment.ts         shared download/validation, owned GPU textures
scripts/
  prerender.ts                 build orchestration
  prerender/
    externalize-scripts.ts    HTML parsing and hydration-script extraction
```

Extract by responsibility as behaviour changes. Avoid generic scene managers,
repository-wide file moves, arbitrary file-length rules, circular dependencies,
and a shared module that imports every scene. Use direct feature imports rather
than broad barrel files. Keep `vite.config.ts` declarative and small.
[Vite performance guidance](https://vite.dev/guide/performance).

Retain dynamic imports for optional scenes and Vite's async dependency preloads.
Do not eagerly import Three.js through a shared UI export. Inspect built imports
and transfer sizes; do not add manual chunks solely to make source folders
look smaller. Source modularity and bundle splitting are different concerns.
[Vite build optimizations](https://vite.dev/guide/features#build-optimizations).

Keep artwork imports in the asset graph for content hashes; use `public/` for
resources needing stable names. Preserve separate client/SSR entry points and
keep DOM/WebGL operations out of SSR module evaluation.
[Vite assets](https://vite.dev/guide/assets),
[Vite SSR source structure](https://vite.dev/guide/ssr#source-structure).

## CodeQL finding: separate correction

Reported finding: `js/bad-tag-filter`, high security severity, at
`scripts/prerender.ts:30`. A case-insensitive flag alone does not cover HTML
parser recovery, including malformed closing tags. Use a maintained HTML parser
and a focused extraction module; keep CSP `script-src 'self'` intact.
[CodeQL recommendation](https://codeql.github.com/codeql-query-help/javascript/js-bad-tag-filter/).

The input here is trusted build-time SSR output. This transform is not an HTML
sanitizer and must never be offered as one. Preserve script order, JSON-LD,
external/module script attributes, exact hydration data and escaped NUL values.
Test browser behaviour for mixed case, whitespace, malformed closing tags,
comments, inert template content and duplicate script bodies. Verify the new
CodeQL analysis before saying the hosted alert is closed.

The follow-up `js/bad-code-sanitization` finding in the browser fixture is
addressed by storing fixture HTML as data and reading it from a fixed SSR module.
Do not interpolate `JSON.stringify(document)` into executable JavaScript.
[CodeQL code-construction guidance](https://codeql.github.com/codeql-query-help/javascript/js-bad-code-sanitization/).

## Acceptance criteria

These are proposed release gates, not achieved measurements.

| Area | Gate |
| --- | --- |
| Regression attribution | Record deployed hash, tested revisions, device/browser versions, traces and reversible isolation result. Otherwise label cause unconfirmed. |
| Hero appearance | Same silhouette, glass layers, silver/graphite materials, framing and three-second assembly. Compare start/mid/end frames. |
| Desktop motion | On the affected Mac at a fixed 60 Hz reference rate: target p95 frame interval <=20 ms, p99 <=34 ms, and no entrance freeze over 100 ms. Report cold and warm runs independently. |
| Mobile/lower-capacity GPU | Target stable 30 fps or better under the chosen quality tier; preserve legibility and design. No false claim that emulation represents physical device performance. |
| Entrance and fallback | Preserve the user's original transition calendar for a promptly prepared scene. If graphics or hydration are late, CSS reveals the complete composition within 1.2 seconds. Failed JS or WebGL cannot leave content hidden. |
| Interaction | Wheel, pointer, keyboard and touch finish the entrance promptly; no scroll lock, replay or delayed model mount after leaving the page. |
| Idle | Zero hero draw calls across a five-second idle observation after settling; no draws while hidden/offscreen. |
| Compatibility | Parallel compile present/absent, WebGL unavailable/lost, reduced motion, slow lighting, malformed/excessive gzip and rapid navigation all remain usable. |
| Network | Test cold/warm HTTP caches at unthrottled, 1.6 Mbps/150 ms RTT and 400 Kbps/400 ms RTT; separately block the scene, lighting and application JS. |
| Privacy | Disposable test profiles only; no access to the user's browser sessions, no production telemetry added for this investigation. |

Use WebKit's Frames and Layout & Rendering views to distinguish JavaScript,
paint/compositing and GPU-related stalls. Instrumented rAF intervals alone do
not prove which stage caused a missed frame. Enable only needed profiling
timelines, then repeat uninstrumented runs.
[WebKit profiling](https://webkit.org/web-inspector/timelines-tab/).

## Implementation and rollout

1. Finish deployment matching and regression isolation. Preserve a baseline report.
2. Prepare a focused hero PR: resource ownership, asynchronous preparation,
   motion-start timing, cancellation, and only measured rendering improvements.
3. Keep the CodeQL parser fix in its existing separate PR. Keep structural changes
   tied to the responsibility being fixed, not a whole-application rewrite.
4. Update `visual-landing.md` and browser tests with new observable guarantees.
   Add deterministic lifecycle/readiness coverage and keep variable hardware
   timing measurements outside brittle shared-runner pass/fail assertions.
5. Run `bun run lint`, `bun test server`, `bun run api:check`, `bun run build`,
   and the browser journeys. Add focused build-transform tests for prerendering.
6. Compare baseline/fix with alternating order and at least five cold and five warm
   runs on physical Safari and Chrome, then iPhone/iPad Safari and Android Chrome.
   A physical-device check uses a dedicated test profile/device, never the user's
   open browser without a new explicit instruction.
7. Review the PR and deployment checks. Verify delivered hashes and the actual
   live entrance after deployment; retain rollback to the previous build. Do not
   claim resolution from a passing build or Linux WebKit alone.

### Execution record

- Current follow-up: the scene and page share the original transition calendar;
  a CSS fallback reveals content within 1.2 seconds if preparation is late. No
  legacy loading delay, runtime lighting convolution or GPU-fence workaround is
  reintroduced. Type checking, API drift, build and 27 focused browser checks pass.
- The user confirms the longer sequence and prefers its overall pacing. The
  recording still shows a comparable early pose pause/catch-up in both local
  and production versions. The test container was stopped for that recording.
  The resumed local full-suite run was stopped again to free host resources for
  the user's requested live comparison. Deployment must wait for the complete
  GitHub browser suite on the new commit. Do not infer RAM exhaustion from swap
  use or attribute the pause to the GPU without a trace.
- The rejected warmup candidate passed 42 focused checks. Its full run reached
  214 passes and one skip before the emulation time limit; the remaining WebKit
  journey passed separately. These results do not validate the new coordinator's
  full suite and did not establish physical Safari smoothness.

- Hero branch: `fix/safari-scroll-performance`. Final shaders compile before
  playback; aborting preparation disposes materials, geometry, textures and the
  renderer. The motion clock starts on its first prepared frame. Unchanged sizes
  no longer reallocate the drawing buffer. Scene construction is extracted without
  changing its original geometry, materials, lights or camera parameters.
- CodeQL branch: `fix/prerender-script-case`, existing PR #17. Uses parse5 8.1.1
  only at build time. The test fixture reads HTML data through a fixed module.
  Neither finding is suppressed; hosted analysis must confirm their resolution.
- Both branches pass type checking, OpenAPI drift checks and production builds.
  Hero branch: 20 backend tests. Parser branch: 23 backend/parser tests.
- Full hero-branch browser suite: 197 passed, one existing mobile-hover skip.
  After the final resize guard, all 27 focused entrance/hero tests passed.
  The parser regression passed all three browser projects after the fixture fix.
- Browser checks used pinned Playwright 1.62.1 and its matching Chromium and
  WebKit engines in a disposable Linux container. Final settled desktop/mobile
  screenshots were inspected. Five-second idle checks observed zero additional
  hero draw calls; hidden-state coverage uses an injected visibility event.
- No physical Safari performance gate or exact bandwidth/RTT matrix is marked
  complete. Earlier/current emulation results remain inconclusive for attribution.
  Implementation is published in PR #18; parser and fixture corrections are
  published in PR #17. Neither PR has been deployed by this investigation.
