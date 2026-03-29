import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A form row that lets the user press any key or key combination to set a global hotkey.
///
/// How capture works:
/// - Press one or more modifier keys → they are accumulated but NOT finalized yet.
/// - Then press a regular key (with at least one modifier held, or an F-key alone) → the
///   combination is captured and recording stops.
/// - Release ALL modifiers without pressing a regular key → the last modifier key pressed
///   is captured as a modifier-only hotkey (e.g. Right ⌥ for push-to-talk).
/// - Press Escape at any point to cancel.
struct KeyRecorderView: View {
    @Binding var hotkey: HotkeyConfig
    let label: String

    @State private var isRecording    = false
    @State private var monitor: Any?
    // Accumulated state while the user holds modifier keys
    @State private var pendingModKey:  UInt16?       = nil  // keyCode of the last modifier pressed
    @State private var pendingCGFlags: CGEventFlags  = []

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 8) {
                Text(isRecording ? (pendingDisplay ?? "Press a key…") : hotkey.displayName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isRecording ? .secondary : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                lineWidth: 1
                            )
                    )
                    .frame(minWidth: 80)

                Button(isRecording ? "Cancel" : "Record") {
                    isRecording ? stopRecording() : startRecording()
                }
                .buttonStyle(.bordered)
            }
        }
        .onDisappear { stopRecording() }
    }

    // Shows partial modifier combo while the user is holding keys, e.g. "⌃⇧…"
    private var pendingDisplay: String? {
        guard !pendingCGFlags.isEmpty else { return nil }
        var parts: [String] = []
        if pendingCGFlags.contains(.maskControl)   { parts.append("⌃") }
        if pendingCGFlags.contains(.maskAlternate) { parts.append("⌥") }
        if pendingCGFlags.contains(.maskShift)     { parts.append("⇧") }
        if pendingCGFlags.contains(.maskCommand)   { parts.append("⌘") }
        parts.append("…")
        return parts.joined()
    }

    // MARK: - Recording lifecycle

    private func startRecording() {
        pendingModKey  = nil
        pendingCGFlags = []
        isRecording    = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleEvent(event)
            return nil  // consume the event
        }
    }

    private func stopRecording() {
        isRecording    = false
        pendingModKey  = nil
        pendingCGFlags = []
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    // MARK: - Event handling

    private func handleEvent(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }

        if event.type == .flagsChanged {
            handleFlagsChanged(event)
        } else if event.type == .keyDown, !event.isARepeat {
            captureRegularKey(event)
        }
    }

    /// Accumulate modifier presses; finalize as modifier-only when all are released.
    private func handleFlagsChanged(_ event: NSEvent) {
        let relevantMods = event.modifierFlags.intersection([.control, .option, .shift, .command])

        if !relevantMods.isEmpty {
            // One or more modifiers are held — accumulate flags and track the last pressed key.
            // Only update pendingModKey when this specific key was just PRESSED (not released).
            let nsFlag = nsModifierFlag(for: event.keyCode)
            let keyWasPressed = !nsFlag.isEmpty && event.modifierFlags.contains(nsFlag)
            if keyWasPressed {
                pendingModKey = event.keyCode
            }
            var cgFlags: CGEventFlags = []
            if relevantMods.contains(.control) { cgFlags.insert(.maskControl) }
            if relevantMods.contains(.option)  { cgFlags.insert(.maskAlternate) }
            if relevantMods.contains(.shift)   { cgFlags.insert(.maskShift) }
            if relevantMods.contains(.command) { cgFlags.insert(.maskCommand) }
            pendingCGFlags = cgFlags
        } else {
            // All modifiers released — capture the full accumulated combo as modifier-only.
            // pendingModKey is stored for display purposes; detection uses the full flag set.
            if let modKey = pendingModKey, !pendingCGFlags.isEmpty {
                hotkey = HotkeyConfig(
                    keyCode: modKey,
                    modifierFlags: pendingCGFlags.rawValue,
                    isModifierOnly: true
                )
                stopRecording()
                return
            }
            pendingModKey  = nil
            pendingCGFlags = []
        }
    }

    /// Capture a regular key + any currently held modifiers.
    private func captureRegularKey(_ event: NSEvent) {
        let isFnKey = Int(event.keyCode) >= kVK_F1 && Int(event.keyCode) <= kVK_F20

        // Use the tracked CGFlags (more reliable than event.modifierFlags alone)
        let cgFlags: CGEventFlags
        if !pendingCGFlags.isEmpty {
            cgFlags = pendingCGFlags
        } else {
            let relevantMods = event.modifierFlags.intersection([.control, .option, .shift, .command])
            guard !relevantMods.isEmpty || isFnKey else { return }
            var flags: CGEventFlags = []
            if relevantMods.contains(.control) { flags.insert(.maskControl) }
            if relevantMods.contains(.option)  { flags.insert(.maskAlternate) }
            if relevantMods.contains(.shift)   { flags.insert(.maskShift) }
            if relevantMods.contains(.command) { flags.insert(.maskCommand) }
            cgFlags = flags
        }

        guard !cgFlags.isEmpty || isFnKey else { return }

        hotkey = HotkeyConfig(
            keyCode: event.keyCode,
            modifierFlags: cgFlags.rawValue,
            isModifierOnly: false
        )
        stopRecording()
    }

    // MARK: - Helpers

    private func nsModifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch Int(keyCode) {
        case kVK_Option, kVK_RightOption:    return .option
        case kVK_Command, kVK_RightCommand:  return .command
        case kVK_Control, kVK_RightControl:  return .control
        case kVK_Shift, kVK_RightShift:      return .shift
        case kVK_CapsLock:                   return .capsLock
        default:                             return []
        }
    }

    private func cgEventFlag(for keyCode: UInt16) -> CGEventFlags {
        switch Int(keyCode) {
        case kVK_Option, kVK_RightOption:    return .maskAlternate
        case kVK_Command, kVK_RightCommand:  return .maskCommand
        case kVK_Control, kVK_RightControl:  return .maskControl
        case kVK_Shift, kVK_RightShift:      return .maskShift
        default:                             return CGEventFlags(rawValue: 0)
        }
    }
}
