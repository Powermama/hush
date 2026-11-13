export const HTML_CACHE_CONTROL = "no-cache, must-revalidate";

export function cacheControlForStaticPath(path: string) {
  // The CMS polls it to see whether a change is live; no cache may hold it.
  if (path.endsWith("/blog/revision.txt")) return "no-store";

  if (path.includes("/assets/")) {
    // Precompressed binary archives must not acquire another edge/proxy layer.
    return "public, max-age=31536000, immutable" + (path.endsWith(".gz") ? ", no-transform" : "");
  }

  return path.endsWith(".html")
    ? HTML_CACHE_CONTROL
    : "public, max-age=300";
}
