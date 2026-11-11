# Community and documentation references

Reviewed 10 November 2026. These are patterns observed in project-owned source
and documentation, not a claim that one folder layout is an industry mandate.

| Project | What was inspected | Applied to hush |
| --- | --- | --- |
| [Ice](https://github.com/jordanbaird/Ice/blob/main/README.md) | Native screenshots, visible development status, installation and gallery | A real dashboard cover, a demo-data caption and a clearly labelled alpha |
| [LocalSend](https://github.com/localsend/localsend/blob/main/README.md) | Product purpose, screenshots, compatibility, development and protocol links; [support/docs](https://github.com/localsend/localsend/tree/main/support/docs) | Explain the local-processing boundary, show the app and separate installation from engineering |
| [LocalSend contributing](https://github.com/localsend/localsend/blob/main/CONTRIBUTING.md) | Paths for code, translation, documentation and bug reports | Welcome useful non-code work and request reproducible reports |
| [Zed contributing](https://github.com/zed-industries/zed/blob/main/CONTRIBUTING.md) | Focused contributions, local testing and feature discussion | Keep PRs focused; explain a substantial feature before implementation |
| [Zed feature process](https://github.com/zed-industries/zed/blob/main/docs/src/development/feature-process.md) | Problem evidence, concrete behaviour and cross-feature impact | Journey changes describe the outcome, failure states and affected surfaces |
| [Zed docs](https://github.com/zed-industries/zed/tree/main/docs/src) | Topic-oriented user docs, development guides and a documentation index | One navigable docs entry point, with separate user and contributor paths |
| [Ghostty](https://github.com/ghostty-org/ghostty/blob/main/HACKING.md) | A separate engineering guide, platform requirements and manual input-test matrix | Keep build details out of the introduction and distinguish automation from manual evidence |
| [Bruno contributing](https://github.com/usebruno/bruno/blob/main/contributing.md) and [docs](https://github.com/usebruno/bruno/tree/main/docs) | A package map, pinned toolchain, separate contributor/publishing docs and browser-test guidance | Explain component boundaries and give each component an exact setup and validation path |

These projects do not use one common `user-journeys/` convention. hush already
has scenario-based contracts with test mappings. We keep those, add an index,
and make their evidence boundaries easier to see. This is an adaptation of the
observed practices, not a copied project structure.

Some references have restrictive contribution intake or AI policies. hush does
not adopt their vouch systems, public blocklists or blanket restrictions. A
contributor remains responsible for understanding and testing their changes.
No third-party README text or artwork is copied.

## Standards used

- [Diátaxis](https://diataxis.fr/) separates tutorials, task guides, reference and
  explanation by reader need. It does not require a documentation generator or
  moving every component guide into four new directories.
- [GitHub README guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes)
  informs the introduction, getting-started links, help path and relative assets.
- [GitHub community profiles](https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/about-community-profiles-for-public-repositories)
  identifies the recognised locations for contribution, conduct, security and
  issue-reporting files. A green checklist is not a legal or quality certificate.
- [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
  supplies the commit-title format. GitHub validates the PR title used for the
  squash commit; release numbers still require an intentional release decision.

## First-page design

The root README is the visual entry: icon, concise positioning, useful links,
one native dashboard image, a short start guide and a clear contribution path.
The optional Personas screenshot stays collapsed. Images are stored in the
repository with descriptive alternative text and documented capture provenance.
No invented adoption numbers or badges for unconfigured services are used.

The star-history chart remains deferred while the repository is private. When
public, validate a real unauthenticated chart before adding it. Never embed a
private access token or fabricate growth to fill an empty graph.
