export const HTML_CACHE_CONTROL = "no-cache, must-revalidate";

export function cacheControlForStaticPath(path: string) {
  if (path.includes("/assets/")) {
    // Precompressed binary archives must not acquire another edge/proxy layer.
    return "public, max-age=31536000, immutable" + (path.endsWith(".gz") ? ", no-transform" : "");
  }

  return path.endsWith(".html")
    ? HTML_CACHE_CONTROL
    : "public, max-age=300";
}
