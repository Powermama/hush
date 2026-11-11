import { siApple, siGithub } from "simple-icons";
import { type ReactNode, useEffect, useId, useRef, useState } from "react";
import { DownloadLink } from "../components/DownloadExperience";
import { Logo } from "../components/Logo";
import { PageProgress } from "./PageProgress";
import "./header.css";

export function Header({
  theme = "light",
  currentPage,
  navigationLabel = "Primary navigation",
  children,
}: {
  theme?: "light" | "dark";
  currentPage?: "verified-messages";
  navigationLabel?: string;
  children?: ReactNode;
}) {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuId = useId();
  const header = useRef<HTMLElement>(null);
  const toggle = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    if (!menuOpen) return;
    const escape = (event: KeyboardEvent) => {
      if ((event.target as Element).closest?.("dialog[open]")) return;
      if (event.key === "Escape") { setMenuOpen(false); toggle.current?.focus(); }
    };
    const outside = (event: PointerEvent) => {
      if ((event.target as Element).closest?.("dialog[open]")) return;
      if (!header.current?.contains(event.target as Node)) setMenuOpen(false);
    };
    const desktop = matchMedia("(min-width: 761px)");
    const resized = () => { if (desktop.matches) setMenuOpen(false); };
    document.addEventListener("keydown", escape);
    document.addEventListener("pointerdown", outside);
    desktop.addEventListener("change", resized);
    return () => {
      document.removeEventListener("keydown", escape);
      document.removeEventListener("pointerdown", outside);
      desktop.removeEventListener("change", resized);
    };
  }, [menuOpen]);
  return (
    <><PageProgress /><header ref={header} className="site-header" data-theme={theme} data-menu-open={menuOpen}>
      <nav aria-label={navigationLabel}>
        <div className="site-brand"><Logo href="/" /></div>
        <div className="site-mobile-start"><DownloadLink variant="custom" className="site-compact-download" mobileLabel="Get started on macOS"><svg viewBox="0 0 24 24" aria-hidden="true"><path d={siApple.path} fill="currentColor" /></svg>Get started on macOS</DownloadLink></div>
        <button ref={toggle} className="site-menu-toggle" type="button" aria-label={menuOpen ? "Close navigation" : "Open navigation"} aria-expanded={menuOpen} aria-controls={menuId} onClick={() => setMenuOpen(open => !open)}>
          <svg viewBox="0 0 24 24" aria-hidden="true">{menuOpen ? <path d="m6 6 12 12M18 6 6 18" /> : <path d="M4 8h16M4 16h16" />}</svg>
        </button>
        <div id={menuId} className="site-header-links" data-open={menuOpen} onClick={event => { if (event.currentTarget.contains(event.target as Node) && (event.target as Element).closest("a")) setMenuOpen(false); }}>
          <a href="https://github.com/Powermama/hush" target="_blank" rel="noopener noreferrer" className="site-github">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d={siGithub.path} fill="currentColor" /></svg>
            GitHub
          </a>
          <a href="/verified-messages" aria-current={currentPage === "verified-messages" ? "page" : undefined}>Verified Messages</a>
          <button className="site-community" type="button" disabled title="Community link coming soon" aria-label="Community, coming soon">
            Community<span aria-hidden="true">Soon</span>
          </button>
          <DownloadLink variant="custom" className="site-header-download"><svg viewBox="0 0 24 24" aria-hidden="true"><path d={siApple.path} fill="currentColor" /></svg>Download</DownloadLink>
        </div>
      </nav>
      {children && <div className="site-header-context">{children}</div>}
    </header></>
  );
}
