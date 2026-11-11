# Contributing to hush

Bug reports, documentation, accessibility improvements and code all help.
The [native development guide](macos/docs/development.md) and
[web guide](webapp/README.md) explain how to run each part.

## Your first contribution

Start with a documentation improvement, a reproduced bug or a small accessibility
fix. Search [existing issues](https://github.com/Powermama/hush/issues) first.
For a substantial feature, describe the user problem and intended result in an
issue before investing in an implementation. Helpful reports and careful design
feedback are welcome even if you do not write code.

Use the [docs hub](docs/README.md) to find your area and the
[journey index](docs/reference/user-journeys.md) to find its behaviour and tests.
Follow the [community expectations](CODE_OF_CONDUCT.md). You are responsible for
understanding, reviewing and testing everything in your PR, including work made
with coding tools. Do not paste generated changes that you cannot explain.

## One change, one pull request

Start a short-lived branch from current `main`, named for the change:

```sh
git switch main
git pull --ff-only
git switch -c fix/recording-hud
```

Use `feat/`, `fix/`, `docs/` or `chore/` prefixes. A feature can have several small
commits while it is being developed; it does not need a separate branch for every
commit. Keep unrelated changes in separate pull requests.

Use Conventional Commits for commit messages and PR titles:

```text
feat(personas): add a writing style picker
fix(hud): stop the timer when recording closes
docs(setup): explain local model downloads
```

Use a PR to review the result and its checks. Squash-merge a focused PR into
`main` with its conventional title, then remove the merged feature branch. Do
not rebase or force-push `main`, recreate release tags, or invent historical
commits to make earlier development look different. Generated changelogs are
never edited by hand. Do not add an agent co-author trailer.

## Explain and verify the change

Lead the PR with the user-visible problem and resulting behaviour. Include the
reproduction, checks run, and known limitations. For visual changes, include
screenshots with demo content and check mobile or native Light/Dark appearances,
keyboard navigation and Reduce Motion where relevant.

Reproduce bugs in the running product before fixing them. Keep the change
focused, fix encountered test failures, and update the relevant journey contract
and tests together. Read the component's `AGENTS.md` for its required checks.

The shared CI selects checks for the affected components: web type checking,
server tests, API drift detection, browser journeys, Swift package tests,
Swift-to-service integration and unsigned Release compilation. Ready PRs and
`main` pushes are checked; manual runs check everything. See the
[CI guide](docs/explanation/continuous-integration.md) for the selection rules
and the required `CI result` status. CI does not replace live model, permission,
audio-device, Spaces or signed-installation testing on a Mac.

## Report safely

Include the version/build, macOS version, chip, memory, selected model, expected
behaviour and reproduction steps. For hangs, include the app and audio device in
use. Review screenshots and process samples before sharing. Never attach real
messages, audio, private proof links, decryption keys or credentials.

For security findings, follow [the private reporting policy](SECURITY.md).
Do not publish sensitive details in an issue.

## Respect ownership

Preserve upstream copyright, license and attribution notices. Only contribute
material you have permission to contribute. Declare copied or adapted material
and new dependencies in the PR. Artwork and AI weights can have different terms
from source code.

By submitting an original contribution intended for inclusion in hush, you
license that contribution under **[AGPL-3.0-only](LICENSE)**. You retain your
copyright; no assignment or additional proprietary relicensing permission is
required. Confirm that you have the necessary rights, including any required
employer permission. Identify existing third-party material separately rather
than claiming it as your original contribution.

Changes to separately licensed material must respect its stated terms. Preserve
the native baseline's MIT notice and the artwork's licenses. See
[LICENSING.md](LICENSING.md) for the scope. Do not silently change another
contributor's license or remove their attribution.

For new original source files, use the comment syntax of that language to add
`SPDX-License-Identifier: AGPL-3.0-only` and an accurate copyright notice. When
modifying imported permissive code, retain its notice and identify your dated
changes separately. Do not bulk-label generated code, dependencies, model
weights or artwork as original hush code.

Write the product name as **hush**. Existing identifiers such as the `Hush` Xcode
scheme keep their exact case.
