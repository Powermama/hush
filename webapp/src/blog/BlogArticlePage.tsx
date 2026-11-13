// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { blogCopy, type BlogLanguage, type BlogPostMetadata } from "../../shared/blog";
import { blogPosts } from "../../shared/blog-posts.generated";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { Footer } from "../layout/Footer";
import { Header } from "../layout/Header";
import { BlogDownloadCard } from "./BlogDownloadCard";
import { useActiveSection } from "./useActiveSection";
import "./blog.css";

const dateFormat = (lang: BlogLanguage) => new Intl.DateTimeFormat(lang === "de" ? "de-DE" : "en-US", {
  year: "numeric", month: "long", day: "numeric", timeZone: "UTC",
});

export function BlogDate({ lang, value }: { lang: BlogLanguage; value: string }) {
  return <time dateTime={value}>{dateFormat(lang).format(new Date(`${value}T00:00:00Z`))}</time>;
}

function relatedPosts(post: BlogPostMetadata) {
  const others = blogPosts.filter((candidate) => candidate.lang === post.lang && candidate.slug !== post.slug);
  const sameCluster = others.filter((candidate) => candidate.cluster === post.cluster);
  return [...sameCluster, ...others.filter((candidate) => candidate.cluster !== post.cluster)].slice(0, 3);
}

/** A chevron that grows into a long arrow when its link is hovered. */
export function BlogArrow({ direction }: { direction: "back" | "forward" }) {
  return (
    <svg className={`blog-arrow blog-arrow-${direction}`} viewBox="0 0 16 16" aria-hidden="true">
      {direction === "back"
        ? <><path className="blog-arrow-shaft" d="M2 8h11" /><path className="blog-arrow-head" d="M6.5 3.5 2 8l4.5 4.5" /></>
        : <><path className="blog-arrow-shaft" d="M14 8H3" /><path className="blog-arrow-head" d="M9.5 3.5 14 8l-4.5 4.5" /></>}
    </svg>
  );
}

export function BlogHeader({ lang }: { lang: BlogLanguage }) {
  return <Header navigationLabel={lang === "de" ? "Blog-Navigation" : "Blog navigation"} />;
}

/** Rendered by each generated article module with its own HTML chunk. */
export function BlogArticlePage({ lang, slug, html }: { lang: BlogLanguage; slug: string; html: string }) {
  const post = blogPosts.find((candidate) => candidate.lang === lang && candidate.slug === slug);
  if (!post) throw new Error(`Unknown blog article ${lang}/${slug}`);
  const copy = blogCopy[lang];
  const related = relatedPosts(post);
  const active = useActiveSection(post.toc.map((entry) => entry.id));
  const toc = post.toc.length > 1 && (
    <nav aria-label={copy.onThisPage} className="blog-toc">
      <p className="blog-toc-title">{copy.onThisPage}</p>
      <ol>
        {post.toc.map((entry) => (
          <li key={entry.id}>
            <a href={`#${entry.id}`} aria-current={entry.id === active ? "location" : undefined}>{entry.text}</a>
          </li>
        ))}
      </ol>
    </nav>
  );

  return (
    <div className="min-h-screen bg-canvas text-ink" lang={lang}>
      <DocumentMetadata title={post.title} description={post.description} canonicalPath={post.path} language={lang} />
      <BlogHeader lang={lang} />
      <main className="blog-article-main">
        <article className="blog-article" aria-labelledby="article-title">
          <header className="blog-article-header">
            <a className="blog-back" href={copy.indexPath}><BlogArrow direction="back" />{copy.allArticles}</a>
            <h1 id="article-title">{post.heading}</h1>
            <p className="blog-byline">
              <span>{copy.by} <a href={post.authorUrl} rel="author">{post.author}</a></span>
              <span>
                {post.updated !== post.published
                  ? <>{copy.updated} <BlogDate lang={lang} value={post.updated} /></>
                  : <>{copy.published} <BlogDate lang={lang} value={post.published} /></>}
              </span>
              <span>{copy.readingTime(post.readingMinutes)}</span>
            </p>
          </header>
          {toc && <details className="blog-toc-mobile"><summary>{copy.onThisPage}</summary>{toc}</details>}
          <div className="blog-article-layout">
            <div className="blog-prose" data-blog-body="" dangerouslySetInnerHTML={{ __html: html }} />
            {toc && <aside className="blog-toc-desktop">{toc}</aside>}
          </div>
          <BlogDownloadCard lang={lang} />
        </article>
        {related.length > 0 && (
          <section className="blog-related" aria-labelledby="blog-related-title">
            <h2 id="blog-related-title">{copy.related}</h2>
            <ul>
              {related.map((item) => (
                <li key={item.slug}>
                  <a href={item.path}>
                    <span className="blog-related-title">{item.heading}</span>
                    <span className="blog-related-description">{item.description}</span>
                    <span className="blog-related-more">{copy.readArticle}<BlogArrow direction="forward" /></span>
                  </a>
                </li>
              ))}
            </ul>
          </section>
        )}
      </main>
      <Footer />
    </div>
  );
}
