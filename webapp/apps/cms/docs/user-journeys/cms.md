# CMS journeys

The owner signs in to the admin with GitHub; agents use the admin API with a bearer token.
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
| CMS-API-009 | A draft can start from any of the fields, also none: its texts may be empty or of any length, and the article contract applies only when it goes live. Without a slug it is named after its H1 ("untitled" until it has one), numbered when the language already has that slug; its image references follow a changed slug. | `tests/posts.test.ts` |
| CMS-API-010 | Saves sent with `autosave=true` by one author within ten minutes share a single revision holding their last state; a deliberate save, another author or a live post always gets a revision of its own. | `tests/posts.test.ts` |
| CMS-API-011 | A draft can be deleted with its history and images; a scheduled or published post is refused with 409 until it is unpublished. | `tests/posts.test.ts` |
| CMS-MEDIA-001 | An article referencing `media/<slug>/<name>` cannot go live until that image is uploaded; once it is, the post renders a figure with responsive WebP sources (680 px and 2x) and the renditions exist in storage. | `tests/media.test.ts` |
| CMS-MEDIA-002 | Uploads are refused unless the name is lowercase with digits and dashes, the declared type matches the extension and the bytes decode as that image; files over 10 MB get 413. | `tests/media.test.ts` |
| CMS-001 | The owner signs in with GitHub and sees every post with its author, topic, date and status, scheduled posts first, then drafts, then published ones; a menu sorts them, and the sidebar's views (on a phone, the sheet behind the bottom bar) filter Drafts, Scheduled and Published. | `tests/admin/admin.e2e.ts` |
| CMS-002 | An article opens in the block editor (title, excerpt, body) and a draft saves itself three seconds after its writer stops, written back as the same Markdown; Markdown shortcuts format as you type; the preview from the real renderer, in a frame that runs no scripts, shows the article with its images and lists what the article contract refuses; Cmd/Ctrl+S saves at once. | `tests/admin/admin.e2e.ts` |
| CMS-003 | Publishing now takes a valid draft live. | `tests/admin/admin.e2e.ts` |
| CMS-004 | Scheduling sets a future time; the post shows when it goes live. | `tests/admin/admin.e2e.ts` |
| CMS-005 | Unpublishing asks first, then returns the post to drafts. | `tests/admin/admin.e2e.ts` |
| CMS-006 | An earlier revision is restored from the post's history into the editor. | `tests/admin/admin.e2e.ts` |
| CMS-007 | A new post needs no form: its title, excerpt and body are typed straight in, the first save moves the address to the post while the editor stays open, the post is named after its title, and "/" offers the blocks of an article. | `tests/admin/admin.e2e.ts` |
| CMS-008 | An image is added through its card (picked or dropped): a new post is saved first, the picture shows in the card with a caption and alt text, and its reference moves with the post's address when the title arrives, so the contract finds it. | `tests/admin/admin.e2e.ts` |
| CMS-ADMIN-001 | Signing in sends the owner to GitHub with a random state and a PKCE challenge (S256, RFC 9700), both kept in `__Host-` cookies (HttpOnly, Secure, SameSite=Lax), and no OAuth scope; the callback needs the matching state and sends the verifier, then sets a session cookie with the same attributes, stored only as a hash. | `tests/admin.test.ts` |
| CMS-ADMIN-002 | A GitHub account whose numeric id is not on the allowlist gets no session (403). | `tests/admin.test.ts` |
| CMS-ADMIN-003 | A session acts as the owner (every scope) and revisions name `github:<login>`. | `tests/admin.test.ts` |
| CMS-ADMIN-004 | Sessions end after 12 hours without use and at the latest after seven days; signing out ends the session on the server and sends `Clear-Site-Data`; unsafe requests from another origin are refused (403). | `tests/admin.test.ts` |
| CMS-ADMIN-005 | The preview renders unsaved changes as the post would go live, lists the contract's problems and saves nothing. | `tests/admin.test.ts` |
| CMS-ADMIN-006 | The built admin is served on the CMS origin with an app fallback for its routes, never shadows `/v1`, `/auth` or `/health`, keeps paths inside its directory, and every response says `noindex` (plus `robots.txt` disallowing all). | `tests/admin.test.ts` |
| CMS-ADMIN-007 | Sign-in is configured completely (public HTTPS URL, numeric allowlist, OAuth client) or not at all; without it only bearer tokens work. | `tests/admin.test.ts` |
| CMS-IMPORT-001 | `bun run cms:import <dir>` imports hush-seo Markdown articles with their images, keeps drafts as drafts and publishes the rest with their original dates. | `tests/import.test.ts` |
| CMS-IMPORT-003 | Articles of one import may link to each other, also in a cycle: they are checked and published together. An article that fails the contract stays a draft, and so does every article linking to it, so no published article links to a missing page. | `tests/import.test.ts` |
| CMS-IMPORT-002 | Running the import again matches posts by language and slug; an unchanged article keeps its date, revisions and site revision. | `tests/import.test.ts` |
| CMS-SITE-001 | `GET /v1/site/export` (read scope) returns every published post as a hush-seo Markdown file with its image list and the site revision; each file parses back and renders to exactly the stored HTML, `GET /v1/media/{sha256}` returns the original image, and `GET /v1/site/revision` (public, never cached) returns the revision alone. | `tests/site.test.ts` |
| CMS-SITE-002 | Publishing, editing a live post, unpublishing and a scheduled post going live each take the next site revision, recording the article and its blog index; edits to drafts do not. | `tests/site.test.ts` |
| CMS-SITE-003 | When the live site serves an older revision, the scheduler asks Coolify for one forced website build (Coolify otherwise reuses the image of the current commit) per 20-minute window; once the site serves the revision, it submits every changed page to IndexNow exactly once. | `tests/site.test.ts` |
| CMS-SITE-004 | IndexNow rate limits and server errors are retried on the next tick; a refusal (such as a missing key file) is logged and not retried. | `tests/site.test.ts` |
| CMS-BACKUP-001 | A backup restores into a fresh database with every post, keyword and token intact. | `scripts/backup-drill.sh` (CI) |
| CMS-BACKUP-002 | Backups are named by time, listed newest first and kept for the configured days; the newest is never removed. | `tests/backups.test.ts` |
| CMS-SCHEDULER-001 | The scheduler publishes due posts every minute and takes a backup whenever the newest is a day old. | `src/jobs/scheduler.ts`, CMS-API-005 |
| CMS-ISOLATION-001 | The CMS imports nothing from the website and never reads the proof service's database URL or signing key. | `tests/boundary.test.ts` |

The import of the live article renders HTML byte-identical to the website's
static build. The website builds its blog from the export (M2); the admin
(`apps/cms-admin`, M3) runs the browser journeys CMS-001 to CMS-008 on desktop,
a phone and WebKit.
