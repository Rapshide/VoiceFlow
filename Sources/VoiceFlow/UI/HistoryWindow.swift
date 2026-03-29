import AppKit
import SwiftUI

extension Notification.Name {
    static let historyFocusSearch  = Notification.Name("historyFocusSearch")
    static let historyTypeCharacter = Notification.Name("historyTypeCharacter")
}

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var keyMonitor: Any?

    func show(historyStore: HistoryStore) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            postFocusSearch()
            return
        }

        let view = HistoryView(store: historyStore)
        let hosting = NSHostingController(rootView: view)

        let win = NSWindow(contentViewController: hosting)
        win.title = "VoiceFlow History"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 680, height: 500))
        win.minSize = NSSize(width: 400, height: 300)
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        window = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        addKeyMonitor()
        postFocusSearch()
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        addKeyMonitor()
    }

    func windowDidResignKey(_ notification: Notification) {
        removeKeyMonitor()
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
    }

    // MARK: - Key monitor

    private func addKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let win = self.window, win.isKeyWindow else { return event }

            // If a text field / editor is already first responder, let it handle the event.
            if win.firstResponder is NSTextView { return event }

            // Ignore Escape, and anything with Command, Control, or Option modifiers
            // (those are app shortcuts, not regular typing).
            guard event.keyCode != 53,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let chars = event.characters, !chars.isEmpty
            else { return event }

            NotificationCenter.default.post(name: .historyTypeCharacter, object: chars)
            return nil  // consume — the view will inject the character into searchText
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func postFocusSearch() {
        // Small delay so the window finishes appearing before SwiftUI tries to set focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .historyFocusSearch, object: nil)
        }
    }
}
