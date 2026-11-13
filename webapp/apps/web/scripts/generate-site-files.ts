import { sitePages, siteOrigin } from "../shared/site";

const publicPages = Object.values(sitePages).filter(page => page.indexable);
const urls = publicPages.map(page => ({ location: `${siteOrigin}${page.canonicalPath}`, modified: page.modified }));

const escapeXML = (value: string) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");

const sitemap = [
  '<?xml version="1.0" encoding="UTF-8"?>',
  '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
  ...urls.flatMap(({ location, modified }) => [
    "  <url>",
    `    <loc>${escapeXML(location)}</loc>`,
    ...(modified ? [`    <lastmod>${modified}</lastmod>`] : []),
    "  </url>",
  ]),
  "</urlset>",
  "",
].join("\n");

await Bun.write("public/sitemap.xml", sitemap);
await Bun.write("public/llms.txt", [
  "# hush", "",
  "> Free, open-source voice dictation and local AI for Apple silicon Macs.", "",
  "hush transcribes speech, refines writing with optional personas and offers a beta assistant. macOS 15 or later is required. An 8 GB Mac can run transcription; 16 GB is recommended for the optional assistant.", "",
  "After model downloads, transcription and AI inference run locally. Model downloads, updates, web actions and publishing optional Verified Messages use network connections.", "",
  "Verified Messages share encrypted signed capture and edit history. They do not establish identity, human presence or truth. Private proof links and their fragment keys are not public documentation and must not be indexed or included in summaries.", "",
  "## Product", "",
  ...publicPages.map(page => `- [${page.title}](${siteOrigin}${page.canonicalPath}): ${page.description}`), "",
  "## Source and contribution", "",
  "- [hush on GitHub](https://github.com/Powermama/hush): macOS app and website monorepo.",
  "- [Licensing](https://github.com/Powermama/hush/blob/main/LICENSING.md): AGPL-3.0-only for original code; separately licensed components and assets retain their terms.",
  "- [Contributing](https://github.com/Powermama/hush/blob/main/CONTRIBUTING.md): development and contribution workflow.", "",
  "## Optional", "",
  `- [Sitemap](${siteOrigin}/sitemap.xml): Public URLs intended for indexing.`, "",
].join("\n"));
console.info(
  `Generated public/sitemap.xml with ${urls.length} indexable URL${urls.length === 1 ? "" : "s"}.`,
);
