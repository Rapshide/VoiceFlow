import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var appState = AppStateManager.shared
    private let transcriptionEngine = TranscriptionEngine()
    private var hotkeyManager: GlobalHotkeyManager?
    private var audioRecorder: AudioRecorder?
    private var systemAudioRecorder: SystemAudioRecorder?
    private var pasteEngine: PasteEngine?
    private var floatingPanel: FloatingPanel?
    private let historyStore = HistoryStore()
    private var historyWindowController: HistoryWindowController?
    private var vadMonitor: VADMonitor?
    private let ollamaClient = OllamaClient()
    private var hotwordDetector: HotwordDetector?

    func updateHotkey(_ option: HotkeyOption) {
        hotkeyManager?.updateHotkey(option)
    }

    func showHistory() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController()
        }
        historyWindowController?.show(historyStore: historyStore)
    }

    func reloadModel() {
        let engine = transcriptionEngine
        let state = appState
        Task {
            do {
                try await engine.loadModel { progress in
                    Task { @MainActor in state.modelDownloadProgress = progress }
                }
                let modelName = await engine.loadedModelName
                await MainActor.run {
                    state.isModelLoaded = true
                    state.loadedModelName = modelName
                }
            } catch {
                await MainActor.run {
                    state.state = .error("Model load failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private var activeSource: (any AudioSourceProtocol)? {
        switch appState.audioSource {
        case .microphone: return audioRecorder
        case .systemAudio: return systemAudioRecorder
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppDelegateLocator.shared = self

        audioRecorder = AudioRecorder()
        systemAudioRecorder = SystemAudioRecorder()
        pasteEngine = PasteEngine()

        let panel = FloatingPanel(appState: appState)
        floatingPanel = panel

        let hotkey = GlobalHotkeyManager()
        hotkeyManager = hotkey

        hotkey.onKeyDown = { @Sendable [weak self] in
            await self?.handleKeyDown()
        }
        hotkey.onKeyUp = { @Sendable [weak self] in
            await self?.handleKeyUp()
        }
        let tapCreated = hotkey.start(hotkey: appState.hotkeyOption)
        if !tapCreated {
            appState.state = .error("Accessibility permission needed — open System Settings → Privacy & Security → Accessibility and add VoiceFlow, then relaunch.")
            GlobalHotkeyManager.openAccessibilitySettings()
        }

        // Load WhisperKit model in background
        let engine = transcriptionEngine
        let state = appState
        Task {
            do {
                try await engine.loadModel { progress in
                    Task { @MainActor in
                        state.modelDownloadProgress = progress
                    }
                }
                let modelName = await engine.loadedModelName
                await MainActor.run {
                    state.isModelLoaded = true
                    state.loadedModelName = modelName
                }
            } catch {
                await MainActor.run {
                    state.state = .error("Model load failed: \(error.localizedDescription)")
                }
            }
        }

        // Start hotword detection if enabled
        if appState.hotwordEnabled {
            startHotwordDetector()
        }

        // Check Ollama availability in background
        let ollama = ollamaClient
        Task {
            let available = await ollama.isAvailable()
            let models = available ? await ollama.availableModels() : []
            await MainActor.run {
                state.isOllamaAvailable = available
                state.ollamaModels = models
            }
        }
    }

    func updateHotwordDetection() {
        if appState.hotwordEnabled {
            startHotwordDetector()
        } else {
            hotwordDetector?.stop()
            hotwordDetector = nil
        }
    }

    func refreshOllamaModels() {
        let ollama = ollamaClient
        let state = appState
        Task {
            let available = await ollama.isAvailable()
            let models = available ? await ollama.availableModels() : []
            await MainActor.run {
                state.isOllamaAvailable = available
                state.ollamaModels = models
            }
        }
    }

    // MARK: - Hotkey handlers

    private func handleKeyDown() async {
        switch appState.recordingMode {
        case .pushToTalk:
            await startRecording()
        case .vadToggle:
            if case .idle = appState.state {
                await startRecording()
                startVADMonitor()
            } else if case .recording = appState.state {
                // Manual stop in VAD mode
                vadMonitor?.stop()
                await stopAndTranscribe()
            }
        }
    }

    private func handleKeyUp() async {
        // Only push-to-talk uses key up
        guard appState.recordingMode == .pushToTalk else { return }
        await stopAndTranscribe()
    }

    // MARK: - Recording flow

    private func startRecording() async {
        guard case .idle = appState.state else { return }

        // Pause hotword detector during recording (shared mic)
        hotwordDetector?.stop()

        appState.trackFrontmostApp()

        guard let source = activeSource else { return }
        let granted = await source.requestPermission()
        guard granted else {
            appState.state = .error("Permission denied")
            restartHotwordIfEnabled()
            return
        }

        do {
            try source.start()
            appState.state = .recording
        } catch {
            appState.state = .error("Failed to start recording: \(error.localizedDescription)")
            restartHotwordIfEnabled()
        }
    }

    private func restartHotwordIfEnabled() {
        if appState.hotwordEnabled {
            startHotwordDetector()
        }
    }

    private func stopAndTranscribe() async {
        guard case .recording = appState.state else { return }

        let samples = activeSource?.stop() ?? []
        let pid = appState.frontmostAppPID
        let lang = appState.language
        let sourceType = appState.audioSource == .systemAudio ? "system" : "mic"
        let ppMode = appState.postProcessMode
        let ppModel = appState.ollamaModel
        let ppCustomPrompt = appState.customLLMPrompt

        appState.state = .transcribing

        let engine = transcriptionEngine
        let state = appState
        let paste = pasteEngine
        let history = historyStore
        let ollama = ollamaClient
        Task {
            do {
                let result = try await engine.transcribe(audio: samples, language: lang)
                var finalText = result.text

                // LLM post-processing (if enabled and Ollama is available)
                if ppMode != .none && !ppModel.isEmpty {
                    await MainActor.run { state.state = .postProcessing }
                    do {
                        finalText = try await ollama.process(
                            text: result.text,
                            mode: ppMode,
                            customPrompt: ppCustomPrompt,
                            model: ppModel
                        )
                    } catch {
                        // Fall back to raw text on LLM failure
                        finalText = result.text
                    }
                }

                let finalResult = DictationResult(text: finalText, words: result.words, duration: result.duration)
                await MainActor.run {
                    state.state = .showingResult(finalResult)
                    history.add(finalResult, language: lang, source: sourceType)
                }
                await paste?.paste(text: finalText, toPID: pid)
            } catch {
                await MainActor.run {
                    state.state = .error("Transcription failed: \(error.localizedDescription)")
                }
            }
            // Restart hotword detection after transcription completes
            await MainActor.run { [weak self] in
                self?.restartHotwordIfEnabled()
            }
        }
    }

    private func startHotwordDetector() {
        hotwordDetector?.stop()
        let detector = HotwordDetector()
        detector.hotword = appState.hotword
        detector.transcriptionEngine = transcriptionEngine
        detector.onHotwordDetected = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, case .idle = self.appState.state else { return }
                self.hotwordDetector?.stop()
                await self.startRecording()
                if self.appState.recordingMode == .vadToggle {
                    self.startVADMonitor()
                }
            }
        }
        detector.start()
        hotwordDetector = detector
    }

    private func startVADMonitor() {
        guard let source = activeSource else { return }
        let monitor = VADMonitor()
        vadMonitor = monitor
        monitor.onSilenceDetected = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.stopAndTranscribe()
            }
        }
        monitor.start(source: source, silenceTimeout: appState.silenceTimeout)
    }
}
