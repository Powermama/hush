# Visual landing journey

## Goal

A visitor understands hush as a local voice interface for familiar Mac apps and can download the notarized alpha. The original 3D object and app constellation carry the first impression. Product limits are available without making the hero dense.

## Invariants

- Downloads retain the immutable release URL and matching release-note flow documented in `private-alpha-download.md`.
- A decorative scene must never block navigation, scrolling or downloading.
- Both Vite development and the production server render the same 3D hero and rose. The lighting loader detects gzip bytes after Fetch's HTTP decoding, avoiding double decompression when a host sends `Content-Encoding: gzip`. The real Vite-server journey in `tests/studio-lighting.spec.ts` covers both scenes in Chromium, mobile Chromium and WebKit; the production scene and missing-asset journeys cover static-file delivery and fallback.
- The hero and rose share one locally hosted, prefiltered studio-lighting download. They do not run PMREM convolution in the visitor's browser. The KTX2 asset retains six reflection levels and independently disposable GPU textures. A failed lighting request keeps the static artwork and controls usable; leaving the page during loading cannot mount an abandoned scene. Regenerate the asset with `node scripts/bake-studio-environment.mjs` when upgrading Three.js's PMREM format. The loading-failure journey is covered in `tests/entrance.spec.ts`.
- WebGL or module failure retains the CSS hush illustration and all app icons.
- Reduced-motion visitors see the complete composition without entrance or pointer animation.
- The entrance is finite and ends on wheel, keyboard or touch input. No visible skip or replay controls are shown, as requested.
- The background responds only to mouse proximity, settles at rest, and suspends when hidden or offscreen. The page does not request microphone access.
- The button fades in during entrance; hover and press preserve the background, text colour and position of the header and both landing download actions. Keyboard focus retains a visible outline.
- The beta assistant, macOS 15 / Apple silicon requirements, optional 16 GB recommendation and online-task exceptions remain clear in FAQ disclosures.
- Optional verification links to the complete proof explanation and limits. No new tracking is introduced.
- Below the hero, public-domain art tells a story about voice, human expression, ownership and personal creativity. No generated images or product feature showcase is used. Visible source credits link to the original rights statements.
- Artwork is hosted locally, lazy-loaded with responsive sizes, and has intrinsic dimensions and descriptive alternative text. Decorative duplicates are hidden from assistive technology. Image failure does not hide the narrative or download.
- From the hero, a voice-signal transition unfolds into a continuous art composition. Typography overlaps artwork, Liberty bleeds into the local-intelligence composition, and the printing-press scene resolves into the same canvas as the FAQ and download. Semantic sections remain for navigation. Source credits belong to their figures; no image request depends on Wikimedia or museum servers.
- A small hush cameo peeks from the marble collage, with its face visible and lower body occluded by a foreground strip. Its fingers sit in front of that same strip. It stays attached to the artwork during scrolling. The thinking companion is a small vector avatar within the Vermeer workspace's toolbar, not a floating overlay. The illustrations are not app controls or live microphone states. Online actions and optional publishing remain explicit exceptions. At the user's request, open-source copy is written for release, linked to the existing repository; this does not publish the repository.
- A locally hosted CC0 pearl/lilac Three.js rose extends between the freedom and local-intelligence compositions. Its 18 separate petal meshes remain closed until the bud is comfortably visible, then open gradually over approximately half a viewport of native scrolling and close when scrolling back. Elapsed-time damping smooths the petal movement even when rendering is slow, with its clock reset after idle or hidden intervals; entering view alone does not play the animation. It loads near the viewport and renders only during changes. Its CSS size is independent of its capped drawing buffer; it cannot expand the layout through ResizeObserver. Static artwork remains when the module, model asset or WebGL fails. Reduced motion shows the fully open rose with no pointer response, and offscreen or hidden scenes do not render.
- Colour treatments, the command symbol and portrait distortion are CSS/SVG. Collage strips respond to fine-pointer hover only when reduced motion is not requested; there is no repeating story animation.
- Story companions are static vector artwork, with no extra WebGL context, scroll listener or animation loop. All visible brand names use lowercase “hush”.
- After the local-intelligence chapter, a blue-ink printing-press collage on the continuous light canvas closes the narrative with optional Verified Messages. A public-domain woodcut becomes fragmented digital voices; one continuous line leads to signed message history. It never presents its illustrative typography as a real proof, human-origin detector or identity guarantee. No flashing or continuous glitch animation is used.

## Scenarios and tests

All automated scenarios live in `tests/landing.spec.ts` and run on desktop Chromium, mobile Chromium and WebKit, except the hover check which is desktop only.

| Journey | User outcome |
| --- | --- |
| LANDING-001 | Read the headline, see app imagery and download without icon/button overlap or horizontal scrolling. |
| LANDING-002 | Open hardware, offline and beta disclosures using keyboard or pointer. |
| LANDING-003 | Continue to see the illustration and download if WebGL is unavailable or the scene module cannot load. |
| LANDING-004 | Reduced motion shows content immediately and keeps collage fragments still on hover; Escape ends entrance without blocking content. |
| LANDING-005 | Hover and press preserve the background, text colour and position of the header, hero and closing downloads. Keyboard focus remains visible. |
| LANDING-006 | Read the continuous composition, load four locally hosted source images, inspect their credits, and see a listening character in the portrait and a vector companion in the personal workspace. The open-source link points to the app repository. Headlines and figures stay within responsive bounds. The removed Steve Jobs chapter is absent. Test: `LANDING-006 keeps each locally hosted artwork with its story and credit`. |
| LANDING-007 | The story remains readable and downloads remain available if its artwork cannot load. Test: `LANDING-007 keeps the narrative and download usable when artwork fails`. |
| LANDING-008 | The small mascot cameo remains attached to the marble collage while scrolling and stays within its artwork on mobile and desktop. Test: `keeps the mascot cameo within the artwork as the page scrolls`. |
| LANDING-009 | Scroll repeatedly through the flower and resize the window without canvas/layout growth, browser errors or horizontal overflow. The scene stops rendering at rest and offscreen; WebGL failure retains a visible static bloom. Tests: `flower stays bounded during scrolling and resizing`, `flower keeps its static artwork without WebGL`, and `flower stops drawing when idle and offscreen`. |
| LANDING-010 | See a closed bud before scrolling, then a visibly wider half-open and open rose. Scrolling back closes it; reduced motion remains open. Tests: `rose opens with native scroll and closes when scrolling back` checks rendered pixel widths, and `rose stays open with reduced motion and survives a missing model` covers the static alternatives. |
| LANDING-VM-001 | Follow the privacy section's optional verification link to the complete explanation, including proof limits. |
| LANDING-VM-002 | Read the closing printing-press-to-AI collage and follow its keyboard-accessible verification link. Optionality and proof limits remain clear. Test: `LANDING-VM-002 closes the story with message history without promising human identity`. |

Inspect screenshots for material quality, readable copy, the app constellation, button spacing and mobile proportions. Check pointer distortion and the finite entrance in the running browser.

## Shared public navigation

LANDING-NAV-001: home, Verified Messages, releases and legal pages use one full-width Header component. Right-aligned links include the public app GitHub repository, Verified Messages, a disabled Community placeholder and the existing download. Privacy and releases remain in the footer. On mobile the compact header shows the brand, an Apple-marked “Get started on macOS” action immediately left of the menu toggle. The expanded menu fills the viewport, hides the compact header action, and shows large links with a single Apple-marked download action at its bottom. The hero remains below the header in document flow. Escape or the close toggle closes the menu; keyboard focus returns to the toggle. At 320px the logo mark remains while its wordmark yields space to the controls.

LANDING-NAV-002: headers scroll away normally. Only a thin reading-progress line stays fixed at the top, without dots or section markers. It follows native scrolling in both directions and recalculates on content-size changes. Reduced motion removes easing.

LANDING-NAV-003: an open mobile menu locks the page against background scrolling
and keeps keyboard focus within the header. Closing restores the original page
position and normal scrolling. Navigating away or resizing to desktop releases
the lock. On short viewports, only the menu can scroll so every link stays
reachable. The nested mobile download dialog retains its own keyboard handling;
closing it returns to the still-locked menu, then closing the menu unlocks the page.

These journeys are covered in tests/navigation.spec.ts and the nested dialog
case in tests/mobile-download.spec.ts across desktop Chromium, mobile Chromium
and WebKit. Real-device Safari touch and browser-toolbar behaviour remain a
manual check beyond the automated WebKit coverage.

## Entrance recovery

LANDING-FOOTER-001: on mobile, the brand and description sit above two balanced
columns for Product and Legal. Both groups and their links are left-aligned.
Desktop retains its brand, Product and Legal layout. Links remain readable
without horizontal overflow at 320px. Covered in `tests/footer.spec.ts` across
Chromium, mobile Chromium and WebKit.

LANDING-ENTRY-001: on initial load at the top, the header, fallback model, background, connections, heading, icons and download start hidden in the first paint. A deferred scene starts the common reveal, without blur or a static-logo flash. The header and complete scene settle within three seconds of scene readiness.

LANDING-ENTRY-002: a slow scene is released to the complete CSS fallback within 2.2 seconds. A late WebGL scene does not replay or hide the header. WebGL failure, reduced motion, anchor navigation and user interaction keep navigation and downloads available. Tests: tests/entrance.spec.ts plus the existing failure/reduced-motion/keyboard journeys in tests/landing.spec.ts.

LANDING-010: the rose opens and closes with actual wheel scrolling; reduced motion presents its open pose, and a missing local model keeps the vector fallback. Covered in tests/flower.spec.ts.

## Mobile-to-Mac handoff

LANDING-DOWNLOAD-002: phone and iPad visitors get an Apple-marked “Get hush for Mac” action, or the compact “Get started on macOS” header action. It opens a native dialog with device sharing when supported, an email link that opens the visitor's mail app, and copyable public URL. No address is collected, no mail is sent automatically, and no DMG or release-notes popup opens on a phone. The shared URL is always `https://behu.sh/`, never a private proof URL, key, or message. A narrow desktop window retains the real download; iPad desktop browsing receives the handoff. Escape and Close restore focus and normal scrolling. Share cancellation is silent; unavailable sharing and denied clipboard access leave email and a selectable URL available.

Tests: `tests/mobile-download.spec.ts`, the download scenario in `tests/landing.spec.ts`, and the mobile invitation branch of `tests/proof.spec.ts`. Native OS share targets and mail delivery require a real device check; browser tests verify the payload and client-side interaction without sending messages.

The final invitation omits the extra slogan. Its headline has relaxed tracking and a 40px gap before the primary action. “Less input. More instinct.” shares the adjacent ribbon's rotation, and the “Independent by nature” stamp is removed.
