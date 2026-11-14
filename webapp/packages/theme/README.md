# @hush/theme

The shadcn theme of the hush admin: the design tokens of Shade, Ghost Admin's
design system, unchanged, so the admin looks and feels like Ghost.

`src/tailwind.theme.css`, `src/theme-variables.css` and `src/preflight.css`
(from `apps/shade`) and `src/element-styles.css` (from `apps/admin/src`) are
copied verbatim from [TryGhost/Ghost](https://github.com/TryGhost/Ghost) at commit `c2617d08d01ccc96ce88f3f8bd99c9383b518a7b` (MIT,
`LICENSE.ghost`). Update them by copying again, never by editing; hush-specific
tokens go in the app. `src/theme.css` wires them up with Inter (SIL OFL, via
`@fontsource-variable/inter`) and Ghost Admin's 62.5% root size.
