# Repository security settings

GitHub stores these settings outside Git. Keep them in place when changing the
repository, adding maintainers, or moving it to an organization.

| Setting | Required state |
| --- | --- |
| Production branch | `main`, changed through pull requests |
| Required checks | `CI result` and `Conventional title`, up to date with `main` |
| Administrator bypass | Branch protection applies to administrators |
| History | Squash merges, linear history, no force pushes or branch deletion |
| Review threads | Resolved before merge |
| Secret scanning and push protection | Enabled |
| Private vulnerability reporting | Enabled; see [the reporting policy](../../SECURITY.md) |
| Dependabot alerts | Enabled |
| Dependabot security updates | Enabled; review and test each proposed fix |
| CodeQL | Default setup, high-precision default queries, standard runners; Actions, JavaScript/TypeScript, Python and Swift |
| Default workflow token | Read-only; cannot approve pull requests |
| Fork workflows | Maintainer approval for first-time contributors |
| Third-party Actions | Pinned to full commit SHAs in workflows |

The current solo-maintainer setup requires pull requests and checks but does not
require another person's approval. Revisit that choice when additional
maintainers join. A green build or enabled scanner is not a security audit.

## Verify settings

An administrator can inspect the live state without changing it:

```sh
gh api repos/Powermama/hush/branches/main/protection
gh api repos/Powermama/hush/private-vulnerability-reporting
gh api repos/Powermama/hush/vulnerability-alerts --silent
gh api repos/Powermama/hush/automated-security-fixes
gh api repos/Powermama/hush/actions/permissions/workflow
gh api repos/Powermama/hush/actions/permissions/fork-pr-contributor-approval
gh api repos/Powermama/hush/code-scanning/default-setup
```

The vulnerability-alerts check succeeds with an empty response when enabled.
Review the Security tab after activation: existing dependencies are scanned too.
Prioritize affected runtime dependencies and high-severity findings, distinguish
development tools from shipped code, and keep fixes in focused PRs. Security
updates do not automatically merge or deploy.

## CodeQL scanning

CodeQL default setup is managed by GitHub, outside the repository. It was
activated on 11 November 2026 with the default query suite, the remote threat
model and standard GitHub-hosted runners. The selected languages are `actions`,
`javascript-typescript`, `python` and `swift`. Inspect the returned configuration
and the latest analysis jobs to confirm actual coverage, rather than treating
an enabled toggle as a successful scan.

GitHub manages its pull-request, protected/default-branch and scheduled scans.
Do not add a duplicate CodeQL workflow while default setup is active. If Swift
autobuild cannot build the Xcode project, use advanced setup with an explicit
unsigned, single-architecture build and the pinned native toolchain. Keep that
change in its own reviewed PR, and verify every language still reports results.

Standard GitHub-hosted runner compute is free for public repositories such as
this one. Larger runners and storage have different billing rules; this setup
does not select a paid larger runner or enable AI Scan. CodeQL analyses source
code, while Dependabot and the web dependency audit check dependency advisories.
Review findings and verify fixes; none of these tools proves the absence of
vulnerabilities.

Sources: [default setup](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/configure-code-scanning/configure-code-scanning),
[Swift build requirements](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages),
and [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

Keep account recovery codes offline, use two-factor authentication, and review
public profile and commit-email visibility before promoting the project. Never
commit tokens, recovery codes, or private reports to record this configuration.

References: [GitHub repository security](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-security-and-analysis-settings-for-your-repository),
[Actions permissions](https://docs.github.com/en/rest/actions/permissions), and
[private reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository).
