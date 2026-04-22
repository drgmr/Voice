import AppKit
import SwiftUI
import os

/// Hosts the floating pill in a borderless, click-through `NSPanel`.
/// Positioned at screen-bottom-center, raised to `.statusBar` level so it
/// floats above arbitrary app windows. The SwiftUI content itself handles
/// show/hide transitions off of the `AppController.state`; the window stays
/// orderedFront throughout so animations can play cleanly.
@MainActor
final class PillWindowController {
    private let panel: NSPanel
    private let hosting: NSHostingView<PillRootView>
    private let log = Logger(subsystem: "com.drgmr.Voice", category: "pill")

    private static let bottomPadding: CGFloat = 60

    init(controller: AppController) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        hosting = NSHostingView(rootView: PillRootView(controller: controller))
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = panel.contentView?.bounds ?? .zero
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        positionAtBottomCenter()
        panel.orderFrontRegardless()
        log.info("PillWindow initialized and floated at bottom center")

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.positionAtBottomCenter()
            }
        }
    }

    private func positionAtBottomCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + Self.bottomPadding
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
