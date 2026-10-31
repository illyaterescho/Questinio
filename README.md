# Questionio

**English** · [Українська](README.uk.md)

Free, local-first AI meeting assistant for macOS (Apple Silicon, macOS 14+).
It transcribes a call or your microphone on-device, detects questions, and
streams answers from a local LLM, optionally grounded in a code folder you pick.
No cloud APIs, no accounts, no subscription.

> Source folder, Xcode scheme and Swift module still use the old name
> `LocalCopilot` for compatibility.

## Features

- **Two audio channels**: app/system audio (Core Audio Tap or ScreenCaptureKit)
  and microphone, transcribed separately, so you always know who spoke.
- **On-device speech recognition**: WhisperKit (Core ML), small / base /
  large-v3-turbo, or the optional Parakeet TDT v3 (FluidAudio, Neural Engine):
  10+× faster and lighter, less accurate on Ukrainian IT terms. Network fallback
  is disabled during recognition.
- **Light when idle**: the LLM stays loaded only while capturing and unloads
  15 min after Stop; the project folder is rescanned only during capture.
- **Question inbox**: detects finished questions after a pause, keeps the
  conversation context at the moment each question was asked, tracks
  interrupted or rephrased questions.
- **Local answers**: Ollama (`/api/chat`, streaming). Thinking models supported.
- **Code context**: connect a project folder; relevant fragments with exact line
  numbers are sent with code questions ("what does line 129 do?", "where is X
  defined?"). Optional JetBrains editor reading via Accessibility.
- **Rendering**: Markdown, code and LaTeX via bundled marked + DOMPurify + KaTeX.
- **History**: SQLite + JSONL session journal, export and restore.

## Requirements

- Xcode, Homebrew OpenSSL (for local signing), [Ollama](https://ollama.com)
  running on `http://127.0.0.1:11434` with at least one chat model, e.g.
  `ollama pull qwen3:4b`.
- A Whisper model, downloaded once from Settings → Speech Recognition.

## Build

```sh
./scripts/setup-local-signing.sh  # once per Mac: stable local signing identity
./scripts/test.sh
./scripts/build.sh
open dist/Questionio.app
```

The signing key lives in `~/Library/Application Support/Questionio/Signing`,
outside the repository. Builds are local and not notarized.

## Permissions

System Settings → Privacy & Security:

1. **Microphone** — for Microphone / Both modes.
2. **Screen & System Audio Recording → System Audio Recording Only** — for
   Core Audio Tap (default).
3. **Screen & System Audio Recording** — for screen context and the
   ScreenCaptureKit audio fallback.

## Usage

- **Start** begins capture; grey text is interim, confirmed after a pause.
- **Generate Answer** answers the typed text or the last finished question.
  Pick any earlier question from the inbox to answer it with its own context.
- Automatic answers are optional; questions from your own microphone don't
  trigger generation unless enabled.
- Hotkeys: **⌃⌥⌘G** answer, **⌃⌥⌘R** start/stop, **⌃⌥⌘P** floating window.

## Architecture

- `Sources/LocalCopilotCore` — testable core: settings, SQLite storage,
  Ollama client, WhisperKit wrapper, VAD, speech pipeline, transcript assembly,
  question detection / inbox, session journal, project code index.
- `App/Audio` — microphone, system audio, PCM conversion to mono 16 kHz.
- `App/Services` — `ConversationManager` (main view model), project / IDE /
  screen context, permissions, hotkeys, diagnostics.
- `App/UI` — SwiftUI views and the answer web renderer.
- `Vendor/argmax-oss-swift` — patched WhisperKit (see `THIRD_PARTY.md`).

## Local data

`~/Library/Application Support/LocalCopilot/`: `settings.json`,
`history.sqlite`, `Sessions/*.jsonl`, `Models/`. No audio recordings are kept;
overflow PCM goes to a private temp folder and is deleted after decoding.
History → Delete all removes answers and session journals.

## Probe CLI

```sh
swift run LocalCopilotProbe                       # list models, test one answer
swift run LocalCopilotProbe --download --variant openai_whisper-small
swift run LocalCopilotProbe --transcribe sample.wav
swift run LocalCopilotProbe --download-parakeet
swift run LocalCopilotProbe --transcribe a.wav b.wav --engine parakeet --language uk
```

## License

See `LICENSE` and `THIRD_PARTY.md`.
