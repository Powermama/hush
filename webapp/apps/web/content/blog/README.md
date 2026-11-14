# Blog content

Published articles live in the hush CMS (`webapp/apps/cms`), not in this
repository. Production builds the blog from the CMS at deploy time. This
directory only holds articles for local previews; Git ignores everything in it
except this file, so a draft never lands in the public repository.

English and German articles are separate programs with their own keywords; do
not translate articles.

## Write

Use the hush-seo skill (research with treg, outline, article). It writes
`<lang>/<slug>.md` with `draft: true`. The article contract (front matter
fields, headings, FAQ section, links, wording) lives in `@hush/article`; the
CMS and this build apply the same rules.

- **Author:** `author:` is an id from `@hush/article/authors` (for example
  `clemens-kressmann`). Name, bio and profile links live only there; bylines,
  feeds, the author page and the structured data are derived from it.
- **Images:** put screenshots in `<lang>/media/<slug>/` and reference them in a
  paragraph of their own: `![Alt text](media/<slug>/name.png "Optional caption")`.
  Alt text (10 to 160 characters) is required; images should be at least 680px
  wide. Crop away anything personal, such as account names in sidebars.

## Preview locally

Put the article in `<lang>/` here, set `draft: false`, then:

```sh
bun run dev                          # or: bun run build && bun run serve:e2e
```

`bun run blog:generate` validates the articles and rebuilds the blog output;
`dev`, `build`, `lint` and `test` run it first.

## Publish

1. The author fact-checks the article, including title, description and alt text.
2. Import it into the CMS: `bun run cms:import <dir>` in the `cms` container
   reads this layout (`<lang>/<slug>.md` plus `<lang>/media/<slug>/`), keeps
   drafts as drafts and publishes the rest. Through the API, create a draft,
   upload its images and publish or schedule it (`apps/cms/openapi/hush-cms.json`).
3. The CMS deploys the website on its own within minutes and tells search
   engines through IndexNow.

Until the CMS admin and CLI ship, the API is reachable only on the server.
