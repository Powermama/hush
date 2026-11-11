# A GitHub front page for hush

Reviewed 2026-11-10. These are useful reference projects, not a ranking by stars.
The aim is a clear path from understanding hush to trying it or contributing.

## References and decisions

| Reference | Observed pattern | Applied to hush |
| --- | --- | --- |
| [Ghostty](https://github.com/ghostty-org/ghostty) | Recognizable icon, concise positioning, download/documentation/contributor links up front | A compact branded opening and four useful destinations |
| [Zed](https://github.com/zed-industries/zed) | Short introduction; installation and development paths are separate | Get the app before build instructions; move engineering detail into a development guide |
| [LocalSend](https://github.com/localsend/localsend) | Concrete local-processing promise, screenshots, compatibility and download guidance | Explain offline inference and actual network exceptions; state Apple silicon and memory guidance accurately |
| [Ice](https://github.com/jordanbaird/Ice) | Real macOS visuals, visible development status, straightforward installation | Native dashboard screenshot, alpha/beta labels, DMG drag-to-Applications instructions |
| [Bruno](https://github.com/usebruno/bruno) | Offline-first positioning, a large product image and contribution path | Lead with local ownership, then visual evidence and useful contribution instructions |
| [GitHub README guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes) | Purpose, usefulness, getting started, help and contributors; relative asset/document links | Keep the README navigable in forks and local checkouts |

No third-party artwork or README copy was transplanted. No badges for unconfigured
CI, unsupported package-manager installs, invented adoption figures, or inaccessible
community channels were added. The native component retains its existing MIT notice.
The subsequent [licensing decision](../../../LICENSING.md) adopts AGPL-3.0-only
for original hush code and documentation, preserving earlier grants.

## Screenshot direction

Use the real dashboard as the main image, framed with hush's pale blue/lilac
palette. The app's existing Debug preview supplies realistic demo activity.
Keep that fact visible. An expandable Personas screenshot adds detail without
turning the introduction into a long gallery. Capture provenance and the editable
composition are in [the artwork notes](../assets/README.md).

## Star-history graph

The familiar hand-drawn graph is [Star History](https://github.com/star-history/star-history).
Its [embedding guide](https://www.star-history.com/blog/how-to-use-github-star-history/)
supports theme-aware README images. This is a data visualization, not evidence of
product quality. Its live embed refreshes data; it is not a guaranteed animated
line-drawing effect in GitHub's image renderer.

At this check, GitHub's authenticated repository API reported hush-macos as
**private, with zero stars**. Public chart services cannot read that private data.
The README therefore has no broken image and no illustrative growth curve.
Do not send a repository token to a chart service or put credentials in image URLs.

After the user makes the repository public, validate the provider's current
unauthenticated image endpoint before enabling the following integration shape:

```html
<a href="https://www.star-history.com/?repos=Powermama%2Fhush&amp;type=date">
  <picture>
    <source media="(prefers-color-scheme: dark)"
      srcset="https://api.star-history.com/chart?repos=Powermama/hush&amp;type=date&amp;theme=dark">
    <img alt="GitHub star history for hush"
      src="https://api.star-history.com/chart?repos=Powermama/hush&amp;type=date">
  </picture>
</a>
```

This is a pending launch snippet, not a validated live hush chart. The provider's
current README also uses a newer `/chart` endpoint with sealed-token parameters;
do not copy another repository's token. If the public embed needs credentials,
prefer a static SVG generated within the repository's own GitHub Actions from
real GitHub data. Keep credentials inside Actions and store only aggregate chart
data. A chart with zero or one data points should say so, not suggest growth.

## Public launch follow-through

- Review the repository's tracked contents and history separately before changing visibility.
- Recheck the canonical website download, contributor links and screenshots.
- Set the About description to `The voice layer for your Mac. Local dictation, writing, and an AI assistant.`
- Set the website to `https://behu.sh/` and relevant topics such as `macos`, `swift`, `speech-to-text`, `local-ai`, and `apple-silicon`.
- Enable the star chart only when it returns a real chart without private credentials.
- Keep the existing MIT file and third-party/model attributions intact.

The initial README design did not change visibility or hosting. The later
[monorepo migration](../../../docs/monorepo-migration.md) created the private
`Powermama/hush` repository. The
[community review](../../../docs/research/2026-11-10-community-structure.md)
extends this analysis with contributor workflows and documentation structure.
