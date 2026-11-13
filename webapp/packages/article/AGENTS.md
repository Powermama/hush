# @hush/article guidance

The article contract and renderer shared by the website and the CMS: front
matter schema, content rules, Markdown-to-HTML rendering, the author list and
the blog vocabulary (languages, clusters, article types, URL scheme).

- Keep `src/article.ts` free of file system and network access; callers pass
  images and the surrounding site through `ArticleContext`.
- `./authors` and `./taxonomy` are imported by browser code and must stay free
  of Node-only dependencies such as `sharp`.
- The rules mirror the hush-seo skill profile; change both together.
- Check with `bun run lint` here and the blog tests in `apps/web`.
