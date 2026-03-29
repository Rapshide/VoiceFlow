import CoreGraphics
import Carbon.HIToolbox

struct HotkeyConfig: Codable, Equatable, Sendable {
    var keyCode: UInt16        // virtual key code
    var modifierFlags: UInt64  // CGEventFlags raw value
    var isModifierOnly: Bool   // true = modifier key alone; detected via flagsChanged

    // MARK: - Defaults

    static let defaultRecording = HotkeyConfig(
        keyCode: 61, // kVK_RightOption
        modifierFlags: CGEventFlags.maskAlternate.rawValue,
        isModifierOnly: true
    )

    /// Default source toggle: Control+Shift+M
    static let defaultSourceToggle = HotkeyConfig(
        keyCode: 46, // kVK_ANSI_M
        modifierFlags: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue,
        isModifierOnly: false
    )

    // MARK: - Migration from legacy hotkeyCode Int

    static func fromLegacyCode(_ code: Int) -> HotkeyConfig {
        switch code {
        case 54: return HotkeyConfig(keyCode: 54, modifierFlags: CGEventFlags.maskCommand.rawValue,  isModifierOnly: true)
        case 62: return HotkeyConfig(keyCode: 62, modifierFlags: CGEventFlags.maskControl.rawValue,  isModifierOnly: true)
        case 60: return HotkeyConfig(keyCode: 60, modifierFlags: CGEventFlags.maskShift.rawValue,    isModifierOnly: true)
        default: return .defaultRecording // 61 = Right Option
        }
    }

    // MARK: - Display

    var displayName: String {
        if isModifierOnly {
            // Build a list of all flags that are part of the combo, then append
            // the human-readable name of the primary (last-pressed) key.
            // e.g. Right ⌥ + Right ⇧  or just  Right ⌥
            let flags = CGEventFlags(rawValue: modifierFlags)
            var parts: [String] = []

            // Add any "extra" modifiers that aren't the primary key itself
            let primaryFlag = primaryFlagForKey(keyCode)
            if flags.contains(.maskControl)   && !primaryFlag.contains(.maskControl)   { parts.append("⌃") }
            if flags.contains(.maskAlternate) && !primaryFlag.contains(.maskAlternate) { parts.append("⌥") }
            if flags.contains(.maskShift)     && !primaryFlag.contains(.maskShift)     { parts.append("⇧") }
            if flags.contains(.maskCommand)   && !primaryFlag.contains(.maskCommand)   { parts.append("⌘") }

            if !parts.isEmpty {
                return parts.joined() + modifierKeyLabel(for: keyCode)
            }
            return modifierKeyLabel(for: keyCode)
        }

        // Regular key + modifiers
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifierFlags)
        if flags.contains(.maskControl)   { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift)     { parts.append("⇧") }
        if flags.contains(.maskCommand)   { parts.append("⌘") }
        parts.append(regularKeyName(for: keyCode))
        return parts.joined()
    }

    /// The CGEventFlags bit that corresponds to a modifier key code.
    private func primaryFlagForKey(_ code: UInt16) -> CGEventFlags {
        switch Int(code) {
        case kVK_Option, kVK_RightOption:    return .maskAlternate
        case kVK_Command, kVK_RightCommand:  return .maskCommand
        case kVK_Control, kVK_RightControl:  return .maskControl
        case kVK_Shift, kVK_RightShift:      return .maskShift
        default:                             return CGEventFlags(rawValue: 0)
        }
    }

    private func modifierKeyLabel(for code: UInt16) -> String {
        switch Int(code) {
        case kVK_RightOption:  return "Right ⌥"
        case kVK_RightCommand: return "Right ⌘"
        case kVK_RightControl: return "Right ⌃"
        case kVK_RightShift:   return "Right ⇧"
        case kVK_Option:       return "Left ⌥"
        case kVK_Command:      return "Left ⌘"
        case kVK_Control:      return "Left ⌃"
        case kVK_Shift:        return "Left ⇧"
        case kVK_CapsLock:     return "⇪ Caps Lock"
        case kVK_Function:     return "fn"
        default:               return "Key \(code)"
        }
    }

    // swiftlint:disable cyclomatic_complexity
    private func regularKeyName(for code: UInt16) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space:  return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab:    return "Tab"
        case kVK_Delete: return "⌫"
        case kVK_F1:     return "F1"
        case kVK_F2:     return "F2"
        case kVK_F3:     return "F3"
        case kVK_F4:     return "F4"
        case kVK_F5:     return "F5"
        case kVK_F6:     return "F6"
        case kVK_F7:     return "F7"
        case kVK_F8:     return "F8"
        case kVK_F9:     return "F9"
        case kVK_F10:    return "F10"
        case kVK_F11:    return "F11"
        case kVK_F12:    return "F12"
        case kVK_F13:    return "F13"
        case kVK_F14:    return "F14"
        case kVK_F15:    return "F15"
        case kVK_F16:    return "F16"
        case kVK_F17:    return "F17"
        case kVK_F18:    return "F18"
        case kVK_F19:    return "F19"
        case kVK_F20:    return "F20"
        default: return "Key \(code)"
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
