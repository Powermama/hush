# Blog content

One Markdown file per published article: `en/<slug>.md` or `de/<slug>.md`.
English and German articles are separate programs with their own keywords; do
not translate articles.

## Write

Use the hush-seo skill (research with treg, outline, article). It writes new
articles with `draft: true`. The build contract (front matter fields, headings,
FAQ section, links, wording) is enforced by `scripts/blog/build-blog.ts`.

- **Author:** `author:` is an id from `shared/authors.ts` (for example
  `clemens-kressmann`). Name, bio and profile links live only there; bylines,
  feeds, the author page and the structured data are derived from it.
- **Images:** put screenshots in `<lang>/media/<slug>/` and reference them in a
  paragraph of their own: `![Alt text](media/<slug>/name.png "Optional caption")`.
  Alt text (10 to 160 characters) is required; images should be at least 680px
  wide. The build writes content-hashed WebP files to `public/blog/media/`.
  Crop away anything personal, such as account names in sidebars.

## Check and preview

```sh
bun run blog:generate   # validate and regenerate the committed output
bun run build && bun run serve:e2e
```

Drafts never appear in generated output. To preview one, set `draft: false`
locally, regenerate, and do not commit until it is approved.

## Publish

1. The author fact-checks the article, including title, description and alt text.
2. Set `draft: false`, run `bun run blog:generate`, and commit the article with
   the regenerated files in a focused pull request.
3. CI runs `blog:check`, the builds and the browser journeys. Merging deploys.

The generated files (`shared/blog-posts.generated.ts`,
`src/blog/generated/`, `public/**/blog/feed.xml`, `public/blog/media/`) are
never edited by hand.
