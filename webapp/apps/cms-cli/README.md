# hush-cms

The command line for the [hush CMS](../cms/README.md): agents and scripts draft,
check, schedule and publish blog articles with it, through the same OpenAPI
operations the admin uses. Articles are Markdown files in the hush-seo format
(`<lang>/<slug>.md`, images in `<lang>/media/<slug>/`).

## Install

```sh
cd webapp/apps/cms-cli
bun run install:cli          # builds one binary into ~/.local/bin/hush-cms
hush-cms auth login          # opens cms.behu.sh/device; approve the code, done
hush-cms auth status
```

`auth login` works like `gh auth login` (the OAuth 2.0 Device Authorization
Grant, RFC 8628): it shows a one-time code and opens the CMS, where the owner,
signed in with GitHub, checks the code and clicks Authorize. The CLI then
receives a 90-day token and keeps it in the macOS Keychain; it is never shown.
`auth login --with-token` reads one from stdin instead, for scripts, and
`auth logout` revokes it. A token is always an agent's: `posts:write` lets it work on drafts, and
`posts:publish` lets it schedule or publish a post once the owner has approved
it as it is now, in the admin. Any later change to the text or an image needs
a new approval. Only the owner changes or unpublishes a live post.

## Use

```sh
hush-cms posts push en/dictate-without-cloud.md   # draft plus images; reports the contract's problems
hush-cms posts check dictate-without-cloud        # exit 1 while the contract refuses it
hush-cms posts schedule dictate-without-cloud --at 2026-12-01T08:00Z
hush-cms posts list --status scheduled --json
hush-cms posts pull dictate-without-cloud --out content
```

`hush-cms --help` lists every command. `--json` prints the CMS's answers for
scripts; exit codes are 0 (done), 1 (refused or failed) and 2 (wrong usage).
`HUSH_CMS_URL` points at another CMS (default `https://cms.behu.sh`) and
`HUSH_CMS_TOKEN` overrides the stored token.

Licensed [AGPL-3.0-only](../../../LICENSE).
