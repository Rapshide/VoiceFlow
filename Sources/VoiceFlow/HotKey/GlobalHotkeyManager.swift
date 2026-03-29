import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// Only these four modifier bits are compared when matching regular key hotkeys.
// Other CGEventFlags bits (NumericPad, NonCoalesced, etc.) are intentionally ignored.
private let kSignificantModifierMask: UInt64 =
    CGEventFlags.maskControl.rawValue   |
    CGEventFlags.maskAlternate.rawValue |
    CGEventFlags.maskShift.rawValue     |
    CGEventFlags.maskCommand.rawValue

// ── Globals accessible from the C event-tap callback ──────────────────────────
nonisolated(unsafe) private var _recordingConfig:    HotkeyConfig = .defaultRecording
nonisolated(unsafe) private var _toggleConfig:       HotkeyConfig = .defaultSourceToggle
nonisolated(unsafe) private var _onRecordingDown:    (@Sendable () async -> Void)?
nonisolated(unsafe) private var _onRecordingUp:      (@Sendable () async -> Void)?
nonisolated(unsafe) private var _onSourceToggle:     (@Sendable () async -> Void)?
nonisolated(unsafe) private var _onOpenHistory:      (@Sendable () async -> Void)?
nonisolated(unsafe) private var _recordingKeyIsDown: Bool        = false
nonisolated(unsafe) private var _tapPort:            CFMachPort? = nil

// Fixed history hotkey: ⌘⇧H (keyCode 4 = kVK_ANSI_H)
private let kHistoryKeyCode: CGKeyCode = 4
private let kHistoryModSig:  UInt64    = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue

// ── C-compatible tap callback ──────────────────────────────────────────────────
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // macOS disables taps that are too slow — re-enable immediately.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = _tapPort { CGEvent.tapEnable(tap: tap, enable: true) }
        return nil
    }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

    // ── flagsChanged: modifier-only hotkeys ───────────────────────────────────
    if type == .flagsChanged {
        handleFlagsChanged(flags: event.flags)
        return Unmanaged.passRetained(event)
    }

    // ── keyDown / keyUp: regular key hotkeys ──────────────────────────────────
    let activeSignificant = event.flags.rawValue & kSignificantModifierMask

    if type == .keyDown {
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        // Recording hotkey
        if !_recordingConfig.isModifierOnly,
           keyCode == CGKeyCode(_recordingConfig.keyCode),
           activeSignificant == (_recordingConfig.modifierFlags & kSignificantModifierMask),
           !isRepeat, !_recordingKeyIsDown {
            _recordingKeyIsDown = true
            if let cb = _onRecordingDown { Task { await cb() } }
        }

        // Source toggle hotkey
        if !_toggleConfig.isModifierOnly,
           keyCode == CGKeyCode(_toggleConfig.keyCode),
           activeSignificant == (_toggleConfig.modifierFlags & kSignificantModifierMask),
           !isRepeat {
            if let cb = _onSourceToggle { Task { await cb() } }
        }

        // Fixed history hotkey: ⌥ + H
        if keyCode == kHistoryKeyCode,
           activeSignificant == kHistoryModSig,
           !isRepeat {
            if let cb = _onOpenHistory { Task { await cb() } }
        }
    }

    if type == .keyUp {
        // Recording hotkey release (push-to-talk with a regular key)
        if !_recordingConfig.isModifierOnly,
           keyCode == CGKeyCode(_recordingConfig.keyCode),
           _recordingKeyIsDown {
            _recordingKeyIsDown = false
            if let cb = _onRecordingUp { Task { await cb() } }
        }
    }

    return Unmanaged.passRetained(event)
}

private func handleFlagsChanged(flags: CGEventFlags) {
    // For modifier-only hotkeys we match by the EXACT set of significant modifier flags,
    // not by key code. This means the user can press the keys in any order and the
    // hotkey fires as soon as the full combination is held (or released).
    let significantActive = flags.rawValue & kSignificantModifierMask

    // Recording hotkey (modifier-only)
    if _recordingConfig.isModifierOnly {
        let configSig = _recordingConfig.modifierFlags & kSignificantModifierMask
        let isDown = significantActive == configSig
        if isDown && !_recordingKeyIsDown {
            _recordingKeyIsDown = true
            if let cb = _onRecordingDown { Task { await cb() } }
        } else if !isDown && _recordingKeyIsDown {
            _recordingKeyIsDown = false
            if let cb = _onRecordingUp { Task { await cb() } }
        }
    }

    // Source toggle hotkey (modifier-only) — fires once when the exact combo becomes active
    if _toggleConfig.isModifierOnly {
        let configSig = _toggleConfig.modifierFlags & kSignificantModifierMask
        if significantActive == configSig {
            if let cb = _onSourceToggle { Task { await cb() } }
        }
    }
}

// ── Manager ────────────────────────────────────────────────────────────────────
@MainActor
final class GlobalHotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onRecordingKeyDown: (@Sendable () async -> Void)? { didSet { _onRecordingDown = onRecordingKeyDown } }
    var onRecordingKeyUp:   (@Sendable () async -> Void)? { didSet { _onRecordingUp   = onRecordingKeyUp   } }
    var onSourceToggle:     (@Sendable () async -> Void)? { didSet { _onSourceToggle  = onSourceToggle     } }
    var onOpenHistory:      (@Sendable () async -> Void)? { didSet { _onOpenHistory   = onOpenHistory      } }

    init() {}

    /// Returns `true` if the event tap was created successfully.
    @discardableResult
    func start(recordingHotkey: HotkeyConfig, sourceToggleHotkey: HotkeyConfig) -> Bool {
        updateRecordingHotkey(recordingHotkey)
        updateSourceToggleHotkey(sourceToggleHotkey)

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)          |
            (1 << CGEventType.keyDown.rawValue)               |
            (1 << CGEventType.keyUp.rawValue)                 |
            (1 << CGEventType.tapDisabledByTimeout.rawValue)  |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            return false
        }

        _tapPort = tap
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        _tapPort = nil
    }

    /// Live-update the recording hotkey — no restart needed.
    func updateRecordingHotkey(_ config: HotkeyConfig) {
        _recordingKeyIsDown = false
        _recordingConfig = config
    }

    /// Live-update the source-toggle hotkey — no restart needed.
    func updateSourceToggleHotkey(_ config: HotkeyConfig) {
        _toggleConfig = config
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }
}
