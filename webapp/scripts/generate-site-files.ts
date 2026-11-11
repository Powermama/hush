import { releases } from "../shared/releases";
import { publicLegalPaths } from "../shared/legal";

const siteOrigin = (process.env.HUSH_SITE_ORIGIN ?? "https://behu.sh").replace(
  /\/$/,
  "",
);
const publicReleases = releases.filter(
  (release) => release.visibility === "public",
);

const urls = [
  { location: `${siteOrigin}/` },
  { location: `${siteOrigin}/verified-messages` },
  ...publicLegalPaths.map((path) => ({ location: `${siteOrigin}${path}` })),
  ...(publicReleases.length > 0
    ? [
        {
          location: `${siteOrigin}/releases`,
          modified: publicReleases[0].releasedAt,
        },
      ]
    : []),
  ...publicReleases.map((release) => ({
    location: `${siteOrigin}/releases/${release.slug}`,
    modified: release.releasedAt,
  })),
];

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
console.info(
  `Generated public/sitemap.xml with ${urls.length} indexable URL${urls.length === 1 ? "" : "s"}.`,
);
