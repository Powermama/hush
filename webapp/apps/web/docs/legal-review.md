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
6. Analytics (PRD R10, November 2026): the code for cookieless Umami page
   views, download clicks and counted downloads exists but stays off until
   `HUSH_UMAMI_URL` and `HUSH_UMAMI_WEBSITE_ID` are set. Before setting them,
   the privacy policy (section 8, which today says the site uses no audience
   analytics) must describe it and be reviewed: which Umami instance and host
   processes the data, that the visitor's IP address is not forwarded, Do Not
   Track and Global Privacy Control are honoured, and the legal basis. Turning
   it on without that review is not allowed.
7. Confirm the dispute-resolution statement and whether editorial activities
   or other business circumstances trigger additional disclosure duties.

The factual disclosure improvements are approved for publication by the operator.
Outstanding private contractual/account checks remain explicit; they do not
justify retaining known-incorrect provider text. Keep legal indexing disabled
pending those confirmations. A merged PR is not legal clearance.

8. ChatGPT connection (added 18 November 2026, draft): section 7 describes the
   optional Sign in with ChatGPT path from the app's code and consent dialogs:
   requests go from the Mac directly to OpenAI under the user's own account with
   `store: false`; the operator receives nothing. Open for legal review: the roles
   (the operator as neither controller nor processor of this content, or not), the
   legal basis the app relies on for asking consent, the US transfer wording, and
   whether the in-app consent text and this section match. Do not treat the passing
   build as clearance.

   Source check on 18 November 2026:
   - Apple's own disclosure for the same pattern ([ChatGPT Extension & Privacy](https://www.apple.com/legal/privacy/data/en/chatgpt-extension),
     dated 2026-09-14) says that when signed in, "your ChatGPT account settings and
     OpenAI's data privacy policies will apply. This means OpenAI may log your
     request, attachments, and session history, and use this data to train or
     improve their models." Section 7 and the app's consent text now say the same;
     `store: false` is described only as keeping requests out of stored API
     responses.
   - [OpenAI's Europe privacy policy](https://openai.com/policies/eu-privacy-policy/),
     "Updated: 24 August 2026", read in full in a browser on 18 November 2026 (it
     refuses automated fetches). Section 12: for the EEA and Switzerland "OpenAI
     Ireland Limited, with its registered office at 1st Floor, The Liffey Trust
     Centre, 117-126 Sheriff Street Upper, Dublin 1, D01 YC43, Ireland, is the
     controller". Section 10: processing "outside of the EEA … in the United States",
     relying on adequacy decisions (Art. 45) and otherwise SCCs (Art. 46(2)(c)).
     Sections 2 and 5: Content may be used "to train the models that power ChatGPT";
     users "can easily choose whether your Content can be used to improve and train
     our models". Section 9: prompts are processed "where necessary to perform a
     contract with you". Section 7 of hush's policy now names the controller and the
     transfer mechanisms as OpenAI states them.
   - The controller question for hush's operator follows [EDPB Guidelines 07/2020](https://www.edpb.europa.eu/system/files/2021-07/eppb_guidelines_202007_controllerprocessor_final_en.pdf)
     (version 2.1): the content goes from the user's Mac to OpenAI under the user's
     contract, and the operator neither receives it nor decides its use; whether
     that leaves the operator outside both roles is the reviewer's call.

   Role analysis, 19 November 2026 (an engineering analysis of primary sources, not a
   lawyer's opinion; the owner accepted it to publish section 7):
   - Processor: no. Nothing is processed by the operator or on its behalf; the
     request goes from the user's Mac to OpenAI under the user's contract. Compare
     [CJEU C-683/21](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:62021CJ0683),
     para. 36 (liability covers processing "carried out on its behalf").
   - Controller: most likely no. A controller "exerts influence over the processing
     … for his, her or its own purposes" (C-683/21, paras. 30-31) and must decide
     purposes and means ([EDPB Guidelines 07/2020](https://www.edpb.europa.eu/system/files/documents/2023-10/EDPB_guidelines_202007_controllerprocessor_final_en.pdf),
     v2.1). The purpose is the user's own writing. EDPB para. 68: "the existence of a
     mere commercial benefit for the parties involved is not sufficient to qualify as
     a purpose of processing"; footnote 29: a system provider is a joint controller
     only if it participates in determining purposes and means.
   - Fashion ID (C-40/17; EDPB paras. 64-67) is distinguished: there a website
     operator embedded a plugin in its own site, so its visitors' data went to
     Facebook in the operator's commercial interest. Here users send their own
     content, at their own initiative and after per-feature consent, to their own
     account. Purely personal use falls under Art. 2(2)(c) GDPR; professional users
     or their employers are the controllers.
   - Residual risk: a regulator could treat the feature's design (what is sent,
     including the window screenshot) as co-determining the means of "collection and
     transmission" by analogy with Fashion ID. Section 7 therefore names a legal
     basis "insofar as" the operator is responsible: consent under Art. 6(1)(a),
     given per feature in the app and withdrawable by turning it off. The app
     already collects that consent before the first request (#100, #122).
   - Further Art. 13 information: none owed if the operator has no role. Under the
     residual reading, section 7 already gives purpose, recipient (OpenAI Ireland
     Limited for the EEA), the transfer safeguards as OpenAI states them, the legal
     basis and withdrawal; rights and the complaint route are in section 11.
   - TDDDG § 25 ([text](https://www.gesetze-im-internet.de/ttdsg/__25.html)): reading
     the current app's text or a screenshot for the assistant serves a service the
     user expressly requested (Abs. 2 Nr. 2), and consent is collected in addition.
   - Out of scope here, flagged for a separate check: Article 50 of the EU AI Act
     (transparency for AI-generated text) applies since 2 August 2026 to providers
     and deployers of AI systems that generate text; whether hush's Live Write falls
     under it or under the exemption for assistive editing is not yet assessed.

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
