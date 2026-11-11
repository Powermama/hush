# Repository branding

`hush-wordmark.svg` and `hush-wordmark-dark.svg` compose the existing hush icon
with the lowercase product name for the README. The picture element selects
the appropriate wordmark for GitHub's light or dark theme. Keep the icon's four
bar proportions consistent with `macos/icon.svg`.

The dashboard and Personas images remain real native UI with disclosed demo
data; their capture sources are in [the native artwork notes](../../macos/docs/assets/README.md).

A GitHub repository does not have its own account avatar. The README artwork
and the repository's social preview are separate from the owner's profile
picture. Do not change the owner's account avatar to brand a single repository.
GitHub's social preview is configured in repository Settings, independently of
website Open Graph tags. See [GitHub's guide](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview).

`github-social.html` composes the wordmark and existing native dashboard capture.
It retains the disclosure that the dashboard contains demo data. Regenerate the
1280 x 640 PNG with `node docs/assets/render-branding.mjs` from the repository
root after installing the website dependencies and Playwright Chromium. The
renderer uses only local assets. Inspect and commit the output, then upload it
under Settings > Social preview. Git commits alone cannot change that setting.
