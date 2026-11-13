# CMS journeys

An owner or agent manages posts through the admin API with a bearer token.
Tokens carry scopes: `posts:read`, `posts:write` (drafts and edits) and
`posts:publish` (schedule, publish, unpublish). Responses are never indexed.

| ID | Journey | Test |
| --- | --- | --- |
| CMS-API-001 | Requests without a valid token get 401; a token without the needed scope gets 403 naming the scope. | `tests/posts.test.ts` |
| CMS-API-002 | A draft keeps every field and its secondary keywords in order; a second post with the same slug and language is refused with 409. | `tests/posts.test.ts` |
| CMS-API-003 | Publishing a post that breaks the article contract is refused with 422 and the contract's problems; the post stays a draft. | `tests/posts.test.ts` |
| CMS-API-004 | Publishing a valid post stores its rendered HTML (no H1, headings with ids) and a revision naming the token; a second live post targeting the same keyword is refused. | `tests/posts.test.ts` |
| CMS-API-005 | A post scheduled for the future is validated and rendered at once; the publish job publishes it only when due and exactly once, recorded as the scheduler. | `tests/posts.test.ts` |
| CMS-API-006 | Unpublishing returns a post to draft and removes its rendition; publishing it again keeps its original date. | `tests/posts.test.ts` |
| CMS-API-007 | Editing a live post re-validates it: an invalid edit is refused, a valid one is re-rendered. | `tests/posts.test.ts` |
| CMS-API-008 | Any earlier revision can be restored. | `tests/posts.test.ts` |
| CMS-MEDIA-001 | An article referencing `media/<slug>/<name>` cannot go live until that image is uploaded; once it is, the post renders a figure with responsive WebP sources (680 px and 2x) and the renditions exist in storage. | `tests/media.test.ts` |
| CMS-MEDIA-002 | Uploads are refused unless the name is lowercase with digits and dashes, the declared type matches the extension and the bytes decode as that image; files over 10 MB get 413. | `tests/media.test.ts` |
| CMS-IMPORT-001 | `bun run cms:import <dir>` imports hush-seo Markdown articles with their images, keeps drafts as drafts and publishes the rest with their original dates, in an order that satisfies links between them. | `tests/import.test.ts` |
| CMS-IMPORT-002 | Running the import again matches posts by language and slug and changes nothing but its revisions. | `tests/import.test.ts` |
| CMS-BACKUP-001 | A backup restores into a fresh database with every post, keyword and token intact. | `scripts/backup-drill.sh` (CI) |
| CMS-BACKUP-002 | Backups are named by time, listed newest first and kept for the configured days; the newest is never removed. | `tests/backups.test.ts` |
| CMS-SCHEDULER-001 | The scheduler publishes due posts every minute and takes a backup whenever the newest is a day old. | `src/jobs/scheduler.ts`, CMS-API-005 |
| CMS-ISOLATION-001 | The CMS imports nothing from the website and never reads the proof service's database URL or signing key. | `tests/boundary.test.ts` |

The import of the live article renders HTML byte-identical to the website's
static build. The website reading published posts and the admin UI arrive in
later milestones of the CMS PRD.
