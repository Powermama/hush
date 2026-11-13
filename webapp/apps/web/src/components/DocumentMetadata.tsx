import { useEffect } from "react";
import { sitePages } from "../../shared/site";

type DocumentMetadataProps = {
  title: string;
  description: string;
  canonicalPath: string;
  indexable?: boolean;
  language?: "en" | "de";
};

function setMeta(selector: string, attribute: string, value: string) {
  const element = document.head.querySelector<HTMLMetaElement>(selector);
  if (element) element.setAttribute(attribute, value);
}

export function DocumentMetadata(props: DocumentMetadataProps) {
  const {
    title,
    description,
    canonicalPath,
    indexable = true,
    language = "en",
  } = props.indexable === false ? props : sitePages[props.canonicalPath] ?? props;
  useEffect(() => {
    document.documentElement.lang = language;
    document.title = title;
    setMeta('meta[name="description"]', "content", description);
    setMeta('meta[property="og:title"]', "content", title);
    setMeta('meta[property="og:description"]', "content", description);
    setMeta('meta[name="twitter:title"]', "content", title);
    setMeta('meta[name="twitter:description"]', "content", description);
    setMeta(
      'meta[property="og:url"]',
      "content",
      `https://behu.sh${canonicalPath}`,
    );

    const canonical = document.head.querySelector<HTMLLinkElement>(
      'link[rel="canonical"]',
    );
    canonical?.setAttribute("href", `https://behu.sh${canonicalPath}`);

    let robots = document.head.querySelector<HTMLMetaElement>(
      'meta[name="robots"]',
    );
    if (!robots) {
      robots = document.createElement("meta");
      robots.name = "robots";
      document.head.append(robots);
    }
    robots.content = indexable ? "index, follow" : "noindex, nofollow";
  }, [canonicalPath, description, indexable, language, title]);

  return null;
}
