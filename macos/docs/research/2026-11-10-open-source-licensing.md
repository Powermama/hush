# hush licensing research

Reviewed 10 November 2026; decision adopted later the same day at the owner's
request. This research is not itself a license grant or legal opinion. The
operative grant and scope are in [LICENSE](../../../LICENSE) and
[LICENSING.md](../../../LICENSING.md). Existing MIT, dependency, model and asset
grants remain in force. The owner requested one repository for the macOS app and
web service, community remixing, and reciprocity for covered derivatives.

## Adopted decision

Use the unmodified GNU AGPL version 3 for hush-owned application and service code
and documentation, with the explicit SPDX identifier **AGPL-3.0-only**. This
limits the grant to the reviewed version. `AGPL-3.0-or-later` would additionally
let recipients choose future FSF versions; that option was not selected.

Keep third-party notices and separately licensed artwork, model weights and
dependencies. Document branding separately so forks can identify their origin
without implying they are official hush releases. Do not invent a license or add
a restriction against particular companies to an open-source license.

This is a fit to the owner's stated preference for reciprocity, not a finding
that AGPL maximizes adoption or makes a project immune to competition.

The original native MIT notice is preserved byte for byte. Its earlier
permissions cannot be withdrawn through this change or a Git rebase. No claim
is made that Vlr is the current owner's alias, or that the project owns another
contributor's work. Keeping the permissive grant and documenting covered new
contributions avoids relying on that unconfirmed assumption. Provenance and
release-artifact review are still required before publication.

## Implementation cross-check

The following sources were checked again when applying the decision:

- [SPDX AGPL-3.0-only](https://spdx.org/licenses/AGPL-3.0-only.html)
  distinguishes version 3 only from the later-version option. The root license
  was downloaded unchanged from the FSF; scope and the version choice are in
  a separate document, rather than edits to the license text.
- [SFLC's permissive-code guidance](https://softwarefreedom.org/resources/2007/gpl-non-gpl-collaboration.html)
  supports retaining original notices when permissive code is incorporated
  into a copyleft project, and distinguishing newly copyrighted changes.
  Its age is explicit: this is 2007 guidance, not a new legal opinion on hush.
- [The MIT terms](https://opensource.org/license/mit) permit reuse and
  sublicensing while requiring preservation of the notice. Our native baseline
  is identified by revision; we do not present later AGPL contributions as MIT.
- [Heather Meeker's AGPL analysis](https://fossa.com/blog/oss-license-compliance-expert-heather-meeker-agpl/)
  distinguishes distribution obligations from section 13's modified-network
  trigger. We do not say that all commercial use or unrelated company software
  must be published, or that a fork must contribute upstream.
- [GitHub's legal guide](https://opensource.guide/legal/)
  distinguishes adopting compatible terms for new releases from changing the
  rights in existing contributions. A history rewrite is not a rights transfer.
  Its preference for standard terms also supports avoiding a custom company ban.

This implementation uses an unmodified standard license, explicit scope,
contributor retention of copyright, and preserved exceptions. It introduces no
copyright assignment, custom noncommercial restriction or dual-license promise.
These sources are primary license texts and specialist guidance; the articles
are not represented as peer-reviewed legal clearance.

## What the choices actually do

| Choice | Redistribution and modifications | Modified hosted service | Fit for hush's stated goal |
| --- | --- | --- | --- |
| MIT / Apache-2.0 | Permit proprietary derivatives, with applicable notices and other conditions | No general source-sharing obligation | Good for permissive reuse; weaker reciprocity than requested |
| MPL-2.0 | Requires source for covered files when distributed; permits larger works with differently licensed files | Hosting alone does not trigger its distribution obligations | A middle ground if proprietary integration is welcome |
| GPLv3 | Requires corresponding source for covered distributed works | Running a modified server alone does not trigger the same source-delivery obligation | Strong desktop reciprocity, less coverage for hosted derivatives |
| AGPLv3 | Strong copyleft for covered distributed works | Section 13 requires an offer of corresponding source to remote users of a modified version | Best match across the native app and proof service |
| Noncommercial / company restrictions | Depends on the exact terms | Depends on the exact terms | Source available, not OSI open source |

The boundaries of a covered derivative work require factual analysis. Putting
independent programs in one Git repository does not by itself turn them into a
single derived program. AGPL does not require a company to publish unrelated
software, its customer data, private messages or operational credentials.

Companies can sell compliant forks. Recipients need access to corresponding
source under the applicable conditions; they do not have to submit a pull request
upstream. Copyright licensing does not prohibit independent implementation of
the same idea. Prior copies legitimately received under MIT keep their MIT
permissions; changing future terms does not retroactively revoke those grants.

Sources: [MIT terms](https://opensource.org/license/mit),
[Apache-2.0 terms](https://www.apache.org/licenses/LICENSE-2.0),
[Mozilla MPL FAQ](https://www.mozilla.org/en-US/MPL/2.0/FAQ/),
[GNU's explanation of Affero](https://www.gnu.org/licenses/why-affero-gpl.html),
[OSI open-source definition](https://opensource.org/osd),
[WIPO copyright guidance](https://www.wipo.int/en/web/copyright), and
[GNU FAQ on copyright holders and licensing](https://www.gnu.org/licenses/gpl-faq.en.html).

## Evidence and its limits

### License text and standards

[AGPLv3, sections 6, 13 and 14](https://opensource.org/license/agpl-3.0)
are the controlling license provisions for distribution, remote interaction
and version selection. The license is OSI approved. OSI's definition allows
commercial use; a ban on corporations is incompatible with that definition.
These sources establish terms and classification, not clearance of hush's code.

### Apple

[Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
describes an automated malware and code-signing check, distinct from App Review.
[Developer ID guidance](https://developer.apple.com/developer-id/)
describes direct Mac distribution. Neither is a copyright or license audit.

The practical distribution path remains Developer ID signing, hardened runtime,
notarization and a tested download. Provide the corresponding source and license
notices alongside the release. Apple does not select AGPL for hush, and a
notarization ticket must not be presented as Apple's approval of our licensing.
Any future Mac App Store release needs its own terms review; this recommendation
covers the current directly distributed Mac app and separately deployed website.

### Specialist lawyers

- [Heather Meeker, *OSS License Compliance Expert Heather Meeker on the AGPL*
  (2022)](https://fossa.com/blog/oss-license-compliance-expert-heather-meeker-agpl/)
  explains section 13's two triggers: modification and remote network use. She
  distinguishes corresponding source from arbitrary company software. Her
  article also identifies uncertainties around particular architectures. This
  is a lawyer's published analysis, not a peer-reviewed paper or advice to hush.
- [Eben Moglen and Mishi Choudhary, *SFLC Guide to GPL Compliance*, second edition
  (2014)](https://softwarefreedom.org/resources/2014/SFLC-Guide_to_GPL_Compliance_2d_ed.html)
  covers the GPL family, including AGPL. It supports tracking exact source and
  build materials for each released binary and implementing an accessible
  source offer for modified network software. It is specialist legal guidance,
  not a jurisdiction-specific clearance letter. The publication is older; the
  current license text remains the primary reference.

### Peer-reviewed research

- Wu et al., *A Large-Scale Empirical Study of Open Source License Usage:
  Practices and Challenges*, MSR 2024, pp. 595-606,
  [DOI 10.1145/3643991.3644900](https://doi.org/10.1145/3643991.3644900).
  The study examines package license naming, incompatibility and evolution
  across five ecosystems. Its practical implication here is to use standard
  identifiers and review dependencies, rather than assume a root LICENSE clears
  everything. The [conference record](https://2024.msrconf.org/details/msr-2024-technical-papers/5/A-Large-Scale-Empirical-Study-of-Open-Source-License-Usage-Practices-and-Challenges)
  and [technical-track review policy](https://2024.msrconf.org/track/msr-2024-technical-papers)
  establish the reviewed venue. Automated incompatibility findings are not court
  judgments and cannot certify hush.
- Lerner and Tirole, *The Scope of Open Source Licensing*, Journal of Law,
  Economics, and Organization 21(1), 2005, pp. 20-56,
  [DOI 10.1093/jleo/ewi002](https://doi.org/10.1093/jleo/ewi002).
  The published abstract reports associations between license choice, project
  audience and contributions in historical SourceForge data. It warns against
  treating the founder's preferences as the only community consideration.
  These are old observational results, not causal evidence that AGPL will help
  or hurt hush. The study predates AGPLv3 and cannot validate that license's
  present legal effect. Only the published abstract was consulted here.

No cited study proves a best license for this product, and none guarantees legal
compliance. A qualified open-source lawyer should review the ownership chain,
dependency exceptions and distribution terms before public distribution.

## Findings in this checkout

| Material | Observed state | Required treatment |
| --- | --- | --- |
| Native source | `macos/LICENSE` says MIT, copyright 2026 Vlr, unchanged since initial commit `01711c1` | Preserve the baseline grant and attribution. Review provenance without assuming Vlr is the current owner. The new policy does not revoke existing MIT rights |
| Native history | All recorded author names are Powermama | A Git author name is not proof of copyright ownership or permission to relicense |
| Native packages | All 29 cached Swift checkouts match the pinned revisions. Root license texts identify MIT or Apache-2.0 families | Preliminary inventory only. Check full texts, Swift exceptions and bundled subcomponents, including Sparkle and native MLX components, for the actual release |
| Website packages | All 14 direct runtime and 12 direct development packages match the manifest. Metadata reports MIT, Apache-2.0, BSD-3-Clause, Unlicense or CC0 | Metadata is an inventory aid, not final license verification. Review transitive packages and distributed notices |
| Website source | No standalone repository license was found before this decision | Root LICENSE and LICENSING.md now cover original website/service code; package metadata declares AGPL-3.0-only |
| Website artwork | `public/art/CREDITS.md` records public-domain, CC0, CC BY-SA 3.0 and CC BY-SA 4.0 material | Keep the separate licenses, sources, attribution and adaptation notices. Do not label all assets AGPL |
| AI models | Native app includes bundled Whisper assets and downloads other models | Audit exact model distributions and conversion notices separately; a runtime package license does not license its weights |
| Reference repos | Research notes say orchestration implementations were studied without copying them | Check actual copied material, if any, including landing-page source and artwork; a research note alone is insufficient provenance |

This is not yet a complete transitive dependency, code provenance, model-weight
or release-artifact audit. The owner-authorized license change is separate from
this report. Neither it nor this report certifies legal clearance or changes
repository visibility.

## Implementation and release follow-through

1. **Implemented:** Record the AGPL-3.0-only decision and scope in LICENSING.md.
   Retain original copyright and license notices for inherited material.
2. **Implemented:** Add the unmodified FSF license at the monorepo root, with
   matching README and package metadata. Keep asset terms separate.
3. **Implemented:** Use AGPL-3.0-only for original contributions, with authors
   retaining copyright. Do not require an assignment or promise dual licensing.
4. Produce an inventory from both lockfiles and bundled model/assets. Include the
   required notices in source and distributable artifacts.
5. Link each app release and running web version to its exact source revision and
   build instructions. A changing link to `main` is insufficient for an older
   binary; a private repo link is not an effective public source offer.
6. Verify the source archive can build without private keys, accounts or hidden
   files. Signing and deployment credentials stay private; document how a fork
   uses its own signing identity and infrastructure.
7. Review history for secrets and private development captures before changing
   visibility. A clean current tree does not sanitize old commits.

The license is selected; the remaining release review continues privately. Keep
the existing production repositories available until deployment, update URLs and
release-source continuity have been verified. Earlier shipped versions retain
their existing terms; do not relabel or replace their immutable artifacts.
