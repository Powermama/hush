# hush-cms

The command line for the [hush CMS](../cms/README.md): agents and scripts draft,
check, schedule and publish blog articles with it, through the same OpenAPI
operations the admin uses. Articles are Markdown files in the hush-seo format
(`<lang>/<slug>.md`, images in `<lang>/media/<slug>/`).

## Install

```sh
cd webapp/apps/cms-cli
bun run install:cli          # builds one binary into ~/.local/bin/hush-cms
hush-cms auth login          # paste a token; it goes to the macOS Keychain
hush-cms auth status
```

The owner creates tokens inside the CMS container with `bun run cms:token`.
`posts:publish` allows scheduling and publishing. `posts:write` allows drafts,
and today also edits to scheduled and published posts: the CMS does not yet
require the owner's approval for an agent's changes, so give agents no token
until it does (`--live` is only the CLI's own safeguard).

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
