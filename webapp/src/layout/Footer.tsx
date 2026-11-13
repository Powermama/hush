import { Logo } from "../components/Logo";
import { blogPosts } from "../../shared/blog-posts.generated";

// The blog link appears only once an English article is published.
const hasBlog = blogPosts.some((post) => post.lang === "en");

export function Footer() {
  return (
    <footer className="bg-stone px-5 pb-10 pt-16">
      <div className="mx-auto max-w-6xl border-t border-black/8 pt-10">
        <div className="grid grid-cols-2 gap-x-6 gap-y-10 sm:grid-cols-[1fr_auto_auto] sm:gap-16">
          <div className="col-span-2 sm:col-span-1">
            <Logo />
            <p className="mt-4 max-w-xs text-sm leading-6 text-muted">
              The voice layer for your Mac. Personal by nature. Local by design.
            </p>
          </div>
          <nav aria-label="Product" className="text-sm">
            <p className="font-semibold text-ink">Product</p>
            <div className="mt-4 flex flex-col items-start gap-3 text-muted">
              <a className="transition hover:text-ink" href="/#top">About hush</a>
              <a className="transition hover:text-ink" href="/verified-messages">Verified Messages</a>
              <a className="transition hover:text-ink" href="/releases">Releases</a>
              {hasBlog && <a className="transition hover:text-ink" href="/blog">Blog</a>}
              {hasBlog && <a className="transition hover:text-ink" href="/blog/editorial-policy">Editorial policy</a>}
              <a className="transition hover:text-ink" href="mailto:hello@behu.sh">Contact</a>
            </div>
          </nav>
          <nav aria-label="Legal" className="text-sm">
            <p className="font-semibold text-ink">Legal</p>
            <div className="mt-4 flex flex-col items-start gap-3 text-muted">
              <a className="transition hover:text-ink" href="/impressum">Legal notice</a>
              <a className="transition hover:text-ink" href="/datenschutz">Privacy</a>
            </div>
          </nav>
        </div>
        <div className="mt-12 border-t border-black/8 pt-6 text-xs text-soft">
          <span>© {new Date().getFullYear()} hush</span>
        </div>
      </div>
    </footer>
  );
}
