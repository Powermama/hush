// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { blogCopy, type BlogLanguage } from "../../shared/blog";
import { blogPosts } from "../../shared/blog-posts.generated";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { Footer } from "../layout/Footer";
import { BlogArrow, BlogDate, BlogHeader } from "./BlogArticlePage";
import "./blog.css";

export function BlogIndexPage({ lang }: { lang: BlogLanguage }) {
  const copy = blogCopy[lang];
  const posts = blogPosts.filter((post) => post.lang === lang);
  return (
    <div className="min-h-screen bg-canvas text-ink" lang={lang}>
      <DocumentMetadata title={copy.indexTitle} description={copy.indexDescription} canonicalPath={copy.indexPath} language={lang} />
      <BlogHeader lang={lang} />
      <main className="blog-index-main">
        <header className="blog-index-header">
          <h1>{copy.heading}</h1>
          <p>{copy.lead}</p>
        </header>
        <ul className="blog-index-list">
          {posts.map((post) => (
            <li key={post.slug}>
              <a href={post.path}>
                <h2>{post.heading}</h2>
                <p>{post.description}</p>
                <span className="blog-index-meta">
                  <BlogDate lang={lang} value={post.updated} /> · {copy.readingTime(post.readingMinutes)}
                </span>
                <span className="blog-related-more">{copy.readArticle}<BlogArrow direction="forward" /></span>
              </a>
            </li>
          ))}
        </ul>
      </main>
      <Footer />
    </div>
  );
}
