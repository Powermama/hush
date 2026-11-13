# Blog

The blog publishes English and German articles as two independent programs:
each article targets its own market's keywords, and no article is a
translation of another. Articles are Markdown files in `content/blog/<lang>/`,
written with the hush-seo skill and reviewed by the author before publishing.

## Journeys

| ID | Journey | Test |
| --- | --- | --- |
| BLOG-001 | Read a prerendered article without JavaScript: one H1, the full body, `og:type article` and `BlogPosting` data with timezone-qualified dates and the author as a `Person` identified by their author page. | `tests/blog.spec.ts` BLOG-001 |
| BLOG-002 | The article hydrates without console or page errors and stays visible. | BLOG-002 |
| BLOG-003 | Desktop gets the real download; phones and iPads get the "Get hush for Mac" handoff and never a disk image (LANDING-DOWNLOAD-002). | BLOG-003 |
| BLOG-004 | Jump through the table of contents (collapsed on phones, beside the opening on wide screens, highlighting the section being read) and continue to a related article from the same cluster. | BLOG-004 |
| BLOG-005 | Each language lists only its own published articles. Drafts and unknown slugs return 404; the sitemap and the Atom feed list published articles only. | BLOG-005 |
| BLOG-006 | No horizontal page scrolling (tables scroll in their own box) and no runtime CSS or SVG filters (LANDING-PAINT-001). | BLOG-006 |
| BLOG-007 | The byline leads to the prerendered author page (`/authors/<id>`, `/de/autoren/<id>`) with `og:type profile`, `ProfilePage` data whose `Person` lists the author's profiles as `sameAs`, and the author's articles in that language. | BLOG-007 |
| BLOG-008 | Guides have a contents and sharing margin on wide screens; essays use one reading column with sharing at the end. | BLOG-008 |
| BLOG-009 | Each article has a content-versioned 1200x630 PNG shared by Open Graph, Twitter and `BlogPosting` metadata. This artwork appears only in link previews, with no article hero or listing thumbnails. | BLOG-009 |
| BLOG-010 | Responsive article figures include a labelled full-size image link that opens in a new tab, including on phones. | BLOG-010 |
| BLOG-011 | The entire author card, including its padding, opens the author profile. | BLOG-011 |
| BLOG-012 | Scrolling between sections updates the contents highlight without clearing selected article text or replacing its figures. | BLOG-012 |

The browser tests run in CI against fixture articles in
`scripts/blog/fixtures/content`, generated only inside the CI job. With the
committed content they skip, so they never depend on real articles.

## Guarantees

- `/blog` and `/de/blog` exist only when that language has a published article,
  so an empty blog is never served or indexed. The footer links to the English
  blog once it exists.
- `bun run blog:check` fails when the committed generated files are stale.
- All missing article images and social previews are prepared before metadata,
  routes or feeds change. A failed conversion or browser launch preserves the
  previous output, covered by `scripts/blog/generate-blog.test.ts`.
  `scripts/blog/build-blog.test.ts` covers validation: strict front matter
  fields and lengths, one H1 and ordered headings, the FAQ section per language,
  em dashes and banned phrases, raw HTML, unsafe link schemes, dead or
  cross-language internal links, duplicate keywords per language and drafts.
