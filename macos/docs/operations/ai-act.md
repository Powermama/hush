# EU AI Act transparency (Article 50)

Assessed on 19 November 2026 from primary sources. This is an engineering record, not
legal clearance; it says what applies to hush, what is done, and what is still open.

## Sources

- [Regulation (EU) 2024/1689](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32024R1689) (AI Act): Article 50, Article 3(1), (3), (4), (68), Article 2(12), recitals 133 and 134.
- [Regulation (EU) 2026/1744](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32026R1744) (Digital Omnibus on AI, OJ 24.7.2026), recital 38.
- [Commission Guidelines on Article 50](https://ai-act-service-desk.ec.europa.eu/sites/default/files/2026-07/guidelines_on_the_implementation_of_the_transparency_obligations_for_certain_ai_systems_under_article_50_of_the_ai_act_bzptwqhk0ikg1dtlddap41psfy_131215.pdf), C(2026) 5054 final, 20 July 2026.
- [Code of Practice on Transparency of AI-generated Content](https://digital-strategy.ec.europa.eu/en/policies/code-practice-ai-generated-content), final, 10 June 2026, and its [signatory list](https://digital-strategy.ec.europa.eu/en/news/strong-backing-code-practice-transparency-ai-generated-content).

## hush's role

- hush is the **provider of an AI system** (Art. 3(1), 3(3)): it puts Live Write and the
  assistant on the market under its own name, free of charge. It is a **downstream
  provider** (Art. 3(68)): the models (Qwen, Apple Intelligence, ChatGPT) come from other
  providers, "regardless of whether the AI model is provided by themselves … or provided
  by another entity".
- The AGPL licence does not help: the open-source exclusion does not cover Article 50
  systems (Art. 2(12)).
- Users using hush privately are not deployers (Art. 3(4)), but that removes only deployer
  duties, not hush's provider duties.

## Timing

The Omnibus gives systems already on the market before 2 August 2026 until 2 December 2026
for marking (recital 38). The disclosure duties in Art. 50(1) have no transition.

**Owner's position (19 November 2026):** the owner built and distributed hush before
August 2026, so hush counts as already on the market and the marking deadline is
**2 December 2026**. The early builds came from repositories that are not on this machine,
so the dates cannot be checked here; this rests on the owner's statement.

**Owner's plan:** a lawyer reviews this assessment after the early beta, once traffic grows.
Until then this record states what the primary sources say, and the gap below stays open
with its deadline.

## Per feature

| Feature | Duty | Assessment |
|---|---|---|
| Live Write clean-up (fillers, grammar, punctuation) | none | Standard editing, exempt: "Grammar correction and spellchecking, linguistic and minor stylistic polishing that do not change the substance, meaning, style or messaging" (guidelines, para. 90) |
| Live Write writing a requested text, personas changing tone | Art. 50(2) marking | In scope: new text, or "rewriting text that changes style, structure and meaning" |
| Assistant conversation | Art. 50(1) disclosure | In scope: voice assistants are the guidelines' first example. "Hey Hush" and "Talk to Hush" are the "generic references to 'assistant'" the guidelines call unclear |
| Assistant text written into apps | Art. 50(2) marking | In scope |
| Assistant spoken voice (Kokoro) | Art. 50(2) marking | Residual risk. Point 88 exempts ephemeral real-time output only "when marking is not technically feasible", and audio watermarking exists. The voice is generic, played locally and never stored, and the user is told it is AI |

## Done

- **Art. 50(1):**
  - The companion shows a persistent **AI** label next to its status.
  - Its microphone control says "Talk to hush's AI assistant", for VoiceOver too (Art. 50(5)).
  - The first spoken reply of each conversation starts with "This is hush's AI assistant", as the guidelines' example of a voice assistant (para. 36).
  - The draft window's subtitle says "hush's AI assistant".
  - Covered by `CoworkerTests`.

## Open: machine-readable marking of generated text

- **Free-form text:** it cannot carry metadata. The code therefore asks for one layer, an
  imperceptible watermark, "with the exception of very short text. For free-form text longer
  than 200 tokens, watermarking still needs to be applied" (code, sub-measure 1.1.2).
- **ChatGPT:** OpenAI signed Section 1 of the code (marking). hush may rely on model-level
  marking done upstream, without prejudice to its own responsibility (code, measure 1.1).
- **Qwen (local, MLX) and Apple Intelligence:** neither Alibaba nor Apple is a signatory.
  Texts over 200 tokens from these engines, such as assistant emails or long Live Write
  texts, are **not watermarked today**.
- **Deadline:** 2 December 2026, under the owner's position above.
- **Next step (owner's decision):**
  - A research spike on an inference-time text watermark in hush's MLX sampler (SynthID
    Text style), with the detection mechanism the code also asks for (Commitment 2).
  - It is measured for writing quality and speed before anything ships.
- **Ruled out:** invisible Unicode or zero-width "marks" in inserted text. They are not the
  watermarking the code means, they are fragile, and they would break the user's emails,
  forms and code.

## Roadmap to 2 December 2026 (PRD R26, milestone M6)

1. **Assistant disclosure:** built in #125.
2. **Watermark spike:**
   - A SynthID-Text-style watermark in hush's MLX sampler, plus a detection tool.
   - Measured on the Live Write test set for writing quality, speed, and detection on texts over 200 tokens.
3. **Owner decision:** ship the watermark, or keep texts written by local engines under 200 tokens until it is ready.
4. **alpha.8** released before 2 December 2026 with whatever step 3 decides.
5. **Lawyer review** after the early beta.
