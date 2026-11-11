# README artwork

`dashboard.png` and `personas.png` are window-only captures of the native Debug
preview interface. The dashboard uses `DashboardViewController.previewData`:
sample activity, estimates, and sample app destinations. They are not user
statistics or measured performance claims. No personal history was captured.

`readme-cover.html` composes the unchanged dashboard capture on a quiet background.
`readme-cover.png` is its browser render at 1280 × 900. Update the source and
re-render rather than painting over the generated image. Keep the demo-data
caption when reusing it. No AI-generated imagery or invented product UI is used.

The native app's two preview entry points are Debug-only:

```text
--preview-dashboard --preview-light-appearance
--preview-personas --preview-light-appearance
```

Use a window-only capture, inspect for private data, and avoid including other
apps or the desktop. A browser can render the cover locally; no remote font,
analytics, script, or image service is required.
