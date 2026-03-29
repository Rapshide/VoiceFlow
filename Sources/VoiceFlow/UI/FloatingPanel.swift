import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    private var hostingView: NSHostingView<FloatingPanelView>?

    init(appState: AppStateManager) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = false

        let view = FloatingPanelView(appState: appState, panel: self)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = contentView!.bounds
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
        hostingView = hosting

        positionAtBottomCenter()
    }

    func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 600
        let panelHeight: CGFloat = 80
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.minY + 40
        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: false)
    }

    func show() {
        positionAtBottomCenter()
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
