import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController {
    private var window: NSWindow?

    func show(historyStore: HistoryStore) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = HistoryView(store: historyStore)
        let hosting = NSHostingController(rootView: view)

        let win = NSWindow(contentViewController: hosting)
        win.title = "VoiceFlow History"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 600, height: 500))
        win.minSize = NSSize(width: 400, height: 300)
        win.center()
        win.isReleasedWhenClosed = false
        window = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
