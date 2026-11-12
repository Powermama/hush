# PRD: smooth 3D entrance across browsers, devices and networks

Status: implementation and automated validation complete for shader preparation,
cancellation, bounded resizing and modular scene construction. The reported live
Safari regression is not yet isolated to a single commit. Physical-device
performance gates, hosted checks and deployment remain outstanding.

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
| `aa22838`, before PR #12 | Scene import waited 150 ms; scene startup set `data-opening="playing"`; scene completion ended the page entrance. | Candidate earlier baseline, not a confirmed last-good live deployment. |
| `f893df7`, [PR #12](https://github.com/Powermama/hush/pull/12), `fix/landing-first-load` | Removed the import delay; CSS reveals the page independently; added `useLandingEntrance`; moved the fallback deadline to 1.2 seconds. | Primary scheduling hypothesis. Improved content readiness can overlap rendering work differently. |
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
| First paint | Preserve current headline/download reveal and the 1.2-second static-artwork deadline measured from CSS readiness. Failed/delayed JS or WebGL cannot hide content. |
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
  Publishing is blocked in the agent process by unavailable Keychain-backed
  credentials despite a successful interactive-terminal GitHub login.
