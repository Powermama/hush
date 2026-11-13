<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (c) 2026 Clemens Kressmann -->

# CI checks the components a change can affect

Ready pull requests and pushes to `main` run checks selected from the complete
Git diff. Draft pull requests do not allocate product build runners. Marking a
draft ready starts its checks; converting it back to a draft cancels older work.
Manual workflow runs always check both components.

| Change | Web journeys | Swift package and service integration | Native Release build |
| --- | --- | --- | --- |
| Website UI, assets, legal contact or browser tests | Yes | No | No |
| Proof service, shared proof contracts, OpenAPI or web dependencies | Yes | Yes | No |
| Native source, resources, packages or build scripts | No | Yes | Yes |
| Both components | Yes | Yes | Yes |
| Documentation, licenses or issue forms only | No | No | No |
| CI configuration, an unknown root component or an unavailable comparison | Yes | Yes | Yes |

Component selection itself has tests, including real Git histories with
multi-commit pushes, divergent PR branches, renamed/deleted files and rewritten
base commits. It uses Git instead of a file-list API with a pagination cap.
Unrecognized events and unavailable comparisons run the full suite. A failed
selection step cannot produce a passing aggregate check.

Use **CI result** as the required CI status when repository protection is
available. It accepts only successful selected jobs and skipped unaffected jobs.
It fails if selection fails or a selected job fails, is cancelled or skips.
Keep **Conventional title** as the other required check. Workflow concurrency
cancels obsolete runs for the same PR or branch.

## Coverage and resource choices

Web changes run three kinds of jobs in parallel. **Web checks** runs the
dependency audit, the blog output check, backend tests against PostgreSQL, API
drift detection, the production build and the image build. **Web journeys**
runs every Chromium desktop/mobile and WebKit journey, split across three
machines with [Playwright sharding](https://playwright.dev/docs/test-sharding);
`fullyParallel` splits by test, so each shard gets a third. **Blog journeys**
builds with the fixture articles and runs the blog journeys. Nothing is
selected away inside the website: a shared style or layout can break any
journey, so every web change runs all of them, only faster.

Whenever web journeys run, the **Zero-downtime deployment** job also runs
`webapp/apps/web/scripts/rolling-update-e2e.ts`: it builds the production image
and replaces the web service twice under continuous load behind Traefik with a
separate PostgreSQL, failing on any dropped request or changed signing key.
**CI result** requires every one of these jobs. Run `bun run lint` locally for a
type-check-only pass. Swift and native build commands remain pinned to the
existing toolchain and package lockfiles.

Service-only changes still exercise the real Swift client against the local
Hono service on macOS, but do not compile the unrelated desktop app. Native
changes retain both Swift tests and the unsigned Release compilation.

Each Playwright shard keeps one CI worker and its global timeout. Increasing
concurrency on one machine previously caused contention in software-rendered
WebGL tests; sharding adds machines instead. Its official
[CI guidance](https://playwright.dev/docs/ci) recommends one worker for stability
and does not recommend caching browser binaries by default. In the sampled run,
installing web dependencies took one second and browser setup took 43 seconds;
adding broad caches would not address the dominant cost. No DerivedData cache
is trusted as a replacement for a clean native compilation.

Dependabot groups weekly GitHub Actions updates into one PR. Existing PRs keep
their own review histories; the grouping applies to future updates.

## Cost evidence and limits

The successful website-only PR #9 run, before the history cleanup, took
9m 26s on macOS and 8m 40s on Linux. At GitHub's published standard rates
($0.062/min macOS and $0.006/min Linux, rounded up per job), those jobs represented
about $0.62 and $0.054 of gross usage respectively. These are usage estimates,
not invoices; included usage and public-repository discounts may cover them.

Removing the unrelated Mac job from an equivalent website change is expected
to reduce its compute usage by roughly 90%, including the two small Linux
selection/result jobs. This is an estimate from the old run, not a measured
post-change bill. Overall savings depend on the mix of native and web work.
The `main` push check intentionally remains, to validate the merged code.

Sources consulted:

- [GitHub runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)
- [GitHub job conditions and skipped checks](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions)
- [iOS developers discussing runner costs](https://www.reddit.com/r/iOSProgramming/comments/1wwt739/ios_teams_on_github_actions_what_do_macos_runners/)
- [Community experiences with frequent AI-assisted CI runs](https://www.reddit.com/r/ChatGPTCoding/comments/1xd9yqp/github_actions_getting_really_expensive_any/)

The Reddit discussions are anecdotal. They informed the questions to investigate;
the decisions above use hush's job timings and official tool documentation.
Changing providers or adding self-hosted machines is a separate infrastructure
decision. This workflow does not change account budgets, paid runner tiers or
repository visibility.
