# Preparation stall diagnosis

Measured on the development base M5 MacBook Pro, 16 GB, macOS 26.3, with the installed Qwen3.5-4B tokenizer. Debug app built with Swift optimization enabled. No model weights are loaded by the isolated grammar test. These are local single-run diagnostics, not a model-quality or end-to-end browser benchmark.

## User-visible reproduction

The greeting trace accepted speech and prepared its input at 1.904 seconds, then did not leave grammar preparation before cancellation unwound at 60.134 seconds. Escape had stopped the UI at 9.082 seconds. A following dinner-invitation request entered the model at 4.044 seconds but only prepared its input at 47.293 seconds, after waiting behind the previous operation. Both permissions were granted; speech recognition completed 87-208 ms after the transcribing stage. Neither request produced a model reply or dispatched an action.

## Isolated test

`AssistantGrammarTests.installedTokenizerPreparation` compares the frozen pre-fix response schema with an otherwise identical version that removes `subject.maxLength:300`. It uses `GrammarMaskedLogitProcessor.from` and the same installed tokenizer in fresh test processes. The bounded-string version is retained only as an opt-in benchmark baseline.

| Order | Preparation | Seconds |
| --- | --- | ---: |
| Bounded first | Bounded schema, cold tokenizer | 65.212856292 |
| Bounded first | Unbounded-string schema, tokenizer ready | 0.006041583 |
| Bounded first | Bounded cached | 0.000105375 |
| Reversed | Unbounded-string schema, cold tokenizer | 2.141437958 |
| Reversed | Bounded schema, tokenizer ready | 57.766044875 |
| Reversed | Bounded cached | 0.000698209 |

Reversing the order separates tokenizer startup from schema compilation. A stack sample during the bounded case shows XGrammar's JSON-schema compiler and Earley parser processing states. This attributes the major delay to the character-count grammar, rather than Qwen inference, speech recognition, or screen capture. The first attempted test exited before completion and provides no measurement; the two completed runs above are the evidence.

## Change and limits

The production grammar retains required fields, types, action enums, and numeric constraints. Native reply decoding still rejects subjects longer than 300 characters and content longer than 6,000 characters. Per-request shortening limits remain in the prompt and native validation with bounded repair. Character-count grammar expansion is removed, including dynamic draft limits that could cause another compilation spike. Cancelled work checks cancellation before model loading and again on entry to the shared model container and after prompt preparation.

The isolated measurement does not include model loading, prompt/image prefill, output generation, TTS, or native desktop actions. The complete Safari/YouTube sequence must be reported separately. Faster preparation alone does not establish improved task accuracy.
