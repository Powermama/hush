# Safari hero entrance: senior developer brief

Updated: 2026-11-12. Status: unresolved on physical Safari; nothing deployed.
Follow-up to [PR #18](https://github.com/Powermama/hush/pull/18).

## Problem

The central 3D hero hitches on most reloads in Safari. Chrome remains smooth.
The user reports production was previously smoother than localhost; both now
show the hitch. The header also fades noticeably faster. Stack: Three.js
0.187.0 `WebGLRenderer`, Vite 8.2.4, React; no WebGPU or post-processing pipeline.

## Confirmed findings

- Archived lighting PR #6 (`45cd3a8` -> `e183937`, November 10) replaced runtime
  lighting convolution with a shared, approximately 310 KB precomputed texture.
  This reduces startup work but moves texture upload into the first hero draw.
- Public [PR #12](https://github.com/Powermama/hush/pull/12) decoupled content
  visibility from WebGL and accelerated the entire sequence: background
  2.4 -> 1.8 seconds; icon start 1 -> 0.35 seconds; download start
  1.65 -> 0.25 seconds. The header also became shorter and started at first paint.
- Original `hush-web` revision `4d3e456`, branch `feat/local-ai-landing`, retains
  the slower, scene-synchronized entrance. Its source is available locally.
- The user tested shader-only preparation and a subsequent hidden-frame GPU
  warmup on their Mac. **Neither removed the hitch.** Restoring the header's
  duration alone also left it starting too early. Linux WebKit measurements
  cannot establish the Mac regression's cause.

## Current direction

Keep precomputed lighting, responsive WebP artwork, hashed assets, on-demand
rendering and the pixel-ratio cap. The new coordinator restores the original
transition calendar without reverting to the old implementation: a prompt scene
starts the sequence; CSS independently reveals content within 1.2 seconds if
graphics or hydration are late. Background completion no longer ends the page
timeline during the three-second assembly. The ineffective GPU-fence experiment
has been removed. Physical Safari validation remains required.

## Recording findings

The user prefers the candidate's smoother overall pacing. Analysis covered all
1,694 recorded frames, with consecutive-frame visual inspection around the
hitches. Both versions still hold nearly the same 3D pose twice, then jump:
localhost at recording time 2.08-2.38 seconds; production at 9.43-9.73 seconds.
Each window spans about 0.29 seconds with one intermediate pose update. Opacity
continues changing. This is a motion pause/catch-up, not visible mesh corruption.

There are no capture timestamp gaps over 42 ms. Capture cadence is not rendered
frame rate; the recording cannot distinguish main-thread, GPU or presentation
stalls, or establish a RAM cause. The test container was stopped for this capture.
Private recordings and extracted frames remain outside Git.

The coordinator passes 27 focused browser checks. The local complete rerun was
stopped to free host resources; the deployment procedure requires the complete
GitHub browser suite to pass on the new commit before merge.
An online preview is useful for delivery/cache comparisons, but localhost already
serves a production build. Publishing cannot be assumed to remove this pause.

## Evidence needed to close

Compare the previous deployment, current production and candidate on the same
Mac/Safari version with cold loads and repeated reloads. Confirm the full entrance
still plays when ready promptly, without a hitch, and that slow connections keep
content usable. Capture a Safari timeline around the observed pause to separate
main-thread work from rendering/presentation delays. Do not mark
resolved until the user's original Safari symptom is gone.

## Relevant sources

- [Three.js renderer](https://threejs.org/docs/pages/WebGLRenderer.html): shader
  preparation and texture initialization address different first-use costs.
- [WebGL best practices](https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/WebGL_best_practices):
  non-blocking GPU completion polling; avoid synchronous GPU waits.
- [WebKit #233729](https://bugs.webkit.org/show_bug.cgi?id=233729): a similar
  Safari-only WebGL symptom, resolved in 2022; not proof of the same defect today.
- [Vite production builds](https://vite.dev/guide/build) and
  [asset handling](https://vite.dev/guide/assets): compare built artifacts and
  retain imported, hashed assets. Detailed investigation: [PRD](safari-hero-performance-prd.md).
