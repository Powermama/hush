# Language

The landing page exists in English (`/`) and German (`/de`) with one design.
Texts live in `messages/en.json` and `messages/de.json` and are compiled by
Paraglide JS into typed message functions (`src/paraglide`, generated and not
committed); a missing German text fails the type check. The German landing page
addresses readers with "du"; the German blog keeps the neutral form.

## Journeys

| ID | Journey | Test |
| --- | --- | --- |
| LANG-001 | `/de` is prerendered in German with `html lang="de"`, `og:locale de_DE`, its own `SoftwareApplication` data (free offer) and `hreflang` links between `/`, `/de` and `x-default`. Download buttons say "Download", not "Laden". | `tests/language.spec.ts` LANG-001 |
| LANG-002 | A device whose first language is German goes from `/` to `/de` on its visit to the home page. Every other address, and every other device language, stays where it is. | LANG-002 |
| LANG-003 | The footer switcher (under the logo) opens the same page in the other language where one exists and remembers the choice, which then wins over the device language. | LANG-003 |
| LANG-004 | A page whose language differs from the device's first language offers the other version in a slim bar; dismissing it keeps the current language. | LANG-004 |
| LANG-005 | Headings on `/de` use the same font sizes as on `/`; German copy is written to keep the line structure rather than shrinking type. | LANG-005 |

## Guarantees

- Detection runs in `public/language.js`, loaded with `async` on pages that
  exist in both languages, so it never delays the first paint. It reads the
  current language from the URL and the counterpart from the page's `hreflang`
  links, never redirects to the address it is on, and a stored choice
  (`localStorage` `hush.language`) always wins.
- Search engines crawl in English without a stored choice, so they always get
  the page they asked for and find `/de` through `hreflang`, following Google's
  guidance against redirecting by language.
- `bun run check:i18n` runs the inlang checks; `bun run lint` compiles the
  messages before type checking.
