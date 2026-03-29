# VoiceFlow v2 Implementation Plan

## Context

VoiceFlow v1 is a working macOS speech-to-text app with push-to-talk dictation. The research doc at `/Users/rapcsakpal/Desktop/Personal/10 Work/Projects/Speech-to-Text Mac App Research.md` defines six v2 features. This plan implements all of them while preserving the existing v1 push-to-talk flow.

## V2 Features (in implementation order)

1. History panel (recent transcriptions)
2. Export to Markdown / plain text
3. VAD for automatic start/stop
4. System audio capture
5. Local LLM post-processing (via Ollama)
6. Hotword activation

---

## 1. History Panel

**Storage:** JSON file at `~/Library/Application Support/VoiceFlow/history.json`. 500 entries max, oldest pruned on save. No Core Data — overkill for this volume.

**New files:**
- `Sources/VoiceFlow/History/HistoryEntry.swift` — `struct HistoryEntry: Codable, Identifiable` with id, text, language, duration, timestamp, source
- `Sources/VoiceFlow/History/HistoryStore.swift` — `@Observable @MainActor` class: load/save JSON, add/delete/clearAll, sorted newest-first
- `Sources/VoiceFlow/UI/HistoryWindow.swift` — Standard `NSWindow` (not floating), hosts HistoryView
- `Sources/VoiceFlow/UI/HistoryView.swift` — List with timestamp, language badge, truncated preview. Click to expand. Copy button. Search via `.searchable`. Clear All in toolbar.

**Modified files:**
- `TranscriptionResult.swift` — Add `Codable` conformance to `DictationResult` and `DictationWord`
- `AppDelegate.swift` — Create `HistoryStore`, call `historyStore.add()` after successful transcription
- `MenuBarView.swift` — Add "History..." button that opens the history window

---

## 2. Export

**Formats:** `.md`, `.txt`, `.json`. Single entry or batch export.

**New files:**
- `Sources/VoiceFlow/Export/ExportEngine.swift` — Static methods: `exportMarkdown()`, `exportPlainText()`, `exportJSON()`, `exportBatchMarkdown()`. Uses `NSSavePanel` for single, `NSOpenPanel` (directory) for batch.

**Modified files:**
- `HistoryView.swift` — Export button per entry + batch export in toolbar with format picker

---

## 3. VAD Toggle Mode

**Approach:** Use WhisperKit's built-in `EnergyVAD` (already in dependency tree). No new packages needed.

**Mode:** User picks "Push-to-Talk" (v1 default) or "VAD Toggle" in settings. In VAD mode, hotkey toggles recording on/off. Silence auto-stops recording after configurable timeout (default 1.5s, range 0.5-5.0s).

**New files:**
- `Sources/VoiceFlow/Audio/AudioSource.swift` — Protocol `AudioSourceProtocol` with `requestPermission()`, `start()`, `stop() -> [Float]`, `recentSamples(last:)`
- `Sources/VoiceFlow/Audio/VADMonitor.swift` — Wraps `EnergyVAD`, checks tail of audio buffer every ~200ms, fires `onSilenceDetected` callback when silence exceeds threshold

**Modified files:**
- `AudioRecorder.swift` — Conform to `AudioSourceProtocol`, add `recentSamples(last:)` method
- `AppStateManager.swift` — Add `recordingMode: RecordingMode` enum (`.pushToTalk`, `.vadToggle`), `silenceTimeout: Double`
- `AppDelegate.swift` — Branch hotkey logic by mode:
  - Push-to-talk: existing hold-to-record behavior
  - VAD toggle: keyDown toggles recording, keyUp is ignored. Create `VADMonitor`, wire `onSilenceDetected` to stop recording + transcribe
- `GlobalHotkeyManager.swift` — Suppress `onKeyUp` in VAD toggle mode
- `SettingsView.swift` — Recording Mode picker, silence timeout slider
- `FloatingPanelView.swift` — Show "Recording (auto-stop)..." in VAD mode

---

## 4. System Audio Capture

**Approach:** `ScreenCaptureKit` (`SCStream`) with audio-only config. macOS 14+ compatible. No virtual audio drivers needed.

**Limitation:** Mic and system audio are mutually exclusive in v2 (no mixing). User picks source before recording.

**New files:**
- `Sources/VoiceFlow/Audio/SystemAudioRecorder.swift` — Conforms to `AudioSourceProtocol`. Uses `SCStreamConfiguration` with `capturesAudio = true`, 16kHz mono. Implements `SCStreamOutput` to receive `CMSampleBuffer`, converts to `[Float]`.

**Modified files:**
- `AppStateManager.swift` — Add `audioSource: AudioSourceSelection` enum (`.microphone`, `.systemAudio`)
- `AppDelegate.swift` — Hold both recorders, pick active one based on `appState.audioSource`
- `SettingsView.swift` — Audio Source picker with Screen Recording permission note
- `Info.plist` — Add `NSScreenCaptureUsageDescription`

---

## 5. Local LLM Post-processing

**Approach:** Ollama HTTP API (`localhost:11434`). No Swift package dependencies — just `URLSession`.

**Modes:** None (default), Clean up, Formal, Summary, Custom prompt.

**Flow:** After transcription, before paste. New state `.postProcessing` in the state machine. Falls back to raw text if Ollama unavailable (30s timeout).

**New files:**
- `Sources/VoiceFlow/LLM/OllamaClient.swift` — Actor: check availability via `/api/tags`, process text via `/api/generate`, list models, 30s timeout
- `Sources/VoiceFlow/LLM/PostProcessMode.swift` — Enum with system prompts per mode

**Modified files:**
- `AppStateManager.swift` — Add `postProcessMode`, `customLLMPrompt`, `ollamaModel`, `isOllamaAvailable`. Add `.postProcessing` to `RecordingState`
- `AppDelegate.swift` — Create `OllamaClient`. After transcription, if mode != .none, set `.postProcessing` state, call Ollama, update result text. Check availability on launch.
- `FloatingPanelView.swift` — Handle `.postProcessing` state (spinner + "Cleaning up...")
- `MenuBarView.swift` — Handle `.postProcessing` in status text/icon
- `VoiceFlowApp.swift` — Handle `.postProcessing` in `MenuBarIcon`
- `SettingsView.swift` — Post-processing section: mode picker, model picker, custom prompt field, test connection button

---

## 6. Hotword Activation

**Approach:** Always-on mic (separate `AVAudioEngine`) + `EnergyVAD` gate + periodic WhisperKit transcription on 3-second windows. Checks if output contains wake word. Opt-in feature with battery warning.

**New files:**
- `Sources/VoiceFlow/Audio/HotwordDetector.swift` — Maintains rolling 3s audio buffer, EnergyVAD gates WhisperKit calls (~1s intervals), fires `onHotwordDetected` on match

**Modified files:**
- `AppStateManager.swift` — Add `hotwordEnabled: Bool`, `hotword: String`
- `AppDelegate.swift` — Create `HotwordDetector`, wire to `handleKeyDown()` flow. Stop detector during recording.
- `SettingsView.swift` — Hotword section: toggle, wake word text field, battery warning

---

## New Directory Structure

```
Sources/VoiceFlow/
  Audio/
    AudioRecorder.swift        (modified)
    AudioSource.swift          (new)
    SystemAudioRecorder.swift  (new)
    VADMonitor.swift           (new)
    HotwordDetector.swift      (new)
  History/
    HistoryEntry.swift         (new)
    HistoryStore.swift         (new)
  Export/
    ExportEngine.swift         (new)
  LLM/
    OllamaClient.swift         (new)
    PostProcessMode.swift      (new)
```

## No New Package Dependencies

All features use existing frameworks:
- History/Export: Foundation
- VAD: WhisperKit's `EnergyVAD` (already bundled)
- System Audio: ScreenCaptureKit (system framework)
- LLM: URLSession → Ollama HTTP API
- Hotword: Existing WhisperKit + EnergyVAD

## RecordingState Changes

```swift
enum RecordingState {
    case idle
    case recording
    case transcribing
    case postProcessing        // NEW
    case showingResult(DictationResult)
    case error(String)
}
```

Every `switch` on `RecordingState` must be updated (5 locations: FloatingPanelView, MenuBarView, MenuBarIcon, and the new HistoryView context).

## Verification

After each feature:
1. `swift build` must succeed
2. `bash scripts/make-app.sh` produces a working app
3. Manual test: open app, verify menu bar icon, test the feature
4. Verify v1 push-to-talk still works (regression check)

Feature-specific tests:
- **History:** Transcribe something, open History window, verify entry appears. Quit and relaunch, verify persistence.
- **Export:** Export a single entry as .md, verify file content. Export batch as .json.
- **VAD:** Switch to VAD Toggle mode, press hotkey, speak, stop speaking, verify auto-stop after silence timeout.
- **System Audio:** Switch to System Audio source, play a YouTube video, record, verify transcription of system audio.
- **LLM:** Install Ollama + a model, set mode to "Clean up", transcribe something, verify post-processed output.
- **Hotword:** Enable hotword, say "Voice", verify recording starts automatically.
