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
| CMS-ISOLATION-001 | The CMS imports nothing from the website and never reads the proof service's database URL or signing key. | `tests/boundary.test.ts` |

Images, the import of existing articles, the website reading published posts
and the admin UI arrive in later milestones of the CMS PRD.
