# VoiceFlow

A native macOS speech-to-text app inspired by Wispr Flow, running **fully on-device** with no cloud dependency, no subscription, and complete privacy.

Built with Swift/SwiftUI + [WhisperKit](https://github.com/argmaxinc/WhisperKit) (CoreML / Apple Neural Engine).

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![License MIT](https://img.shields.io/badge/license-MIT-green)

---

## Features

### v1 — Core dictation
- **Global hotkey** — hold a right-side modifier key (⌥ ⌘ ⌃ or ⇧) to record, release to transcribe
- **Universal paste** — result injected at the cursor via `NSPasteboard` + Cmd+V CGEvent; works in any app
- **Hungarian + English** — explicit language selection; defaults to Hungarian
- **On-device only** — WhisperKit with `whisper large-v3-turbo` via CoreML / Apple Neural Engine
- **Floating UI** — always-on-top pill panel with animated waveform and status indicators
- **Menu bar agent** — no Dock icon; keeps focus in your target app while pasting

### v2 — Power features
- **VAD toggle mode** — automatic silence detection ends recording; configurable timeout (0.5–5s); push-to-talk remains available
- **History panel** — browse, search, copy and export past transcriptions; persisted to JSON
- **System audio capture** — transcribe meetings, YouTube, any audio playing on your Mac (via ScreenCaptureKit)
- **Hotword activation** — say your wake word (default: "Voice") to start recording hands-free
- **LLM post-processing** — clean up grammar, reformat, summarize, or apply a custom prompt via a local [Ollama](https://ollama.com) model
- **Export** — save transcriptions as Markdown, plain text, or JSON (single or batch)

### v3 — Hotkey overhaul & UX polish
- **Arbitrary hotkey recorder** — bind any key + any modifier combination (e.g. Right ⌥, ⌃⇧M, F5) via a live key recorder in Settings; multi-modifier combos detected order-independently
- **Source-toggle hotkey** — switch between Microphone and System Audio instantly with a dedicated hotkey (default: ⌃⇧M), without opening Preferences; brief on-screen toast confirms the switch
- **System audio push-to-stop** — press hotkey to start system audio recording (after GDPR consent), press again to stop and transcribe; mic is mixed in automatically
- **History hotkey** — press ⌘⇧H from anywhere to open the History window
- **History search auto-focus** — typing while the History window is focused redirects keystrokes to the search bar automatically
- **History layout fix** — search no longer causes the split-view sidebar to resize unexpectedly

---

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1 or newer) — recommended for Neural Engine acceleration
- ~1.5 GB free disk space (for the Whisper model, downloaded on first launch)

### Optional
- [Ollama](https://ollama.com) running locally for LLM post-processing
- Screen Recording permission for system audio capture

---

## Build

```bash
# Clone
git clone https://github.com/Rapshide/VoiceFlow.git
cd VoiceFlow

# Build and sign the app bundle
bash scripts/make-app.sh

# Launch
open VoiceFlow.app
```

> **First-run setup (one time only)**
> 1. Open **System Settings → Privacy & Security → Accessibility**
> 2. Remove any existing VoiceFlow entry, then add `VoiceFlow.app` and toggle it **ON**
> 3. Relaunch the app — you won't be prompted again

---

## First Launch

On first launch, VoiceFlow downloads the `whisper large-v3-turbo` CoreML model (~800 MB) from HuggingFace to `~/Library/Application Support/VoiceFlow/`. Subsequent launches load the model from cache with no network calls.

---

## Usage

### Push-to-talk (default)
1. Click wherever you want to type
2. **Hold** your hotkey (default: Right ⌥)
3. Speak
4. **Release** — transcription is pasted at the cursor

### VAD toggle mode
1. Enable in **Settings → Recording → Mode → VAD Toggle**
2. **Press** your hotkey once to start
3. Speak — recording stops automatically after silence (configurable)
4. Or press the hotkey again to stop manually

### System audio recording
1. Select **System Audio** in **Settings → Recording → Audio Source** (or press the source-toggle hotkey)
2. **Press** your hotkey — a GDPR consent prompt appears; confirm to start
3. Speak and/or let audio play — your mic and system audio are mixed together
4. **Press** the hotkey again — transcription is pasted at the cursor

### Hotkey customisation
- Open **Settings → Hotkeys**
- Click **Record** next to the hotkey you want to change
- Press any key or modifier combination — release all keys to confirm
- Press **Escape** to cancel

### History
- Press **⌘⇧H** from anywhere, or click **History…** in the menu bar
- Start typing immediately to search — keystrokes go to the search bar automatically
- Search, copy, delete individual entries, or export as Markdown / text / JSON

### Hotword activation
1. Enable in **Settings → Hotword**
2. Set your wake word (default: `Voice`)
3. Say your wake word — recording starts automatically

### LLM post-processing
1. Install [Ollama](https://ollama.com) and pull a model: `ollama pull llama3`
2. Open **Settings → Post-processing** and select a mode + model
3. Transcriptions will be cleaned up / reformatted before pasting

---

## Architecture

```
Sources/VoiceFlow/
├── App/
│   ├── VoiceFlowApp.swift          @main, MenuBarExtra, Settings scene
│   ├── AppDelegate.swift           Engine wiring, recording/transcription flow
│   └── AppStateManager.swift       @Observable state machine
├── Audio/
│   ├── AudioSource.swift           Protocol + RecordingMode/AudioSourceSelection enums
│   ├── AudioRecorder.swift         AVAudioEngine mic capture → 16kHz Float32
│   ├── SystemAudioRecorder.swift   ScreenCaptureKit system audio capture
│   ├── CombinedAudioRecorder.swift Mic + system audio mixed (hard-clip Float32)
│   ├── VADMonitor.swift            EnergyVAD-based silence detection
│   └── HotwordDetector.swift       Always-on mic + rolling WhisperKit wake word check
├── Transcription/
│   ├── TranscriptionEngine.swift   WhisperKit actor, model caching
│   └── TranscriptionResult.swift   DictationResult / DictationWord structs
├── Output/
│   └── PasteEngine.swift           NSPasteboard save/restore + Cmd+V CGEvent
├── HotKey/
│   ├── GlobalHotkeyManager.swift   CGEventTap — flagsChanged + keyDown/keyUp
│   └── HotkeyConfig.swift          Codable hotkey struct (keyCode + modifiers)
├── History/
│   ├── HistoryEntry.swift          Codable entry struct
│   └── HistoryStore.swift          JSON persistence, 500-entry limit
├── Export/
│   └── ExportEngine.swift          .md / .txt / .json via NSSavePanel
├── LLM/
│   ├── OllamaClient.swift          URLSession actor → Ollama HTTP API
│   └── PostProcessMode.swift       Mode enum with system prompts
└── UI/
    ├── FloatingPanel.swift         Borderless .floating NSPanel
    ├── FloatingPanelView.swift     Waveform / spinner / result / source-notification states
    ├── HistoryWindow.swift         NSWindowController + key-redirect monitor
    ├── HistoryView.swift           NavigationSplitView with custom search + FocusState
    ├── KeyRecorderView.swift       Live hotkey capture with multi-modifier support
    ├── MenuBarView.swift           Status + History + Preferences + Quit
    └── SettingsView.swift          All preferences
```

**Recording state machine:**
```
idle → recording → transcribing → [postProcessing] → showingResult → idle
                                                    ↑
                                            (if Ollama mode set)
```

---

## Tech stack

| Layer | Choice |
|---|---|
| Language | Swift 5.9 |
| UI | SwiftUI + AppKit |
| Transcription | WhisperKit (CoreML / Apple Neural Engine) |
| Model | whisper large-v3-turbo (MIT) |
| Audio capture | AVFoundation (mic), ScreenCaptureKit (system) |
| VAD | WhisperKit's built-in `EnergyVAD` |
| Output | CGEvent + NSPasteboard |
| LLM | Ollama HTTP API (optional) |
| Distribution | Direct .app (non-sandboxed) |

---

## Permissions required

| Permission | Why |
|---|---|
| Accessibility | CGEventTap for global hotkey + Cmd+V injection |
| Microphone | Voice capture |
| Screen Recording | System audio capture (optional, ScreenCaptureKit) |

---

## License

MIT — see [LICENSE](LICENSE).

Model weights: `openai/whisper` — MIT License.
WhisperKit — MIT License.
