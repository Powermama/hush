# Legal information journey

This document defines how visitors find and read hush's legal information.

## Goal

A visitor can reach an English legal notice and privacy policy from every public page and switch either document to German without distracting draft UI.

## State flow

```text
Footer legal link selected
  -> English legal document opens
  -> optional EN or DE language selection
  -> equivalent document opens at a stable language-specific URL
  -> visitor returns through the shared hush header or footer
```

## Content invariants

- English is the default language across the site.
- German translations use stable `/de/` URLs and preserve the same section structure.
- All four legal routes use the shared public correspondence address, including the operator's name and the separate c/o delivery line. Tests must use this public address, not a residential address.
- Public headers share the same component and remain in document flow. Only the thin reading-progress line remains fixed while scrolling.
- Home and the EN/DE language switch sit together above the document title, aligned to the reading column on desktop and mobile. The title leads the document, with its update date below it. These local controls stay separate from the global navigation and remain keyboard accessible.
- Placeholder operator, hosting, or supervisory-authority data must remain `noindex, nofollow` and excluded from the sitemap.
- The privacy policy must distinguish local app processing from network features such as downloads, update checks, and optional Verified Messages.
- Sponsorship must not imply sponsor access to messages, audio, proof content, or usage profiles.
- The policy describes live proof cleanup after the 24-hour terminal-state interval, bounded IP expiry, and the separate limits of historical backups. It must not promise deletion the product cannot perform.
- Email disclosures distinguish iCloud Mail as the mailbox provider, Apple Mail as the client and Cloudflare as DNS. Preserve the issued VAT identifier as instructed by the operator.
- Both languages name Hetzner and Germany as the confirmed origin host and location, while distinguishing Cloudflare's international processing. Public provider documents do not establish the account's contractual compliance; pending operational checks are recorded in `../legal-review.md`.
- The notice labels the VAT identifier under Section 27a UStG without exposing internal drafting instructions. An unconfirmed official lookup must not be presented as successful validation.

## Scenarios

### LEGAL-001 - Open the English legal information

Given a visitor is on a public hush page, when they choose Legal notice or Privacy in the footer, then the English document opens with a matching title, language declaration, and canonical URL.

### LEGAL-002 - Read the German version

Given an English legal document is open, when the visitor chooses DE, then the equivalent German document opens at its `/de/` URL and the document language changes to German.

### LEGAL-003 - Protect an unfinished legal template

Given the configured legal identity still contains internal placeholders, when any legal route is requested, then the server returns `X-Robots-Tag: noindex, nofollow` and disables caching without exposing draft warnings to visitors.

## Test mapping

| Journey | Automated evidence |
| --- | --- |
| LEGAL-001 | `tests/landing.spec.ts` verifies the English footer labels, English headings, document language, and privacy sections. |
| LEGAL-002 | `tests/landing.spec.ts` selects DE and verifies the German URL, heading, language, and absence of a draft warning. It also checks the page navigation, current language and return Home on mobile and desktop layouts. |
| LEGAL-003 | `tests/landing.spec.ts` requests all four legal routes and verifies noindex and no-store response headers plus page-level robots metadata and no public draft banner. |
| LEGAL-001 / LEGAL-002 | `tests/landing.spec.ts` checks the complete public correspondence address and delivery-line order on all four routes. |
| LEGAL-001 / LEGAL-002 | `tests/landing.spec.ts` checks the named host, German server location, current review date, processor links and accurate retention disclosures in both languages. |

## Change rule

Update both languages and the automated journey together. Replace all placeholders and review the actual service providers, retention periods, legal bases, and controller information before enabling indexing.
