# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

```bash
# Build, bundle, and ad-hoc sign the app
bash scripts/make-app.sh
```

This runs `swift build` (debug), assembles `VoiceFlow.app`, and applies the entitlements from `VoiceFlow.entitlements`. The output is `VoiceFlow.app` in the project root.

There are no tests and no linter configured.

## Architecture

VoiceFlow is a menu-bar-only macOS app (LSUIElement=true) that performs on-device speech-to-text via WhisperKit. All source is under `Sources/VoiceFlow/`.

**State machine** — `AppStateManager` (singleton `@Observable`) owns `RecordingState` (idle → recording → transcribing → postProcessing → showingResult → idle). All state transitions flow through it.

**Orchestration** — `AppDelegate` wires all engines together. It handles hotkey callbacks, kicks off the recording/transcription pipeline, writes history, and triggers paste.

**Audio pipeline** — Two `AudioSource` implementations: `AudioRecorder` (mic via AVAudioEngine) and `SystemAudioRecorder` (ScreenCaptureKit). Both output 16kHz Float32 PCM consumed by `TranscriptionEngine`.

**Transcription** — `TranscriptionEngine` is a Swift `actor` wrapping WhisperKit. It caches the `whisper-large-v3-turbo` model in `~/Library/Application Support/VoiceFlow/` after first download (~800 MB from HuggingFace).

**Text delivery** — `PasteEngine` saves the current clipboard, writes the transcription, synthesizes CGEvent Cmd+V to the frontmost app, then restores the clipboard.

**Optional LLM post-processing** — `OllamaClient` (actor) calls Ollama at `localhost:11434` with one of the `PostProcessMode` system prompts (cleanup / formal / summary / custom).

**Hotword detection** — `HotwordDetector` keeps a rolling 3-second audio buffer on the mic at all times; when VAD fires it runs a transcription check for the configured wake word.

**Persistence** — `HistoryStore` writes up to 500 entries to `~/Library/Application Support/VoiceFlow/history.json`. User settings are in `UserDefaults`.

## Required permissions

The app needs **Accessibility** (CGEventTap for global hotkey + Cmd+V injection) and **Microphone**. Screen Recording is optional (system audio mode). Grant these in System Settings on first launch.

## Key dependencies

- **WhisperKit** (v0.17.0) — the only direct SPM dependency; all others are transitive.
- **Ollama** (external, optional) — local LLM server at `localhost:11434`.
