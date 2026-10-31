# Components and licenses

- Argmax Open Source Swift SDK / WhisperKit: MIT, vendored from
  https://github.com/argmaxinc/argmax-oss-swift at
  `9f99b5cb6a907730543823ad271b82532782a899`.
  Original LICENSE and NOTICES remain under Vendor/argmax-oss-swift.
  Its included tokenizer implementations retain their original notices.
- Apple swift-argument-parser: Apache-2.0; resolved by SPM for the vendor package.
  Only WhisperKit and ArgmaxCore are linked into the application.
- Whisper small/base multilingual weights: OpenAI Whisper MIT;
  converted Core ML files from https://huggingface.co/argmaxinc/whisperkit-coreml.
  Tokenizer files from https://huggingface.co/openai/whisper-small.
- SQLite: public domain, linked from macOS.
- SwiftUI, AppKit, AVFoundation, ScreenCaptureKit, CoreAudio, Core ML:
  macOS system frameworks. No paid Apple Developer membership is needed.
- Ollama: external installation already present on this Mac, accessed through
  loopback HTTP only. No Ollama binaries or LLM weights are redistributed.
  Individual LLM licenses apply to the models chosen by the user.

## Offline tokenizer patch

The vendored SDK has two small additions:
`WhisperKit.allowTokenizerDownload` and a corresponding
`ModelUtilities.loadTokenizer(..., allowDownload:)` argument. The default keeps
upstream behavior. LocalCopilot sets it to false before loading models so a
missing/corrupt local tokenizer cannot trigger a network fallback. Dependency
updates must retain this patch and rerun offline checks. See the vendor Git diff.

## Offline answer renderer

Official npm distributions bundled in Resources/AnswerRenderer:
- KaTeX 0.19.0 — MIT.
- Marked 18.1.0 — MIT; contribution/license notices retained.
- DOMPurify 3.4.16 — Apache-2.0 OR MPL-2.0.

Full license notices and versions.json are next to the assets. No CDN is used.
Qwen2.5-Coder and Qwen3.5 model weights stay in the existing Ollama installation;
model licenses apply (see `ollama show --license MODEL`). No weights redistributed.

## Whisper Large v3 Turbo model

OpenAI Whisper Large v3 Turbo: MIT license.
Model/tokenizer: https://huggingface.co/openai/whisper-large-v3-turbo
Core ML conversion by Argmax: https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3-v20240930_turbo
Model files are downloaded to local Application Support, not embedded in the app bundle.
