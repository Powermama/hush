// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { useMemo } from "react";
import { authorPath, blogAuthors, type BlogAuthor, type BlogAuthorId } from "../../shared/authors";
import { blogCopy, type BlogLanguage, type BlogPostMetadata } from "../../shared/blog";
import { blogPosts } from "../../shared/blog-posts.generated";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { Footer } from "../layout/Footer";
import { Header } from "../layout/Header";
import { BlogDownloadBand } from "./BlogDownloadBand";
import { BlogPostList } from "./BlogIndexPage";
import { BlogShare } from "./BlogShare";
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

/** The author again after the article, as the best-read blogs do: who wrote it and how they work. */
function BlogAuthorCard({ lang, author }: { lang: BlogLanguage; author: BlogAuthorId }) {
  const profile = blogAuthors[author];
  const path = authorPath(lang, author);
  return (
    <aside className="blog-author-card" aria-label={blogCopy[lang].writtenBy}>
      <a className="blog-author-card-link" href={path} rel="author">
        <span className="blog-author-card-head">
          <BlogAuthorAvatar author={author} size="large" />
          <span>
            <span className="blog-author-card-label">{blogCopy[lang].writtenBy}</span>
            <span className="blog-author-card-name">{profile.name}</span>
            <span className="blog-author-card-role">{profile.role[lang]}</span>
          </span>
        </span>
        <span className="blog-author-card-bio">{profile.bio[lang]}</span>
        <span className="blog-author-card-more">{blogCopy[lang].viewProfile}<BlogArrow direction="forward" /></span>
      </a>
    </aside>
  );
}

export function BlogExternalIcon() {
  return <svg className="blog-external" viewBox="0 0 16 16" aria-hidden="true"><path d="M6 4h6v6M12 4 4.5 11.5" /></svg>;
}

/** The author's portrait, or initials when there is none; shared by the article card and the author page. */
export function BlogAuthorAvatar({ author, size = "small" }: { author: BlogAuthorId; size?: "small" | "large" }) {
  const profile: BlogAuthor = blogAuthors[author];
  const className = `blog-author-avatar blog-author-avatar-${size}`;
  if (profile.image) {
    const pixels = size === "large" ? 64 : 48;
    return <img className={className} src={profile.image} alt="" width={pixels} height={pixels} loading="lazy" decoding="async" />;
  }
  const initials = profile.name.split(" ").map((part) => part[0]).join("");
  return <span className={className} aria-hidden="true">{initials}</span>;
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
  const articleHTML = useMemo(() => ({ __html: html }), [html]);
  // Code blocks carry a copy button from the build; one delegated handler serves them all.
  const copyCode = (event: React.MouseEvent<HTMLDivElement>) => {
    const button = (event.target as Element).closest<HTMLButtonElement>(".blog-code-copy");
    const code = button?.parentElement?.querySelector("pre")?.innerText;
    if (!button || code === undefined) return;
    void navigator.clipboard.writeText(code.trimEnd()).then(() => {
      const label = button.textContent;
      button.dataset.copied = "true";
      button.textContent = button.dataset.copiedLabel ?? label;
      setTimeout(() => { delete button.dataset.copied; button.textContent = label; }, 1800);
    }, () => {});
  };

  return (
    <div className="min-h-screen bg-canvas text-ink" lang={lang}>
      <DocumentMetadata title={post.title} description={post.description} canonicalPath={post.path} language={lang} />
      <BlogHeader lang={lang} />
      <main className="blog-article-main">
        {/* As on Notion: a quiet left margin with the way back and sharing, no contents sidebar. */}
        <article className="blog-article" aria-labelledby="article-title">
          <a className="blog-back" href={copy.indexPath}><BlogArrow direction="back" />{copy.allArticles}</a>
          <header className="blog-article-header">
            <h1 id="article-title">{post.heading}</h1>
            <p className="blog-byline">
              <span>{copy.by} <a href={authorPath(lang, post.author)} rel="author">{blogAuthors[post.author].name}</a></span>
              <span>{copy.published} <BlogDate lang={lang} value={post.published} /></span>
              {post.updated !== post.published && <span>{copy.updated} <BlogDate lang={lang} value={post.updated} /></span>}
              <span>{copy.readingTime(post.readingMinutes)}</span>
            </p>
          </header>
          <BlogShare lang={lang} path={post.path} title={post.title} className="blog-share-margin" />
          <div className="blog-body">
            <div className="blog-prose" data-blog-body="" onClick={copyCode} dangerouslySetInnerHTML={articleHTML} />
            <BlogShare lang={lang} path={post.path} title={post.title} className="blog-share-end" />
            <BlogAuthorCard lang={lang} author={post.author} />
          </div>
        </article>
        {related.length > 0 && (
          <section className="blog-related" aria-labelledby="blog-related-title">
            <h2 id="blog-related-title">{copy.related}</h2>
            <BlogPostList posts={related} headingLevel={3} />
          </section>
        )}
      </main>
      <BlogDownloadBand lang={lang} />
      <Footer />
    </div>
  );
}
