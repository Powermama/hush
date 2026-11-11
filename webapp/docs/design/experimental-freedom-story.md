# A voice of your own

## Direction, 9 November 2026

Replace the alternating image-and-copy sections after the hero with one evolving composition. The approved app-orbit hero remains the point of entry. Its quiet geometry breaks into a voice signal, then marble, revolutionary painting, a personal workspace, and the blue-ink echoes of reproduced words. Human agency is the through-line.

### Tokens

- Cloud `#f8fafb`: continuous with the hero.
- Periwinkle `#dee3fa`: the voice composition and selected software surfaces.
- Cobalt `#3848ce`: voice traces and foreground typography.
- Ink `#171d31`: the freedom painting and provenance field.
- Lilac `#c3b7ed`: overprinting and digital displacement.
- Signal `#ea927e`: small traces of a human voice, not every call to action.
- System sans for oversized compressed-looking display type and readable copy. Georgia italic only for handwritten-like interruptions. Existing monospace only for artwork's file/interface fragments, not section labels.

### Layout

```text
                  approved app orbit
                       download
                  signal opens outward
       Think                   [marble]
                    out loud.
             [voice waveform crosses the edge]
    [revolution painting bleeds up behind the type]
        Keep your              mind yours.
                [personal workspace / Vermeer]
         Intelligence on your terms.
            for the people. [open future note]
      [printed words become digital copies]
          Who said that?       [history link]
                  quiet FAQ / download
```

Typography shares the art plane instead of sitting in a parallel column. Figures and credits remain semantically grouped. The hero-to-story handoff is a soft field with expanding signal contours; no hard colour block, carousel, scroll interception, or section-by-section reveal.

### Brief review

The previous alternating grid, padded banners, repeated paragraphs, and standalone bridge looked like a page-builder stack. Remove those patterns. The distinctive element is the continuous overprinted art composition; keep navigation, download controls, and small explanatory copy quiet. Do not add an unrelated dashboard, decorative badge wall, invented historical quote, or generated image.

The user explicitly requested launch-state copy: open source is presented as available, with the existing repository link. This copy change does not change repository visibility. Local inference is distinguished from online tasks and optional proof publication. Artwork retains public-source credits. Existing branded hero and voice companion stay recognisable.

### Motion and access

Use a scroll-linked signal expansion and modest art displacement as progressive enhancement. Prefer CSS scroll timelines where supported; unsupported browsers receive the composed static design. Motion does not gate reading or links. Reduced motion has no scroll displacement. No permanent new JavaScript render loop or new dependency. Artwork is lazy-loaded with intrinsic dimensions and mobile sources. Small screens get deliberately recomposed posters, not a shrunken desktop canvas.

### Verification

LANDING-006 covers artwork, credits, companions, local hosting and responsive bounds. LANDING-007 covers missing artwork. LANDING-VM-002 covers the story's destination. Existing entrance and navigation journeys continue to cover the hero, reduced motion, download and shared navigation.

## Live preview resize failure

The new flower initially entered the live page before its canvas sizing rules existed. At DPR 1.5, its drawing buffer contributed to layout; ResizeObserver measured the enlarged parent and enlarged the buffer again. Browser reproduction recorded heights 608, 2159, 4604 px in successive observations. The controlled reproduction stopped growth before the next allocation.

The canvas now receives absolute positioning and 100% CSS dimensions before insertion. The host has an intrinsic aspect ratio in the component itself. Drawing-buffer sizing is capped at 1000 x 1200 CSS pixels before the DPR cap and unchanged measurements are ignored. A repeat of the same browser scroll stayed at 521 x 608 CSS pixels and 781 x 912 drawing-buffer pixels in all five samples.

The sculpture now uses a locally hosted [Innerscene CC0 rose](https://www.innerscene.com/tools/library/3d-parts/rose-flower-with-stem-b2a45a50), with 18 separate petal meshes and 10,932 source triangles. `scripts/prepare-rose.py` removes unused textures, reducing the file from 903,056 to 467,160 bytes. Its embedded copyright is retained. Vite serves a hashed local asset, loaded near the viewport. Scroll progress rotates petal hinges in staggered layers; rendering stops when it settles or leaves view. Reduced motion shows the open pose. Fetch failure, context loss and WebGL failure retain static artwork. No third-party viewer is embedded.

Canvas sizing follows [Three.js responsive-canvas guidance](https://threejs.org/manual/pages/responsive.html), with [Vite async chunk loading](https://vite.dev/guide/features#async-chunk-loading-optimization). There is no new runtime dependency. Both companion illustrations are lightweight vectors: one is the toolbar avatar, the other peeks through the marble with foreground fingers.

## Final depth and tonal pass

The portrait uses three explicit planes: character, marble strip, foreground fingers. Their shared coordinate space keeps the contact point aligned on all screen sizes. The provenance composition now stays on cloud and pale lilac paper, with blue-ink woodcut and rose/teal overprinting. No dark panel or new animation is introduced.

## Rose unfolding correction

Live reproduction showed identical petals at scroll progress 0 and 1. GLTFLoader changes spaces in mesh names to underscores, so the old matcher found no petal hinges. The matcher now accepts loaded names; the closed head retains nested layers instead of intersecting petals. The bud stays closed until its centre reaches 74% of the viewport, then opens over 52% of viewport-height scrolling. A 230ms time-based damping constant removes sharp scroll catch-up without an endless render loop. E2E tests compare the actual WebGL silhouette at closed, intermediate and open states, not only a progress counter.

## Mobile navigation and handoff

The expanded mobile menu occupies a full viewport in document flow. Compact navigation keeps the brand, “Get started on macOS” and menu toggle in one row; a large Apple-marked action anchors the expanded menu. Touch controls are at least 44px high, with 60px for the main menu action.

[Wispr Flow's download page](https://wisprflow.ai/downloads) offers email links for desktop installation on another device. [Linear](https://linear.app/download) separates desktop downloads and mobile app stores. For hush, mobile visitors receive the public website link through their own share sheet, mail app or clipboard. [Web Share](https://developer.mozilla.org/en-US/docs/Web/API/Navigator/share) is capability-detected, invoked only from a user action and has email/copy fallbacks. No new backend, email capture or account step is introduced. Desktop downloads keep the existing immutable installer URL and release-notes flow.
