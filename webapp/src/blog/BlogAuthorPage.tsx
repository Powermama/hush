// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 Clemens Kressmann
import { authorPath, blogAuthors, type BlogAuthorId } from "../../shared/authors";
import { blogCopy, type BlogLanguage } from "../../shared/blog";
import { blogPosts } from "../../shared/blog-posts.generated";
import { DocumentMetadata } from "../components/DocumentMetadata";
import { Footer } from "../layout/Footer";
import { BlogArrow, BlogAuthorAvatar, BlogExternalIcon, BlogHeader } from "./BlogArticlePage";
import { BlogPostList } from "./BlogIndexPage";
import "./blog.css";

/** Profile page for one author in one blog language; bylines and BlogPosting data point here. */
export function BlogAuthorPage({ lang, author }: { lang: BlogLanguage; author: BlogAuthorId }) {
  const copy = blogCopy[lang];
  const profile = blogAuthors[author];
  const posts = blogPosts.filter((post) => post.lang === lang && post.author === author);
  const path = authorPath(lang, author);
  return (
    <div className="min-h-screen bg-canvas text-ink" lang={lang}>
      <DocumentMetadata title={`${profile.name} - ${profile.role[lang]}`} description={copy.authorDescription(profile.name)} canonicalPath={path} language={lang} />
      <BlogHeader lang={lang} />
      <main className="blog-index-main">
        <header className="blog-author-header">
          <a className="blog-back" href={copy.indexPath}><BlogArrow direction="back" />{copy.allArticles}</a>
          <div className="blog-author-identity">
            <BlogAuthorAvatar author={author} size="large" />
            <div>
              <h1>{profile.name}</h1>
              <p className="blog-author-role">{profile.role[lang]}</p>
            </div>
          </div>
          <p className="blog-author-bio">{profile.bio[lang]}</p>
          <nav className="blog-author-links" aria-label={copy.authorElsewhere}>
            {profile.sameAs.map((link) => (
              <a key={link.url} href={link.url} rel="me noopener" target="_blank">
                {link.label}<BlogExternalIcon />
              </a>
            ))}
          </nav>
        </header>
        <section aria-labelledby="author-articles">
          <h2 id="author-articles" className="blog-author-section">{copy.authorArticles}</h2>
          <BlogPostList lang={lang} posts={posts} />
        </section>
      </main>
      <Footer />
    </div>
  );
}
