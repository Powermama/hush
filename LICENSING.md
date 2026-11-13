# hush licensing

Effective 10 November 2026. SPDX identifier: **AGPL-3.0-only**.

Copyright (C) 2026 Clemens Kressmann and hush contributors, for their respective
original contributions. Existing third-party copyright notices remain intact.

## Project license

hush's original source code and documentation are licensed under the GNU Affero
General Public License, version 3 only, as published by the Free Software
Foundation. The complete, unmodified terms are in [LICENSE](LICENSE).

You may use, study, modify and redistribute covered work under those terms,
including commercially. The software is provided without warranty, as described
in the license. This grant does not include a choice of later AGPL versions.

This is the default for original contributions to the macOS app, website, proof
service, tests, scripts and documentation from this licensing change onward.
hush-authored parts of the project are offered under AGPL-3.0-only, subject to
the retained licenses below. A directory name or package metadata never
overrides an existing third-party grant. More specific notices identify
separately licensed material. Sharing a repository does not by itself turn
independent works into one derivative work.

## The earlier native code remains available under MIT

The native baseline, originally imported in the private development history
as commit `b9a53dc` from `Powermama/hush-macos` revision
`f0595ed10e8ae19e0c3c0c605cd1a97d48fa0f0f`, carries the
[MIT notice in macos/LICENSE](macos/LICENSE), including its attribution to Vlr.
That notice is preserved verbatim. It records the permissions for that baseline;
it does not grant MIT permissions for subsequent AGPL-only contributions.

This decision does not revoke previously granted MIT permissions, replace the
earlier copyright holder, or assert ownership of their work. Recipients can
continue using the MIT-covered material under MIT, including in proprietary
software. AGPL reciprocity applies to the covered additions and combinations;
it cannot remove that earlier permission. Preserve both notices when combining
MIT material with AGPL contributions.

## Separately licensed material

| Material | Terms and source of notices |
| --- | --- |
| Imported native baseline | [Original MIT grant](macos/LICENSE) and the revision identified above. |
| Dependencies and bundled libraries | Their own licenses, copyright notices and any exceptions. Resolve the checked-in Swift and Bun lockfiles and retain required upstream notices. |
| AI model weights and conversions | Each exact model distribution's license and attribution. A runtime library's license does not license its model weights. |
| Bundled Whisper base model | [Model provenance](macos/Hush/BundledModels/openai_whisper-base/NOTICE.md) and [OpenAI MIT license](macos/Hush/BundledModels/openai_whisper-base/LICENSE.OpenAI). |
| Editorial photographs, artwork, adaptations and rose geometry | [Artwork credits](webapp/apps/web/public/art/CREDITS.md), including public-domain, CC0 and CC BY-SA material. Those terms remain in force for the listed adaptations. |
| Third-party app icons, names and logos | Their owners' applicable rights and notices. The hush license grants no rights on their behalf. |

Do not replace these notices with an AGPL label. Unclear provenance must be
resolved before distributing the affected material. This table describes scope;
it is not a completed dependency or rights audit.

## Contributing

Contributors retain copyright. Original contributions intended for inclusion
use AGPL-3.0-only, as explained in [CONTRIBUTING.md](CONTRIBUTING.md). Contributions
to separately licensed material must respect its stated terms. No copyright
assignment or additional proprietary relicensing permission is required by this
policy. Do not contribute material you lack permission to license.

## What reciprocity means

Distributing covered binaries requires access to the corresponding source under
the license. Section 13 also requires a source offer to remote users interacting
with a modified covered program. A source offer must match the version in use.

These obligations concern the covered work, not unrelated software or users'
private messages. A fork may charge money, compete with hush and share source
with its users without contributing upstream. The license does not protect an
idea from independent implementation or ban particular companies.

## Names and branding

The source-code license does not grant trademark rights. Refer accurately to
hush and preserve attribution, but do not imply that a modified or unofficial
release is endorsed by the project. This statement does not restrict the
copyright permissions granted by AGPL or claim ownership of third-party marks.

## Releasing a version

The license decision and a decision to publish are separate. Before a public
source or binary release:

1. Review ownership, imported code, dependencies, models and asset notices for
   that exact release. Keep original grants and required attribution.
2. Provide the corresponding source, build instructions, lockfiles and license
   notices alongside downloads. Identify the release revision; a moving `main`
   link is insufficient for a different binary.
3. Provide an accessible source link for the deployed covered web version.
   A private GitHub URL is not a public source offer. Retain required license
   notices in packaged apps and containers as well as in source archives.
4. Confirm that a source checkout builds with the user's own signing identity
   and infrastructure. Keep private signing keys, credentials, recordings and
   user data out of the source distribution.

The [licensing assessment](macos/docs/research/2026-11-10-open-source-licensing.md)
records the rationale, primary sources, specialist commentary and review limits.
This document explains the chosen scope; the license texts control permissions.
