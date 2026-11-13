// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { authorPath, blogAuthors, type BlogAuthor, type BlogAuthorId } from "../../shared/authors";
import { blogCopy, hasReadingSidebar, type BlogLanguage, type BlogPostMetadata } from "../../shared/blog";
import { blogPosts } from "../../shared/blog-posts.generated";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { Footer } from "../layout/Footer";
import { Header } from "../layout/Header";
import { BlogDownloadCard } from "./BlogDownloadCard";
import { BlogShare } from "./BlogShare";
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

/** The author again after the article, as the best-read blogs do: who wrote it and how they work. */
function BlogAuthorCard({ lang, author }: { lang: BlogLanguage; author: BlogAuthorId }) {
  const profile = blogAuthors[author];
  const path = authorPath(lang, author);
  return (
    <aside className="blog-author-card" aria-label={blogCopy[lang].writtenBy}>
      <div className="blog-author-card-head">
        <BlogAuthorAvatar author={author} size="large" />
        <div>
          <p className="blog-author-card-label">{blogCopy[lang].writtenBy}</p>
          <p className="blog-author-card-name"><a href={path} rel="author">{profile.name}</a></p>
          <p className="blog-author-card-role">{profile.role[lang]}</p>
        </div>
      </div>
      <p className="blog-author-card-bio">{profile.bio[lang]}</p>
      <div className="blog-author-card-foot">
        <span className="blog-author-links">
          {profile.sameAs.map((link) => (
            <a key={link.url} href={link.url} rel="me noopener" target="_blank">{link.label}<BlogExternalIcon /></a>
          ))}
        </span>
        <a className="blog-author-card-more" href={path}>{blogCopy[lang].moreBy(profile.name.split(" ")[0]!)}<BlogArrow direction="forward" /></a>
      </div>
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
  const active = useActiveSection(post.toc.map((entry) => entry.id));
  const sidebar = hasReadingSidebar(post.type);
  const toc = sidebar && post.toc.length > 1 && (
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
        <article className={`blog-article ${sidebar ? "blog-article-guide" : "blog-article-essay"}`} aria-labelledby="article-title">
          <header className="blog-article-header">
            <a className="blog-back" href={copy.indexPath}><BlogArrow direction="back" />{copy.allArticles}</a>
            <h1 id="article-title">{post.heading}</h1>
            <p className="blog-byline">
              <span>{copy.by} <a href={authorPath(lang, post.author)} rel="author">{blogAuthors[post.author].name}</a></span>
              <span>{copy.published} <BlogDate lang={lang} value={post.published} /></span>
              {post.updated !== post.published && <span>{copy.updated} <BlogDate lang={lang} value={post.updated} /></span>}
              <span>{copy.readingTime(post.readingMinutes)}</span>
            </p>
          </header>
          {toc && <details className="blog-toc-mobile"><summary>{copy.onThisPage}</summary>{toc}</details>}
          <div className="blog-article-layout">
            {/* Wide screens: a quiet, sticky margin column with the contents and sharing. */}
            {sidebar && (
              <aside className="blog-sidebar">
                <div className="blog-sidebar-sticky">
                  {toc}
                  <BlogShare lang={lang} path={post.path} title={post.title} />
                </div>
              </aside>
            )}
            <div className="blog-prose" data-blog-body="" dangerouslySetInnerHTML={{ __html: html }} />
          </div>
          <BlogShare lang={lang} path={post.path} title={post.title} className="blog-share-end" />
          <BlogAuthorCard lang={lang} author={post.author} />
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
