import AppKit
import CoreGraphics

@MainActor
final class PasteEngine {
    func paste(text: String, toPID: pid_t) async {
        let pasteboard = NSPasteboard.general

        // Save existing pasteboard contents
        let savedContents: [(NSPasteboard.PasteboardType, Data?)] = pasteboard.types?.compactMap { type in
            (type, pasteboard.data(forType: type))
        } ?? []

        // Write new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure pasteboard is ready
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Synthesise Cmd+V key down + key up
        if let source = CGEventSource(stateID: .hidSystemState) {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand

            if toPID != 0 {
                keyDown?.postToPid(toPID)
                keyUp?.postToPid(toPID)
            } else {
                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
            }
        }

        // Restore pasteboard after brief delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        pasteboard.clearContents()
        for (type, data) in savedContents {
            if let data {
                pasteboard.setData(data, forType: type)
            }
        }
    }
}
