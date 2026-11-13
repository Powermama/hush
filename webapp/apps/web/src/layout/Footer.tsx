import { Logo } from "../components/Logo";
import { blogPosts } from "../../shared/blog-posts.generated";
import { editorialPolicyPath } from "@hush/article/taxonomy";
import { blogCopy } from "../../shared/blog";
import type { SiteLanguage } from "../../shared/site";
import { LanguageSwitcher } from "../i18n/LanguageControls";
import { m } from "../paraglide/messages";
import { getLocale } from "../paraglide/runtime";

export function Footer() {
  const language = getLocale() as SiteLanguage;
  const prefix = language === "de" ? "/de" : "";
  // The blog links appear only once that language has a published article.
  const hasBlog = blogPosts.some((post) => post.lang === language);
  return (
    <footer className="bg-stone px-5 pb-10 pt-16">
      <div className="mx-auto max-w-6xl border-t border-black/8 pt-10">
        <div className="grid grid-cols-2 gap-x-6 gap-y-10 sm:grid-cols-[1fr_auto_auto] sm:gap-16">
          <div className="col-span-2 sm:col-span-1">
            <Logo href={prefix || "/"} />
            <p className="mt-4 max-w-xs text-sm leading-6 text-muted">{m.footer_tagline()}</p>
            <LanguageSwitcher />
          </div>
          <nav aria-label={m.footer_product()} className="text-sm">
            <p className="font-semibold text-ink">{m.footer_product()}</p>
            <div className="mt-4 flex flex-col items-start gap-3 text-muted">
              <a className="transition hover:text-ink" href={`${prefix}/#top`}>{m.footer_about()}</a>
              <a className="transition hover:text-ink" href="/verified-messages">Verified Messages</a>
              <a className="transition hover:text-ink" href="/releases">{m.footer_releases()}</a>
              {hasBlog && <a className="transition hover:text-ink" href={blogCopy[language].indexPath}>{m.footer_blog()}</a>}
              {hasBlog && <a className="transition hover:text-ink" href={editorialPolicyPath(language)}>{m.footer_editorial()}</a>}
              <a className="transition hover:text-ink" href="mailto:hello@behu.sh">{m.footer_contact()}</a>
            </div>
          </nav>
          <nav aria-label={m.footer_legal()} className="text-sm">
            <p className="font-semibold text-ink">{m.footer_legal()}</p>
            <div className="mt-4 flex flex-col items-start gap-3 text-muted">
              <a className="transition hover:text-ink" href={`${prefix}/impressum`}>{m.footer_imprint()}</a>
              <a className="transition hover:text-ink" href={`${prefix}/datenschutz`}>{m.footer_privacy()}</a>
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
