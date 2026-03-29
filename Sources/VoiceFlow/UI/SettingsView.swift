import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var appState = AppStateManager.shared

    private let languages = [("hu", "Hungarian"), ("en", "English")]

    var body: some View {
        Form {
            Section("Dictation") {
                Picker("Language", selection: Binding(
                    get: { appState.language },
                    set: { appState.language = $0 }
                )) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
            }

            Section("Recording") {
                Picker("Mode", selection: Binding(
                    get: { appState.recordingMode },
                    set: { appState.recordingMode = $0 }
                )) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if appState.recordingMode == .vadToggle {
                    HStack {
                        Text("Silence timeout")
                        Slider(
                            value: Binding(
                                get: { appState.silenceTimeout },
                                set: { appState.silenceTimeout = $0 }
                            ),
                            in: 0.5...5.0,
                            step: 0.5
                        )
                        Text(String(format: "%.1fs", appState.silenceTimeout))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 40)
                    }
                    Text("Press hotkey to start recording. Recording stops automatically after silence, or press hotkey again to stop manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Hold the selected key to record, release to transcribe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Audio Source", selection: Binding(
                    get: { appState.audioSource },
                    set: { appState.audioSource = $0 }
                )) {
                    ForEach(AudioSourceSelection.allCases, id: \.self) { source in
                        Text(source.displayName).tag(source)
                    }
                }

                if appState.audioSource == .systemAudio {
                    Text("Captures all system audio output. Requires Screen Recording permission. Always uses VAD auto-stop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Hotkeys") {
                KeyRecorderView(
                    hotkey: Binding(
                        get: { appState.recordingHotkey },
                        set: { config in
                            appState.recordingHotkey = config
                            AppDelegateLocator.shared?.updateRecordingHotkey(config)
                        }
                    ),
                    label: "Record"
                )

                KeyRecorderView(
                    hotkey: Binding(
                        get: { appState.sourceToggleHotkey },
                        set: { config in
                            appState.sourceToggleHotkey = config
                            AppDelegateLocator.shared?.updateSourceToggleHotkey(config)
                        }
                    ),
                    label: "Switch Source"
                )

                Text("Click \"Record\" then press any key or modifier key. Switch Source toggles between Microphone and System Audio without opening Preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Model") {
                LabeledContent("Active model") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(appState.loadedModelName.isEmpty ? "—" : appState.loadedModelName)
                                .font(.system(.body, design: .monospaced))
                            if !appState.isModelLoaded {
                                ProgressView(value: appState.modelDownloadProgress)
                                    .frame(width: 120)
                                Text(appState.modelDownloadProgress < 1.0
                                     ? "Downloading… \(Int(appState.modelDownloadProgress * 100))%"
                                     : "Loading…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Loaded")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        Button("Re-download") {
                            appState.clearModelCache()
                            AppDelegateLocator.shared?.reloadModel()
                        }
                        .disabled(!appState.isModelLoaded)
                    }
                }
            }

            Section("Post-processing (Ollama)") {
                Picker("Mode", selection: Binding(
                    get: { appState.postProcessMode },
                    set: { appState.postProcessMode = $0 }
                )) {
                    ForEach(PostProcessMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                if appState.postProcessMode != .none {
                    if appState.isOllamaAvailable {
                        Picker("Model", selection: Binding(
                            get: { appState.ollamaModel },
                            set: { appState.ollamaModel = $0 }
                        )) {
                            Text("Select…").tag("")
                            ForEach(appState.ollamaModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text("Ollama not running. Install from ollama.com and start it.")
                                .font(.caption)
                        }
                    }

                    Button("Refresh Models") {
                        AppDelegateLocator.shared?.refreshOllamaModels()
                    }

                    if appState.postProcessMode == .custom {
                        TextField("Custom prompt", text: Binding(
                            get: { appState.customLLMPrompt },
                            set: { appState.customLLMPrompt = $0 }
                        ), axis: .vertical)
                        .lineLimit(3...6)
                    }
                }

                Text("Transcriptions are post-processed by a local LLM before pasting. Requires Ollama running locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hotword") {
                Toggle("Enable hotword activation", isOn: Binding(
                    get: { appState.hotwordEnabled },
                    set: {
                        appState.hotwordEnabled = $0
                        AppDelegateLocator.shared?.updateHotwordDetection()
                    }
                ))

                if appState.hotwordEnabled {
                    TextField("Wake word", text: Binding(
                        get: { appState.hotword },
                        set: { appState.hotword = $0 }
                    ))

                    Label("Always-on mic listening uses more battery.", systemImage: "battery.50percent")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("System") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .navigationTitle("VoiceFlow Settings")
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register()   }
            else        { try SMAppService.mainApp.unregister() }
        } catch {
            print("Launch at login error: \(error)")
        }
    }
}

/// Thin bridge so SettingsView can reach the live GlobalHotkeyManager
/// without creating a hard dependency on AppDelegate.
@MainActor
final class AppDelegateLocator {
    static var shared: AppDelegate?
}
