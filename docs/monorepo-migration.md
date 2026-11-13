# hush monorepo migration

## Public repository baseline - 11 November 2026

The public `Powermama/hush` repository starts with one commit,
`chore: initialize hush monorepo`. It contains the reviewed current file tree,
including the public correspondence address, component-scoped CI and GitHub
Actions upgrades. It does not import the former repository's Git history,
pull requests, Actions artifacts or cached commit references.

The former monorepo is retained privately as `Powermama/hush-private-history`.
Its open PRs were merged before the snapshot was taken. The earlier component
repositories also remain private. These archives must not be made public as a
shortcut: old PR references may retain personal information even after branch
history was sanitized.

This new Git root does not change copyright, previously granted MIT permissions,
third-party licenses, application behavior or the published binary downloads.
Licenses, credits, lockfiles and contribution instructions are retained. The
initial source tree is a new development baseline, not a claim that it exactly
matches every previously published binary. Future releases must identify their
corresponding source revision.

Existing clones must use a fresh clone of the public repository. Do not merge
old history into it. The repository name remains `hush`, but its GitHub identity
is new; recheck GitHub App access and deployment integration accordingly.

The website uses the existing Coolify resource and its persistent data. Source
migration does not authorize a new deployment or establish that the contact
address service has been activated.


## Earlier private import - 10 November 2026

On 10 November 2026, the current native app and website were imported into a
new repository. The component directories remain `macos/` and `webapp/`, so
Xcode paths, package references, Vite and local development paths stay familiar.
They are ordinary directories, not submodules.

The earlier private history began with two baseline commits. Its branch history
was subsequently sanitized to remove a residential address. The public baseline
described above supersedes that history while keeping the current files.

| Component | Original revision | Imported Git tree |
| --- | --- | --- |
| Native app | `f0595ed10e8ae19e0c3c0c605cd1a97d48fa0f0f` | `33ba355c9d8878bbd77b9426b5613b19ff075531` |
| Website and service | `4d3e4569fde3e9f00c13008c32b7a3ac4dcb0e60` | `9e948f1b01d562911bebfe40e236b333fcb5487b` |

The imported trees were compared by Git object ID and matched exactly before
the monorepo documentation, CI and repository-link changes. No application
behaviour was intentionally changed by the import.

Both original histories are retained in the private repositories
`Powermama/hush-macos` and `Powermama/hush-web`. Verified local Git bundles and
the original Git metadata are also retained outside the tracked tree. These
backups must remain private until their contents and rights are cleared.

Future work follows [CONTRIBUTING.md](../CONTRIBUTING.md): focused branches,
Conventional Commit PR titles, CI and squash merges. Published release tags and
download artifacts remain unchanged.

## Website deployment cutover

A repository import does not itself switch the production deployment. Coolify
must resolve the intended repository identity and approved branch before the
next deployment. Retain the existing resource, data and signing key.

1. Back up the existing PostgreSQL data, proof-object volume and signing key.
2. Keep the existing Coolify resource, domain, environment and persistent volume
   identities. Changing repositories must not create a fresh proof database or key.
3. Give the existing Git integration access to `Powermama/hush`.
4. Select the repository and `main`, with Base Directory `/webapp` and Docker
   Compose Location `/docker-compose.coolify.yaml`. Confirm the resolved
   build context is `webapp/`, where the Dockerfile and lockfile live.
5. Review the generated Compose configuration before deploying. Volume names
   must resolve to the existing production volumes, not new empty ones.
6. Deploy, then check `/health/live`, `/health/ready`, the landing page, a known
   private proof in its recipient's browser and the immutable download link.
   Never paste a real proof key into build logs or monitoring.
7. Keep the old source configuration available for rollback. Only archive the
   old repositories after the new deployment and release workflow are validated.

The [deployment guide](../webapp/apps/web/docs/operations/coolify-deployment.md) describes
service operation. A local equivalent is:

```sh
docker compose -f webapp/compose.yaml up --build
```

## Licensing and future releases

The monorepo's license decision is **AGPL-3.0-only**, recorded in
[LICENSING.md](../LICENSING.md). The native MIT notice has not been removed or replaced, and earlier MIT
permissions remain valid. Dependency, model and
artwork licenses remain separate. The
[licensing assessment](../macos/docs/research/2026-11-10-open-source-licensing.md)
records the evidence and outstanding provenance and release checks. No history
rewrite is needed to adopt the license, and rewriting history would not change
earlier grants or ownership.

The old histories were scanned with Gitleaks 8.30.1. Website history had no
findings. The native findings were reviewed as asset checksums and a Swift key
type declaration, not embedded credentials. A scanner result does not establish
that every file is safe to publish or that all rights are cleared. Review the
actual public tree, notices, fixtures and release-source correspondence before
changing repository visibility.
