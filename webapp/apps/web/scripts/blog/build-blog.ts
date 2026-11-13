// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
//
// Builds the static blog from a content directory: reads every Markdown article,
// applies the rules that span articles (unique slugs and keywords, links between
// them) and leaves each article's contract and rendering to @hush/article. Pure
// apart from reading the content directory, so it can be tested against
// fixtures. The writer lives in generate-blog.ts.
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { parseArticle, renderArticle, type ArticleContext, type BlogPost, type ParsedArticle } from "@hush/article";
import { authorPath } from "@hush/article/authors";
import { blogLanguages, blogPath, editorialPolicyPath } from "@hush/article/taxonomy";

export const coverTemplatePath = join(import.meta.dir, "cover-template.html");

export type BuildResult = { posts: BlogPost[]; errors: string[] };

/**
 * @param contentDir directory with one subdirectory per language (en, de)
 * @param staticPaths existing non-blog site paths that articles may link to
 */
export async function buildBlog(contentDir: string, staticPaths: Iterable<string>): Promise<BuildResult> {
  const errors: string[] = [];
  const coverSeed = [
    await readFile(coverTemplatePath, "utf8"),
    await readFile(join(import.meta.dir, "render-covers.ts"), "utf8"),
  ];
  const parsed: Array<{ file: string; article: ParsedArticle }> = [];

  for (const lang of blogLanguages) {
    let files: string[] = [];
    try {
      files = (await readdir(join(contentDir, lang))).filter((file) => file.endsWith(".md")).sort();
    } catch {
      continue;
    }
    for (const file of files) {
      const where = `${lang}/${file}`;
      let source: string;
      try {
        source = await readFile(join(contentDir, lang, file), "utf8");
      } catch (error) {
        errors.push(`${where}: cannot read (${(error as Error).message})`);
        continue;
      }
      const { article, problems } = parseArticle(source);
      if (!article) {
        errors.push(...problems.map((problem) => `${where}: ${problem}`));
        continue;
      }
      const { front } = article;
      if (front.lang !== lang) errors.push(`${where}: lang "${front.lang}" does not match its folder "${lang}"`);
      if (file !== `${front.slug}.md`) errors.push(`${where}: file name must be ${front.slug}.md`);
      if (front.draft) continue;
      parsed.push({ file: where, article });
    }
  }

  // Paths each language may link to: its own published articles and index,
  // plus the existing site pages.
  const knownPaths = new Set(staticPaths);
  for (const { article: { front } } of parsed) {
    knownPaths.add(blogPath(front.lang, front.slug));
    knownPaths.add(blogPath(front.lang));
    knownPaths.add(authorPath(front.lang, front.author));
    knownPaths.add(editorialPolicyPath(front.lang));
  }

  const keywords = new Map<string, string>();
  const slugs = new Map<string, string>();
  const posts: BlogPost[] = [];

  for (const { file, article } of parsed) {
    const { front } = article;
    const problems: string[] = [];
    const slugKey = `${front.lang}:${front.slug}`;
    if (slugs.has(slugKey)) problems.push(`slug already used by ${slugs.get(slugKey)}`);
    slugs.set(slugKey, file);
    const keywordKey = `${front.lang}:${front.keyword.toLowerCase().trim()}`;
    if (keywords.has(keywordKey)) problems.push(`keyword "${front.keyword}" already targeted by ${keywords.get(keywordKey)}`);
    keywords.set(keywordKey, file);

    const context: ArticleContext = {
      knownPaths,
      coverSeed,
      async loadImage(url) {
        const source = join(contentDir, front.lang, url);
        try { return { bytes: await readFile(source), source }; } catch { return undefined; }
      },
    };
    const rendered = await renderArticle(article, context);
    problems.push(...rendered.problems);
    if (problems.length || !rendered.post) {
      errors.push(...problems.map((problem) => `${file}: ${problem}`));
      continue;
    }
    posts.push(rendered.post);
  }

  posts.sort((a, b) => b.published.localeCompare(a.published) || a.slug.localeCompare(b.slug));
  return { posts, errors };
}
