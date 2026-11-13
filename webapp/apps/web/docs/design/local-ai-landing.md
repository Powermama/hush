# Hush landing direction

## Design plan

- Porcelain `#FAFBFC`: quiet page surface.
- Graphite `#24272B`: type, primary actions, the Hush device.
- Slate `#626973`: supporting text with readable contrast.
- Silver `#DCE2E8`: physical edges and connecting paths.
- Ice `#BFE7F1`: translucent layers of the local AI object.
- Leaf `#247A57`: privacy cues and focus outlines.

Use the system sans stack: large, tightly spaced display type and small, readable interface text. No web font download. Center the hero, align explanatory content left, keep a single readable column on mobile.

```text
hush                    GitHub   Verified Messages   Community   Download

                     The voice layer for your Mac.
                              one sentence

                         Mail       Messages
                   Notes       [3D hush]       Slack
                       Chrome           Notion
                           Figma

                          Download for Mac
                    Free alpha for Apple silicon Macs

                 Private by design. Local by default.
                 short facts + optional verification link

                 questions                    final download
```

## Review against the brief

The user asked for a circle of familiar app icons, less copy and no logo slider. The hero uses a constellation around Hush's own waveform, showing voice reaching familiar apps. The dimensional object is the distinctive element; the rest is restrained. On review, the user removed the entire example/tab section, the model's status label, replay and skip buttons, and the cursor follower. The background now deforms gently near the pointer instead. The assistant's beta limits and hardware requirements remain in the native FAQ disclosures.

The download sits below the icon ring with enough separation from Figma's label. Its entrance uses opacity only, with no blur. A solid dark background remains even if the decorative gradient is unavailable. Hover and press change shading, never position. The header joins the entrance with a brief opacity reveal. Any keyboard, pointer, touch or wheel input completes the entrance immediately.

## Reference analysis

Inspected `superdesigndev/treg`, including `src/treg/web/landing.html` and `src/treg/web/media/landing/`. The reference uses procedural Three.js geometry, glass/metal materials, connecting paths, and an entrance sequence. Its root license includes additional commercial-use restrictions. Hush's geometry, scene, choreography, copy and styling are independently authored; no reference code or assets are included.

Use a dynamic import for the scene, render on demand, cap resolution, respect reduced motion, dispose GPU resources, and preserve a CSS visual if WebGL or the module is unavailable. Never hide the download behind the animation. The graphic is a product illustration, not a real microphone or an agent running in the browser.

The reference's opening combines a travelling/settling model, staggered content, paths and a background reveal. Hush uses a shorter three-second assembly, delayed icon/path entrance and a final download fade. Wheel, touch and keyboard input end the entrance. Reduced motion shows the composed scene immediately. No scroll lock, external 3D asset, analytics, microphone access or animation loop at rest is added.

Three.js references: [on-demand rendering](https://threejs.org/manual/pages/rendering-on-demand.html), [resource disposal](https://threejs.org/manual/pages/cleanup.html).

## Editorial story extension

Keep the approved hero intact. The new sections tell a human story through existing public-domain art. No generated artwork, laptop renders, product screenshots, feature cards, or invented historical quotations.

### Plan

- Porcelain #FAFBFC and graphite #24272B connect to the hero. Ice #C5E9E9 and ink blue #224B72 recolour a classical portrait. Coral #EF9C90 and dark blue #172D46 reinterpret the freedom painting.
- System sans remains the voice of the page; a quiet Georgia serif sentence bridges the two artworks. Display headings are short, large and left aligned. No eyebrow labels or decorative chapter numbers.
- First composition: an oversized cut-paper portrait of Aristotle with displaced image strips and a drawn voice wave, beside "Think out loud." Human expression precedes software.
- Second composition: Delacroix's painting becomes a wide, immersive duotone artwork with "Keep your mind yours." Local AI is framed as ownership and personal freedom, not a product specification.
- Finish with a short factual note about on-device inference and online actions, then the existing FAQ and download. Source credits are readable links beneath the art.

```text
   Think out loud.          blue marble portrait
   a short thought          gently displaced strips

               A little less machine.
               A little more human.

   [ coral / ink painting, full width              ]
   [                  Keep your mind yours.        ]
      Liberty source credit

   [ Vermeer: The Geographer ]  Intelligence belongs
      Vermeer source credit     on your side.
                                personal, local AI story

             concise privacy note / FAQ / download
```

### Review against the brief

The initial product-render concept did not meet the user's request and was discarded before inclusion. This direction uses cultural artwork as a metaphor for expression and freedom, with two distinct compositions rather than repeating feature panels. Typography and real images carry the story. Colour edits, cropping and displacement are implemented with CSS and SVG; source images are locally hosted, compressed and credited. No museum or artist endorsement is implied.

Pointer effects are subtle progressive enhancement, not a prerequisite to reading. They stop when the pointer leaves and are disabled for touch and reduced motion. No repeating animation, scroll hijacking or new framework. Images load lazily with intrinsic dimensions. A missing image must not hide the story or download.


### Intelligence section correction

The original afterword left a credit floating in an otherwise empty left column. Keep the Liberty credit directly beneath its banner inside the same figure. Give the intelligence story its own section and locally hosted artwork: Vermeer's *The Geographer*, showing a person thinking with tools within reach. Retain the painting's blue robe and natural light rather than repeating the Liberty treatment.

Preserve porcelain #FAFBFC, graphite #24272B, slate #626973, ink #224B72 and ice #BFE7F1. Keep the existing system sans and left-aligned type. Use a square crop with the face, hands and globe visible, an attached source caption, and vertically balanced copy beside it. Stack image, caption and copy on mobile. No extra card frame, decorative labels or animation. Review: three different compositions now support voice, freedom and personal intelligence; each artwork and attribution has an unambiguous home.


### Classical art, personal computing and creative independence

The user's next direction adds contemporary symbols to older imagery and a punk Steve Jobs portrait. Keep the previous layout and typography, extending the palette with pale circuit cyan #C9F3EF and a restrained magenta #E765AB only inside the photographic collage. The Vermeer gets a fine circuit line from his working tools to a chip/wave mark reading “On your Mac.” Its subject stays visible. This makes on-device inference concrete while the nearby text retains the online-feature exceptions.

Close the story before the FAQ with “For minds of their own.” Original copy about dreamers and outsiders sits beside the openly licensed Jobs photograph. Grayscale, two displaced coloured strips, fine scanlines, a command symbol and a pixel cursor supply the requested punk quality. Keep the person recognisable; no flashing, continuous glitches or motion required to see the composition. Only fine-pointer hover displaces the strips a little further. Use the existing blue-white surface and asymmetric type/photo layout; omit campaign quotations and any claim of endorsement.

Review: the symbolic overlays have concrete meanings (local compute, keyboard creation and direct manipulation). They do not introduce a cloud-provider logo wall, product dashboard, or generic neon backdrop. Three classical images lead to the era of personal computing, then the factual FAQ and download.

### Hush as a companion inside the art

The user wants a recognisable mascot in different states, composed into the artwork rather than UI panels. Retain the hero's graphite square, silver waveform and ice glass as the character's identity. The two central waveform bars become expressive eyes; small arms and feet give it a physical presence. Use original inline SVG, not generated raster images or a borrowed mascot.

Replace the Vermeer chip/status card and circuit frame with Hush thinking beside the map. Put a listening pose beside Aristotle and a recording pose in the lower part of the Jobs composition, with a small “Think different.” speech motif. Keep faces and hands visible. The slogan is a creative reference, not a claim of a recorded Jobs utterance or endorsement. Remove the separate Jobs cursor so the character carries the gesture.

The palette stays graphite #24272B, silver #DCE2E8, ice #BFE7F1 and coral #EF9C90. Three poses share one lightweight SVG component. Each has an accessible illustration label, no button semantics, no microphone access and no live status message. Fine-pointer hover can produce one brief character gesture; reduced motion and touch show a still pose. No page-fixed buddy, chat panel, or dashboard chrome.

Review: a recurring illustrated companion connects the historical artwork to the voice-layer headline. The character belongs to each composition and has a different role in it; it is not a product demonstration floating over the page.

The companion now uses Three.js, as requested, sharing the hero's deferred engine. Use a chibi proportion, bright expressive eyes with small catchlights, a tiny smile and soft coral cheeks. Keep the waveform embossed below the face so it remains recognisably hush. Give each pose a material accessory: listening headphones, thought beads, or a small microphone. The SVG is only a visual fallback when WebGL is unavailable. Mount only near the viewport, stop rendering at rest/offscreen, and dispose resources on unmount. Use lowercase “hush” in visible branding.

### Scroll-linked listening entrance

The latest direction ties the listening character to actual scroll progress. As the Aristotle art moves from the lower viewport into its reading position, hush descends a thin line, points toward “Think out loud” with one hand, and grips the line with the other. The line endpoint follows the projected 3D hand. Sway responds to scroll movement and settles at rest. At the final position the line retracts, the pointing arm relaxes, the character lands with a brief bounce/blink and smiles. Scrolling upward reverses the descent. No scroll lock, autoplay drop or replay control.

The render loop runs only while scroll/gaze smoothing or a bounded landing gesture remains active. Reduced motion and WebGL failure show the settled character without the line. The native scroll handler is passive and is removed on cleanup; hidden/offscreen scenes stop rendering. The figure remains the positioning context throughout.

### From the printing press to message provenance

After Jobs, close the narrative with a deliberate cyberpunk collage. A real public-domain Jost Amman printing-press woodcut from 1568 dissolves into overlapping digital voices. The internet expanded publishing; AI and bots complicate our ability to infer a message's origin from its words alone. “Reality has a copy problem.” opens the composition. One continuous cyan thread crosses the noise and leads to “Give your words their story back.” Each headline is one thought on two lines, with the closing heading smaller than the opening heading.

Palette: midnight ink #111827, cold paper #EAF3F7, electric cyan #8CEDE7, printed pink #F190C9, muted steel #A5B6C7. Keep the site's system sans for the narrative and large headline; Georgia represents the printed word inside the artwork. Use a full-width, asymmetric collage, not another two-column product panel or a feature-card grid. Oversized, displaced lettering provides the cyberpunk character. Let the image and typography carry the energy; no flashing, automatic glitch loop or animated blur.

Layout: a left-aligned headline and short historical introduction; below, a woodcut on the left becomes a field of fragmented voices on the right. A drawn thread passes through the composition and ends at the message-history conclusion. Following the user's review, remove the captured/edited/signed labels, explanatory paragraphs and disclosure from this ending. Keep only the headline and link to the full Verified Messages story, where optionality and proof limits remain explicit. “Who said that?” is solid dark lettering on irregular cyan/pink graffiti strips. A split organic/wireframe face carries the visual question. Keep the smaller copy-of-a-copy line beneath the painted lettering and the source credit clear of the image.

Review: cyberpunk is the explicit user direction, so the dark surface and cyan/pink displacement are intentional. The historic woodcut, printing-to-network transition and unbroken history thread make this specific to hush's voice/provenance narrative. No extra mascot or fake verified badge is needed. Images remain locally served, responsive and credited. The artwork is static and readable with reduced motion or image failure; any fine-pointer movement is limited to displacement of decorative fragments.

## Latest story simplification

Remove the entire “For minds of their own” / Steve Jobs chapter, including its portrait, copy, recording mascot and chapter-specific styles. The local-intelligence composition now flows directly into the printing-press / Verified Messages story. The Jobs exploration above is superseded; the two remaining mascot compositions are unchanged.

## First-paint entrance correction

Reproduced the early flash with the scene module held in a real browser: the fallback logo, header, halo and field were already opaque while the heading and icons waited. The initial pending state now exists on the landing root in its first React commit. All hero layers and the shared header start at zero opacity. The WebGL scene and CSS reveals start together, with no blur or visible fallback crossfade. The header fades in first, the model assembles, the headline and icons follow, and the download appears last.

The finite entrance preserves native input interruption, skips for reduced motion or anchor/restored scroll, and releases a complete usable fallback after 2.2 seconds if the scene is slow. Late scene loading does not replay the entrance. The same Header component stays static on other pages.
