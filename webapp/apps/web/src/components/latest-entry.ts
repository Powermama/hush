/**
 * The current state of an observed element. An IntersectionObserver delivers every change
 * since its last callback in one batch, oldest first: after a reload that restores the
 * scroll position, the first entry can still say "not visible" while the last says
 * "visible". Reading only the first entry then misses the change for good.
 */
export function latestEntry(entries: IntersectionObserverEntry[]): IntersectionObserverEntry {
  return entries[entries.length - 1]!;
}
