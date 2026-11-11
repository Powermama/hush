<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- Copyright (c) 2026 Clemens Kressmann, for this provenance note only. -->

# Bundled Whisper base model

This directory contains the multilingual Whisper base model in Core ML format.
The existing download script, `macos/scripts/fetch_bundled_model.py`, identifies
its source as the `openai_whisper-base` folder in
[argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml).
That distribution's model card declares the MIT license.

The original [OpenAI Whisper](https://github.com/openai/whisper) weights are
released under MIT. Their copyright and permission notice is retained verbatim
in [LICENSE.OpenAI](LICENSE.OpenAI). Argmax provides the Core ML distribution;
its model card and conversion project remain the source for conversion details.

The imported files are retained as supplied. The original import did not record
an immutable upstream model revision, so this note does not invent one or claim
byte-for-byte correspondence with today's upstream branch. A repository commit
identifies the exact bundled bytes. Future model updates should record the
upstream revision and artifact checksums.

The repository's AGPL default and this note's license do not replace the model's
MIT terms. Separately downloaded models have their own licenses and are not
included by this notice.
