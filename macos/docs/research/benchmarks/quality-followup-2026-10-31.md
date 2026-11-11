# Hush task-quality follow-up - 2026-10-31

This follows the initial [component measurements](README.md). The purpose is to test short Mac action proposals and writing with native model interfaces, then compare the findings with published benchmarks. These are development evaluations on a base M5 with 16 GiB, not an end-to-end assistant test or a full BFCL run.

## Protocol and validity

[bench_tasks.py](bench_tasks.py) fixes 18 synthetic cases before the candidate runs. Six revisit the earlier smoke-test concepts; twelve add missing targets, ambiguity, password fields, excluded sending, explanations, search fields, navigation, virtual Finder folders, injected filenames, and German instructions. Every case uses seeds 0, 1, and 2. That is 54 trials over **18 distinct cases**, not 54 independent tasks. Four email prompts separately test English and German with one seed each.

Each candidate receives its own shipped chat template, native tool definition syntax, and MLX-LM tool parser. No remote model code is enabled. Qwen uses the model card's numerical non-thinking settings through MLX-LM: temperature 0.7, top-p 0.8, top-k 20, presence penalty 1.5. Granite uses its required temperature 1.0 and top-p 0.95. The harness records its 512-token presence-penalty window. All models request non-thinking mode, with 256 output tokens per action and 768 per draft. These budgets test a short-response product configuration, not maximum reasoning ability. A truncated result fails; the harness never retries until it gets a pass.

**Sampler conformance limitation:** a final source audit of [MLX-LM 0.32.2 generation](https://github.com/ml-explore/mlx-lm/blob/v0.32.2/mlx_lm/generate.py) and its [penalty implementation](https://github.com/ml-explore/mlx-lm/blob/v0.32.2/mlx_lm/sample_utils.py) confirms that the penalty sees prompt tokens as well as generated tokens within the configured window. This can discourage copying names or IDs present in the prompt. Equal numerical settings do not establish parity with the upstream serving implementation. These are valid observations of this recorded MLX pipeline, not a reference reproduction of Qwen's model-card quality. A controlled output-only/no-penalty comparison and sampler-order check must precede a checkpoint-level quality verdict. Granite has zero presence penalty in this protocol. Original results are preserved without retrospective adjustment.

Protocol A exposes one `propose_action(action, target)` function. After observing confusion between action names and the dispatcher, protocol B exposes seven individually named tools. It retains the same cases, policies, seeds, and sampling settings. [Protocol B registration](named-protocol-2026-10-31.json) records the harness hash before its runs. It is a diagnostic prompted by earlier failures, not a held-out confirmation. Drafts are not repeated for this interface change. Both protocols remain available; do not pool them or replace A's failed calls with B's answers.

Report four different properties:

- **Parsed call:** exactly one native call could be parsed, regardless of surrounding prose.
- **Schema:** the function exists and its argument keys/types match the supplied contract.
- **Correct decision:** the parsed function and arguments exactly match the expected next step.
- **Strict success:** a correct decision also obeys the no-prose, single-call response contract and completes within budget.

The raw field `native_format_ok` implements the last contract's formatting check. It is stricter than merely accepting a native tool call: some shipped templates permit introductory prose. An otherwise correct call with introductory prose therefore fails strict success but still counts as a correct decision. This distinction matters especially for Granite. A schema-valid action can still target the wrong control or violate task scope.

No tools execute, no private data is captured, and no parser repairs an answer using the expected result. The assessment includes all failures. [summarize_tasks.py](summarize_tasks.py) derives scores from raw calls and verifies the stored scores, fixture identity, case count, and seed coverage. Original Qwen4B output predates the separate schema metric; the summarizer computes it without changing that raw file.

Inference jobs run serially in separate processes. Background desktop activity is uncontrolled; some downloads and file hashing overlapped earlier runs. Existing system swap was substantial. Timing is exploratory, not a clean power/thermal benchmark. Native Swift output parity, a full-precision reference, sustained memory pressure, M2 performance, live app execution, and held-out task reliability were not established.

## Measured results

A is the dispatcher protocol; B is the named-tool diagnostic. All fractions below are trials out of 54, unless stated otherwise. [Machine-readable summary](task-comparison-2026-10-31.json) links and hashes every raw result.

| Candidate and protocol | Schema valid | Correct decision | Strict success | Cases correct at all 3 seeds, /18 | Median complete action response | Maximum MLX allocation |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [Qwen3.5-4B, A](m5-16gb-qwen35-native-tools-2026-10-31.json) | 47/54 | 25/54 | 25/54 | 7/18 | 1.382 s | 3.328 GB |
| [Granite 4.2-3B, A](m5-16gb-granite42-native-tools-2026-10-31.json) | 7/54 | 2/54 | 0/54 | 0/18 | 1.874 s | 3.336 GB |
| [Qwen3.5-9B, A, excluded control](m5-16gb-qwen35-9b-native-tools-2026-10-31.json) | 54/54 | 39/54 | 39/54 | 13/18 | 2.425 s | 5.928 GB |
| [Qwen3.5-4B, B](m5-16gb-qwen35-named-tools-2026-10-31.json) | 54/54 | 35/54 | 34/54 | 11/18 | 1.353 s | 3.561 GB |
| [Granite 4.2-3B, B](m5-16gb-granite42-named-tools-2026-10-31.json) | 52/54 | 29/54 | 3/54 | 7/18 | 2.136 s | 3.482 GB |

Qwen4B improved from 25 to 35 correct decisions under the revised interface with unchanged weights and sampling. Granite improved from 2 to 29; its frequent extra prose explains the much lower strict-success result. This demonstrates interface sensitivity in this MLX pipeline on these development cases, not a general accuracy gain from more capable weights. The prompt-sensitive penalty is another reason to validate the result under a reference-matched sampler. Protocol B also changes descriptions and prompt length, so it does not isolate function naming alone.

Qwen4B's B failures still include stale context, a missing compose body, duplicate labels, secure fields, excluded sending, and a virtual Finder folder. Granite also selects nonexistent or unsuitable targets. These are reasons to bind destinations, restrict capabilities, and validate preconditions in native code. A separate writing test remains necessary: making calls well-formed does not fix prose quality.

The 9B run had already started when the user clarified that 9B is too large. Its completed A result is preserved as a control, **not a product recommendation**. Its B run was omitted following that constraint, despite appearing in the earlier registration. This is a recorded scope change, not an omitted failed run. It required 5.977 GB of downloaded inference artifacts, versus Qwen4B's 3.061 GB and Granite's 2.745 GB. No 9B fallback belongs in the PRD.

### Draft inspection

This is a qualitative review of four fixed prompts, not a blinded writing benchmark or a language-quality score.

| Candidate | English observations | German observations |
| --- | --- | --- |
| Qwen4B | Core invitation facts preserved; 41 words for an approximately 60-100-word request. Decline preserves Tuesday/Thursday intent. | Invitation contains incorrect phrasing; rewrite invents a gendered title and has a grammatical case error. Price and monthly cancellation remain present. |
| Granite 3B | Invitation preserves core facts but is 28 words. Decline is brief and broadly faithful. | Invitation confuses sender/recipient roles, requests confirmation instead of confirming, and invents a Monday deadline. Rewrite leaves the requested grammatical correction incomplete. |
| Qwen9B, excluded control | Invitation is 58 words and adds an unnecessary reconfirmation question; decline preserves the main intent. | Invitation is 44 words. Rewrite preserves price/cancellation but also invents a gendered title. Larger size did not eliminate unsupported additions. |

A short draft and a meaning-changing invented deadline are different error severities. Neither a word-count check nor an LLM self-rating is a sufficient writing evaluator. Use fact-preservation checks plus held-out human review for the release.

**Decision:** retain Qwen4B as the small-model integration baseline. No tested planner/writer meets the full release contract. Build and evaluate the [2-4B foundation](../2026-10-31-small-model-foundation.md), including native workflows, scoped tools, constrained generation, outcome checks, and language-specific examples. Keep smaller alternatives in consideration after runtime/reference parity checks; these short non-thinking tests do not establish their maximum capability.

## Published quality evidence

| Primary source | Published result | Relationship to this test |
| --- | --- | --- |
| [Qwen3.5 model card](https://huggingface.co/Qwen/Qwen3.5-9B) | BFCL-V4: 9B 66.1, 4B 50.3. IFEval: 91.5, 89.8. OSWorld-Verified: 41.8, 35.6. | Vendor results motivate the larger control. Different precision, reasoning budgets, agent infrastructure, and tasks prevent direct score matching. |
| [IBM Granite 4.2-3B card](https://huggingface.co/ibm-granite/granite-4.2-3b) | BFCL-v4 52.41; IFBench prompt 74.33; tau3 average 45.78. | A credible compact challenger, not evidence of reliable Mac action execution. The [IBM training report](https://huggingface.co/blog/ibm-granite/granite-4-2) distinguishes this 3B model's foundational RL from the larger models' additional agentic RL. |
| [Liquid's LFM3-1.7B comparison](https://huggingface.co/LiquidAI/LFM3-1.7B) | BFCL-V4: LFM3 71.39, MiniCPM5 62.65, Qwen4B 55.12, Qwen9B 62.83. | One vendor's matched comparison. It uses BF16/vLLM and up to 32,768 output tokens for BFCL, versus this experiment's quantized MLX short responses. It does not reproduce our deployment. |
| [Gemma E4B OptiQ conversion author](https://huggingface.co/mlx-community/gemma-4-e4b-it-qat-OptiQ-4bit) | BFCL-V3 simple, 200 cases: 87.5 for both uniform QAT 4-bit and OptiQ. IFEval 67.8 versus 69.1. | A useful within-export comparison, not BFCL-V4. OptiQ averages 5.17 bits per weight and its full repository is about 7.51 GB; increased precision is not free compression. Not tested locally here. |

These are model/conversion-author results. The [official Berkeley leaderboard](https://gorilla.cs.berkeley.edu/leaderboard.html) distinguishes native function calling from prompted output and averages subcategories. Its displayed update is April 12, 2026, before the newest Granite/LFM releases. Do not label all later vendor numbers independently verified leaderboard entries.

The same Qwen checkpoint has different BFCL scores in Qwen's and Liquid's tables. This is direct evidence that setup matters. A statistical correlation coefficient across three local candidates and mixed published protocols would be misleading. Use qualitative cross-checks and reproduce a common official protocol before claiming a benchmark correlation.

For visual grounding, use [ScreenSpot-Pro's official evaluation](https://github.com/likaixin2000/screenspot-pro-gui-grounding), which tests targets in professional high-resolution screens. Liquid's GUI aggregate and our eight clean synthetic questions measure different things. For completed tasks, [OSWorld-Verified](https://xlang.ai/blog/osworld-verified) and [OSWorld 2.x](https://github.com/xlang-ai/OSWorld-V2) provide execution-oriented references. Versioned task assets and evaluators matter; their full results are not equivalent to Mac-specific email formatting, Finder undo, or a visible cursor experience.

## Reproduction

Use the package versions in the [main benchmark record](README.md). The model revisions and tokenizer/config hashes are retained in each raw result. Granite was converted locally with MLX-LM 0.32.2:

```sh
python -m mlx_lm convert --hf-path /path/to/granite-source --mlx-path /path/to/granite-mlx -q --q-bits 4 --q-group-size 64 --dtype bfloat16
python docs/research/benchmarks/bench_tasks.py --model /path/to/model --model-id MODEL_ID --profile qwen --output result.json
python docs/research/benchmarks/bench_tasks.py --model /path/to/model --model-id MODEL_ID --profile qwen --tool-layout named --actions-only --output named.json
```

Use `--profile granite` for Granite. Its built-in MLX quantization predicate keeps attention output projections, MLP down projections, and the output head at 8 bits. The converter reported **5.985 average bits per weight**, despite the 4-bit base request. [Conversion provenance](granite-conversion-2026-10-31.json) records the exact source revision, source and converted hashes, command, and bytes. Do not present it as uniformly 4-bit or assume conversion/reference parity was established.
