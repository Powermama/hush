export const HTML_CACHE_CONTROL = "no-cache, must-revalidate";

export function cacheControlForStaticPath(path: string) {
  if (path.includes("/assets/")) {
    return "public, max-age=31536000, immutable";
  }

  return path.endsWith(".html")
    ? HTML_CACHE_CONTROL
    : "public, max-age=300";
}
