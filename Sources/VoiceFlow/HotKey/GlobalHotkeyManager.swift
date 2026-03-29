import Cocoa
import Carbon.HIToolbox
import ApplicationServices

// Right-side modifier key codes (kVK_* values)
enum HotkeyOption: Int, CaseIterable {
    case rightOption  = 61  // kVK_RightOption
    case rightCommand = 54  // kVK_RightCommand
    case rightControl = 62  // kVK_RightControl
    case rightShift   = 60  // kVK_RightShift

    var displayName: String {
        switch self {
        case .rightOption:  return "Right ⌥"
        case .rightCommand: return "Right ⌘"
        case .rightControl: return "Right ⌃"
        case .rightShift:   return "Right ⇧"
        }
    }

    /// The CGEventFlags bit that is set while this key is held down
    var eventFlag: CGEventFlags {
        switch self {
        case .rightOption:  return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .rightShift:   return .maskShift
        }
    }
}

// ── Globals accessible from the C event-tap callback ──────────────────────────
nonisolated(unsafe) private var _onKeyDown:   (@Sendable () async -> Void)?
nonisolated(unsafe) private var _onKeyUp:     (@Sendable () async -> Void)?
nonisolated(unsafe) private var _isKeyDown:   Bool        = false
nonisolated(unsafe) private var _hotkeyCode:  CGKeyCode   = 61
nonisolated(unsafe) private var _hotkeyFlag:  CGEventFlags = .maskAlternate
nonisolated(unsafe) private var _tapPort:     CFMachPort? = nil   // for re-enable

// ── C-compatible tap callback ──────────────────────────────────────────────────
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // macOS disables taps that are too slow. Re-enable immediately.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = _tapPort { CGEvent.tapEnable(tap: tap, enable: true) }
        return nil
    }

    guard type == .flagsChanged else {
        return Unmanaged.passRetained(event)
    }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    guard keyCode == _hotkeyCode else { return Unmanaged.passRetained(event) }

    let isModifierDown = event.flags.contains(_hotkeyFlag)

    if isModifierDown && !_isKeyDown {
        _isKeyDown = true
        if let cb = _onKeyDown { Task { await cb() } }
    } else if !isModifierDown && _isKeyDown {
        _isKeyDown = false
        if let cb = _onKeyUp   { Task { await cb() } }
    }

    return Unmanaged.passRetained(event)
}

// ── Manager ────────────────────────────────────────────────────────────────────
@MainActor
final class GlobalHotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onKeyDown: (@Sendable () async -> Void)? { didSet { _onKeyDown = onKeyDown } }
    var onKeyUp:   (@Sendable () async -> Void)? { didSet { _onKeyUp   = onKeyUp   } }

    init() {}

    /// Returns `true` if the event tap was created successfully.
    @discardableResult
    func start(hotkey: HotkeyOption = .rightOption) -> Bool {
        updateHotkey(hotkey)

        // flagsChanged is the ONLY event modifier-only keys generate.
        // Also subscribe to tap-disabled notifications so we can re-enable immediately.
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)         |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        ) else {
            return false   // caller decides how to surface this
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

    /// Call this when the user changes the hotkey in Settings — no restart needed.
    func updateHotkey(_ option: HotkeyOption) {
        _isKeyDown   = false          // reset hold-state on key change
        _hotkeyCode  = CGKeyCode(option.rawValue)
        _hotkeyFlag  = option.eventFlag
    }

    /// Opens System Settings → Accessibility. Call this after detecting the tap failed.
    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }
}
