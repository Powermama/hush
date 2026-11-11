# hush repository guidance

- Write the product name as `hush`. Preserve case-sensitive code identifiers,
  Xcode targets and filenames.
- Read `CONTRIBUTING.md` and the nearest component `AGENTS.md` before editing.
- Keep changes on focused `feat/`, `fix/`, `docs/` or `chore/` branches. Use
  Conventional Commits and a pull request; do not rewrite published history.
- Use plain dashes, not em dashes. Do not add agent co-author trailers.
- Reproduce bugs through the affected user journey before fixing them.
- Update journey contracts and tests when observable behaviour changes.
- Do not hand-edit generated files or changelogs. Keep dependency lockfiles.
- Keep personal content, debug captures, credentials and signing keys out of Git.
- Run commands in the component directory unless documentation says otherwise.
- Never treat a passing build, secret scan or notarization as legal clearance.

`macos/` contains the native app; `webapp/` contains the website and proof service.
Both directories are part of this repository, not submodules.
