# Full-width story navigation

Keep the story artwork as the focal point. The header is larger and uses the viewport width, with a 40px brand mark, system sans labels and generous horizontal breathing room. All navigation sits on the right: GitHub, Verified Messages, Community and Download. Remove Privacy and What's new from this header; their footer destinations remain.

Use porcelain #FAFBFC, graphite #24272B, slate #626973, ice #BFE7F1 and muted coral #E7A39C. The Verified Messages page uses its existing midnight surface and light lettering. A single shared component supplies both headers. On mobile, logo/download occupy one row and the visible navigation a second, rather than hiding destinations in a menu.

The app repository is still private. The user explicitly requested linking to https://github.com/Powermama/hush-macos anyway. Do not change visibility. Community is a clearly unavailable control until its URL is supplied, not a dead link or invented community destination.

The header remains in document flow and scrolls away. Only a slim reading-progress line stays at the top. Its fill follows native scroll position. There are no markers, section points or counters. It updates at most once per animation frame, observes content size changes, has no idle loop and cleans up on unmount. Reduced motion keeps direct progress updates without easing. This is an informational indicator, not a navigation slider or a scroll lock.

## Home entrance performance

The home headline has a little extra breathing room below the header: 28px of hero top padding on desktop and 33px on mobile, an increase of 8px and 6px respectively. This spacing is static throughout the entrance.

The home header fades from opacity 0 to 1 while translating down 14px into place over 1.05 seconds, with a 120ms delay and a smooth ease-out. Only opacity and transform change. Header size, padding, font and document position remain fixed. No blur, animated shadow, persistent will-change hint, new animation dependency or React frame loop is added. The landing root owns the initial hidden state so deferred WebGL does not flash the header or fallback model first. Other pages retain a static header.

Reduced motion shows the header immediately; user input ends the entrance. A slow/failed scene restores the complete page. Browser checks sample the fade mid-flight and verify that its layout dimensions stay unchanged.

References: [web.dev animation performance guide](https://web.dev/articles/animations-guide), [MDN reduced motion](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-motion), [MDN will-change cautions](https://developer.mozilla.org/en-US/docs/Web/CSS/will-change). These guide implementation; they are not a claim of measured frame rate on every device.
