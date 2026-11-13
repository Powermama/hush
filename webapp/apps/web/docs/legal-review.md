# Legal disclosure review

Reviewed on 11 November 2026. This is an engineering evidence record and a
source-based disclosure review, not legal clearance. Tests verify publication and
behaviour, not compliance.

## Confirmed and implemented

- The operator confirmed Hetzner hosting with servers in Germany. The policy
  names Hetzner Online GmbH and its published business address.
- The public correspondence address is shared by all four legal pages. Keep
  residential addresses, receipts and identity documents out of this repository.
- Cloudflare is in the delivery path; installation downloads use R2 through
  `updates.behu.sh`. German origin hosting does not imply exclusively German
  processing. The policy links Cloudflare's processing terms and names the
  international processing involved.
- Local inference, model downloads, update checks, assistant navigation and
  optional proof publication are distinguished. Public and private signing keys
  are no longer described ambiguously.
- Public MX records point to `mx01.mail.icloud.com` and `mx02.mail.icloud.com`;
  the SPF record lists iCloud. The operator confirmed Apple Mail as the client.
  Both languages now distinguish Apple's iCloud Mail from Cloudflare DNS.
- The retention fix implements bounded live-storage cleanup: terminal proofs
  and abandoned reservations become eligible after 24 hours; expired challenges
  are removed; IP limiter entries expire within two minutes. Failures retry.
  See `proof-retention.md` for tests, erasure handling and restore limitations.
- Backups (updated 13 November 2026): the proof database had no backup schedule
  after the November migration. A daily schedule now writes to the non-public
  Cloudflare R2 bucket `hush-proof-backups` with a token limited to it, keeps 7
  days and keeps no local copy; the bucket deletes objects after 9 days. The
  policy states the 9-day bound for these backups and keeps the caveat for other
  recovery copies.
- The VAT identifier remains published at the operator's explicit request.
  Free distribution alone does not establish an exemption from DDG disclosure.
  Project wording now says free, open source and alpha, without an invented
  future commercialization plan.
- Unsubstantiated blanket liability exclusions and internal drafting advice
  have been removed. EN and DE use the same updated facts.

## Owner confirmation and operational work still required

Keep `legalConfig.isPlaceholder` true while these items remain unresolved.
Noindex is an indexing choice, not a substitute for legal obligations.

1. VAT: VIES returned `isValid: false` and `userError: INVALID` for the currently
   published number on 11 November 2026. Compare it with the official allocation
   notice. VIES validity concerns EU cross-border transactions and is not proof
   of the number's assignment or its absence. Do not silently substitute a
   guessed number or publish a personal tax number.
2. Contact and establishment: confirm an additional effective public contact
   channel and the actual business establishment. Confirm the correspondence
   service accepts legally effective service for this use. A forwarding address
   alone does not establish which state authority is competent. Do not publish
   a private telephone number from a receipt.
3. Processors: retain the actual Hetzner processing agreement and the applicable
   Cloudflare terms in private operational records. Public provider documents
   alone do not prove the account's contractual configuration. iCloud Mail is
   confirmed; retain the applicable Apple account terms and assess the actual
   processing/transfer arrangement for business correspondence.
4. Logging and tracking: check Coolify/proxy, host and Cloudflare log retention,
   backups, and dashboard-injected analytics. No analytics SDK was found in the
   application, but this does not verify account settings. Do not invent log
   retention periods. Update the policy with the actual periods or specific
   determination criteria once confirmed.
5. Backups: regular proof-database backups are bounded (9 days, see above).
   Still open: give the November 2026 migration backup on the server
   (`/root/hush-backup-20261112-1815`) and the stopped rollback resources a
   removal date, and confirm the Cloudflare processing terms cover R2 storage
   of these backups. Live-object cleanup and authenticated revocation are
   implemented separately; neither establishes GDPR compliance alone.
6. Confirm the dispute-resolution statement and whether editorial activities
   or other business circumstances trigger additional disclosure duties.

The factual disclosure improvements are approved for publication by the operator.
Outstanding private contractual/account checks remain explicit; they do not
justify retaining known-incorrect provider text. Keep legal indexing disabled
pending those confirmations. A merged PR is not legal clearance.

## Primary sources

- [Section 5 DDG](https://www.gesetze-im-internet.de/ddg/__5.html): provider
  identification, address, effective contact and identification numbers where issued.
- [GDPR](https://eur-lex.europa.eu/eli/reg/2016/679/oj/deu): Articles 5, 6, 12-14,
  17, 21, 28, 44 et seq. and 77.
- [Saxon data protection authority: information duties](https://www.datenschutz.sachsen.de/informationspflichten.html):
  purposes, legal bases, recipients, retention and rights.
- [Section 25 TDDDG](https://www.gesetze-im-internet.de/ttdsg/__25.html): terminal
  storage/access, consent and the strictly necessary exceptions.
- [CJEU C-298/07](https://eur-lex.europa.eu/legal-content/EN/ALL/?uri=celex%3A62007CJ0298):
  effective contact in addition to email; not necessarily a telephone number.
- [Section 36 VSBG](https://www.gesetze-im-internet.de/vsbg/__36.html): consumer
  dispute-resolution disclosure and its scope.
- [Official VIES guidance](https://europa.eu/youreurope/business/finance-and-tax/vat/check-vat-number-vies/index_en.htm):
  meaning and limitations of an invalid lookup result.
- [Apple privacy policy](https://www.apple.com/legal/privacy/): email processing and transfers.
- [Apple service entities](https://www.apple.com/legal/privacy/en-ww/affiliated-company/): iCloud entity depends on account region.
- [Hetzner legal notice](https://www.hetzner.com/de/legal/legal-notice/): provider identity.
- [Cloudflare processing terms](https://www.cloudflare.com/cloudflare-customer-dpa/):
  processing roles and section 6 transfer safeguards.

Recheck these facts whenever infrastructure, recipients, features, retention or
funding changes. Keep account evidence and legal advice outside the public repo.
