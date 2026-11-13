// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { useState } from "react";
import { blogAuthors } from "@hush/article/authors";
import { blogClusters, type BlogClusterId, type BlogLanguage } from "@hush/article/taxonomy";
import { blogCopy, type BlogPostMetadata } from "../../shared/blog";
import { blogPosts } from "../../shared/blog-posts.generated";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { Footer } from "../layout/Footer";
import { BlogArrow, BlogHeader } from "./BlogArticlePage";
import { BlogDownloadBand } from "./BlogDownloadBand";
import "./blog.css";

/** One article as a card: cover, topic, title, summary, then "Read article" with author and reading time. */
export function BlogCard({ post, headingLevel = 2 }: { post: BlogPostMetadata; headingLevel?: 2 | 3 }) {
  const copy = blogCopy[post.lang];
  const Heading = headingLevel === 2 ? "h2" : "h3";
  return (
    <li className="blog-card">
      <a href={post.path}>
        <img className="blog-card-image" src={post.cardImage} width={800} height={420} alt="" loading="lazy" decoding="async" />
        <span className="blog-card-body">
          <span className="blog-card-topic">{blogClusters[post.cluster][post.lang]}</span>
          <Heading className="blog-card-title">{post.heading}</Heading>
          <span className="blog-card-summary">{post.description}</span>
          <span className="blog-card-footer">
            <span className="blog-related-more">{copy.readArticle}<BlogArrow direction="forward" /></span>
            <span className="blog-card-meta">{blogAuthors[post.author].name} · {copy.readingTimeShort(post.readingMinutes)}</span>
          </span>
        </span>
      </a>
    </li>
  );
}

/** Article cards, shared by the blog index and author pages. */
export function BlogPostList({ posts, headingLevel = 2 }: { posts: readonly BlogPostMetadata[]; headingLevel?: 2 | 3 }) {
  return <ul className="blog-card-grid">{posts.map((post) => <BlogCard key={post.slug} post={post} headingLevel={headingLevel} />)}</ul>;
}

export function BlogIndexPage({ lang }: { lang: BlogLanguage }) {
  const copy = blogCopy[lang];
  const posts = blogPosts.filter((post) => post.lang === lang);
  // Topic filters appear for topics that have articles; "All" is the prerendered default.
  const topics = [...new Set(posts.map((post) => post.cluster))];
  const [topic, setTopic] = useState<BlogClusterId | undefined>(undefined);
  const shown = topic ? posts.filter((post) => post.cluster === topic) : posts;
  return (
    <div className="min-h-screen bg-canvas text-ink" lang={lang}>
      <DocumentMetadata title={copy.indexTitle} description={copy.indexDescription} canonicalPath={copy.indexPath} language={lang} />
      <BlogHeader lang={lang} />
      <main>
        <header className="blog-index-band">
          <div className="blog-index-band-inner">
            <h1>{copy.heading}</h1>
            <p>{copy.lead}</p>
            <div className="blog-topics" role="group" aria-label={copy.topics}>
              <button type="button" aria-pressed={!topic} onClick={() => setTopic(undefined)}>{copy.allTopics}</button>
              {topics.map((id) => (
                <button key={id} type="button" aria-pressed={topic === id} onClick={() => setTopic(id)}>{blogClusters[id][lang]}</button>
              ))}
            </div>
          </div>
        </header>
        <div className="blog-index-grid">
          <BlogPostList posts={shown} />
        </div>
      </main>
      <BlogDownloadBand lang={lang} />
      <Footer />
    </div>
  );
}
