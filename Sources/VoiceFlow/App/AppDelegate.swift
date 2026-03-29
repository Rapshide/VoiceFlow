import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var appState = AppStateManager.shared
    private let transcriptionEngine = TranscriptionEngine()
    private var hotkeyManager: GlobalHotkeyManager?
    private var audioRecorder = AudioRecorder()           // mic-only mode
    private var combinedRecorder = CombinedAudioRecorder() // system audio mode (mic + system)
    private var pasteEngine: PasteEngine?
    private var floatingPanel: FloatingPanel?
    private let historyStore = HistoryStore()
    private var historyWindowController: HistoryWindowController?
    private var vadMonitor: VADMonitor?
    private let ollamaClient = OllamaClient()
    private var hotwordDetector: HotwordDetector?

    // MARK: - Public API (called from SettingsView via AppDelegateLocator)

    func updateRecordingHotkey(_ config: HotkeyConfig) {
        hotkeyManager?.updateRecordingHotkey(config)
    }

    func updateSourceToggleHotkey(_ config: HotkeyConfig) {
        hotkeyManager?.updateSourceToggleHotkey(config)
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
                    state.isModelLoaded   = true
                    state.loadedModelName = modelName
                }
            } catch {
                await MainActor.run {
                    state.state = .error("Model load failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func refreshOllamaModels() {
        let ollama = ollamaClient
        let state  = appState
        Task {
            let available = await ollama.isAvailable()
            let models    = available ? await ollama.availableModels() : []
            await MainActor.run {
                state.isOllamaAvailable = available
                state.ollamaModels      = models
            }
        }
    }

    func updateHotwordDetection() {
        if appState.hotwordEnabled { startHotwordDetector() }
        else { hotwordDetector?.stop(); hotwordDetector = nil }
    }

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppDelegateLocator.shared = self

        pasteEngine  = PasteEngine()
        floatingPanel = FloatingPanel(appState: appState)

        let hotkey = GlobalHotkeyManager()
        hotkeyManager = hotkey

        hotkey.onRecordingKeyDown = { @Sendable [weak self] in await self?.handleKeyDown() }
        hotkey.onRecordingKeyUp   = { @Sendable [weak self] in await self?.handleKeyUp()   }
        hotkey.onSourceToggle     = { @Sendable [weak self] in await self?.handleSourceToggle() }
        hotkey.onOpenHistory      = { @Sendable [weak self] in await self?.handleOpenHistory() }

        let tapCreated = hotkey.start(
            recordingHotkey:    appState.recordingHotkey,
            sourceToggleHotkey: appState.sourceToggleHotkey
        )
        if !tapCreated {
            appState.state = .error("Accessibility permission needed — open System Settings → Privacy & Security → Accessibility and add VoiceFlow, then relaunch.")
            GlobalHotkeyManager.openAccessibilitySettings()
        }

        let engine = transcriptionEngine
        let state  = appState
        Task {
            do {
                try await engine.loadModel { progress in
                    Task { @MainActor in state.modelDownloadProgress = progress }
                }
                let modelName = await engine.loadedModelName
                await MainActor.run {
                    state.isModelLoaded   = true
                    state.loadedModelName = modelName
                }
            } catch {
                await MainActor.run {
                    state.state = .error("Model load failed: \(error.localizedDescription)")
                }
            }
        }

        if appState.hotwordEnabled { startHotwordDetector() }

        let ollama = ollamaClient
        Task {
            let available = await ollama.isAvailable()
            let models    = available ? await ollama.availableModels() : []
            await MainActor.run {
                state.isOllamaAvailable = available
                state.ollamaModels      = models
            }
        }
    }

    // MARK: - Active audio source

    private var activeSource: (any AudioSourceProtocol) {
        switch appState.audioSource {
        case .microphone:  return audioRecorder
        case .systemAudio: return combinedRecorder
        }
    }

    // MARK: - Hotkey handlers

    private func handleKeyDown() async {
        switch appState.audioSource {

        case .systemAudio:
            // System audio uses push-to-STOP (no VAD):
            // first press → start (after GDPR consent), second press → stop & transcribe.
            if case .idle = appState.state {
                await startRecording()
            } else if case .recording = appState.state {
                await stopAndTranscribe()
            }

        case .microphone:
            switch appState.recordingMode {
            case .pushToTalk:
                await startRecording()
            case .vadToggle:
                if case .idle = appState.state {
                    await startRecording()
                    startVADMonitor()
                } else if case .recording = appState.state {
                    vadMonitor?.stop()
                    await stopAndTranscribe()
                }
            }
        }
    }

    private func handleKeyUp() async {
        // Key-up only matters for mic + push-to-talk
        guard appState.audioSource == .microphone,
              appState.recordingMode == .pushToTalk else { return }
        await stopAndTranscribe()
    }

    private func handleOpenHistory() async {
        showHistory()
    }

    private func handleSourceToggle() async {
        guard case .idle = appState.state else { return }
        let newSource: AudioSourceSelection = appState.audioSource == .microphone ? .systemAudio : .microphone
        appState.audioSource = newSource
        appState.sourceNotification = newSource.displayName
        floatingPanel?.show()

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.appState.sourceNotification = nil
                if case .idle = self.appState.state { self.floatingPanel?.hide() }
            }
        }
    }

    // MARK: - Recording flow

    private func startRecording() async {
        guard case .idle = appState.state else { return }

        if appState.audioSource == .systemAudio {
            guard showGDPRConsentAlert() else { return }
        }

        hotwordDetector?.stop()
        appState.trackFrontmostApp()

        let source = activeSource
        let granted = await source.requestPermission()
        guard granted else {
            appState.state = .error("Permission denied")
            restartHotwordIfEnabled()
            return
        }

        do {
            try await source.start()
            appState.state = .recording
        } catch {
            appState.state = .error("Failed to start recording: \(error.localizedDescription)")
            restartHotwordIfEnabled()
        }
    }

    private func showGDPRConsentAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Recording Consent Required"
        alert.informativeText = """
            System audio recording captures audio from all participants in your session.

            Under GDPR and applicable privacy laws, you must obtain explicit consent from \
            every person who may be recorded before proceeding.

            Do you confirm that all participants have agreed to be recorded?
            """
        alert.addButton(withTitle: "Yes, Proceed")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func restartHotwordIfEnabled() {
        if appState.hotwordEnabled { startHotwordDetector() }
    }

    private func stopAndTranscribe() async {
        guard case .recording = appState.state else { return }

        let samples    = activeSource.stop()
        let pid        = appState.frontmostAppPID
        let lang       = appState.language
        let sourceType = appState.audioSource == .systemAudio ? "system" : "mic"
        let ppMode     = appState.postProcessMode
        let ppModel    = appState.ollamaModel
        let ppCustom   = appState.customLLMPrompt

        appState.state = .transcribing

        let engine  = transcriptionEngine
        let state   = appState
        let paste   = pasteEngine
        let history = historyStore
        let ollama  = ollamaClient

        Task {
            do {
                let result = try await engine.transcribe(audio: samples, language: lang)
                var finalText = result.text

                if ppMode != .none && !ppModel.isEmpty {
                    await MainActor.run { state.state = .postProcessing }
                    do {
                        finalText = try await ollama.process(
                            text: result.text,
                            mode: ppMode,
                            customPrompt: ppCustom,
                            model: ppModel
                        )
                    } catch {
                        finalText = result.text
                    }
                }

                let finalResult = DictationResult(text: finalText, words: result.words, duration: result.duration)
                await MainActor.run {
                    history.add(finalResult, language: lang, source: sourceType)
                    state.state = .showingResult
                }
                await paste?.paste(text: finalText, toPID: pid)
            } catch {
                await MainActor.run {
                    state.state = .error("Transcription failed: \(error.localizedDescription)")
                }
            }
            await MainActor.run { [weak self] in self?.restartHotwordIfEnabled() }
        }
    }

    // MARK: - Hotword detection

    private func startHotwordDetector() {
        hotwordDetector?.stop()
        let detector = HotwordDetector()
        detector.hotword             = appState.hotword
        detector.transcriptionEngine = transcriptionEngine
        detector.onHotwordDetected   = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, case .idle = self.appState.state else { return }
                self.hotwordDetector?.stop()
                await self.startRecording()
                // Hotword always uses VAD for mic; system audio uses push-to-stop (no VAD)
                if self.appState.audioSource == .microphone,
                   self.appState.recordingMode == .vadToggle {
                    self.startVADMonitor()
                }
            }
        }
        detector.start()
        hotwordDetector = detector
    }

    private func startVADMonitor() {
        let monitor = VADMonitor()
        vadMonitor  = monitor
        monitor.onSilenceDetected = { [weak self] in
            Task { @MainActor [weak self] in await self?.stopAndTranscribe() }
        }
        monitor.start(source: activeSource, silenceTimeout: appState.silenceTimeout)
    }
}
