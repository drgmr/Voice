import AppKit
import SwiftUI
import os

/// Hosts the onboarding UI in a regular titled NSWindow. Shown only on first
/// launch (and kept up until the user taps "Get Started" or closes the
/// window). The SwiftUI content observes `AppController.modelLoadState` and
/// transitions from a loading spinner to a ready state as prewarm completes.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let hosting: NSHostingView<WelcomeView>
    private weak var controller: AppController?
    private let log = Logger(subsystem: "com.drgmr.Voice", category: "welcome")

    init(controller: AppController) {
        self.controller = controller

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 560, height: 720)
        window.title = "Welcome to Voice"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        hosting = NSHostingView(rootView: WelcomeView(controller: controller))
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = window.contentView?.bounds ?? .zero
        window.contentView = hosting

        super.init()
        window.delegate = self
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        log.info("Welcome window presented")
    }

    func hide() {
        window.orderOut(nil)
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // User closed the welcome window manually — treat as onboarded so we
        // don't pop it again on the next launch.
        controller?.finishOnboarding()
    }
}
