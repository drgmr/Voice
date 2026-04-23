import AppKit
import CoreGraphics
import os

/// Watches for the Fn key globally via CGEventTap. Requires Input Monitoring permission.
///
/// Hotkey is a dumb event source: it reports each physical Fn press, each
/// release with the hold duration, and each Esc press. Interpretation of
/// those events (quick-tap toggle vs. hold-to-record, whether a press starts
/// or stops, whether to ignore during transcription) lives in
/// `AppController`, which owns the authoritative app state. Keeping toggle
/// semantics out of Hotkey prevents its state from drifting out of sync with
/// the app.
@MainActor
final class Hotkey {
    var onFnPress: (@MainActor () -> Void)?
    var onFnRelease: (@MainActor (_ held: TimeInterval) -> Void)?
    var onEsc: (@MainActor () -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var fnDown = false
    private var fnPressStart: Date?

    private static let escapeKeyCode: Int64 = 53

    private let log = Logger.voice("hotkey")

    enum HotkeyError: Error, LocalizedError {
        case tapCreationFailed

        var errorDescription: String? {
            switch self {
            case .tapCreationFailed:
                "Could not create event tap — Input Monitoring permission is required."
            }
        }
    }

    func start() throws {
        let hasInputMonitoring = CGPreflightListenEventAccess()
        log.info("Input Monitoring preflight: \(hasInputMonitoring ? "GRANTED" : "NOT GRANTED", privacy: .public)")
        if !hasInputMonitoring {
            log.warning("Input Monitoring not granted — triggering request. You MUST relaunch the app after granting.")
            _ = CGRequestListenEventAccess()
        }

        let hasAccessibility = AXIsProcessTrusted()
        log.info("Accessibility preflight: \(hasAccessibility ? "GRANTED" : "NOT GRANTED", privacy: .public) (needed for paste)")

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Hotkey.tapCallback,
            userInfo: refcon
        ) else {
            log.error("CGEvent.tapCreate returned nil — Input Monitoring permission missing?")
            throw HotkeyError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source

        if hasInputMonitoring {
            log.info("Event tap active — global key capture ENABLED")
        } else {
            log.warning("Event tap active but scoped to focused app only — Input Monitoring not yet active this session")
        }
    }

    fileprivate func reEnableTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        log.warning("Event tap was disabled by macOS — re-enabled. Check for slow callbacks.")
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<Hotkey>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { owner.reEnableTap() }
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            let raw = event.flags.rawValue
            let fnNowDown = event.flags.contains(.maskSecondaryFn)
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    owner.logRawFlags(raw: raw, fnDown: fnNowDown, keycode: keycode)
                    owner.handleFnChange(pressed: fnNowDown)
                }
            }

        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    owner.logRawKeyDown(keycode: code)
                    if code == Hotkey.escapeKeyCode {
                        owner.handleEscape()
                    }
                }
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func logRawFlags(raw: UInt64, fnDown: Bool, keycode: Int64) {
        log.debug("flagsChanged: raw=0x\(String(raw, radix: 16)) fnDown=\(fnDown) keycode=\(keycode)")
    }

    private func logRawKeyDown(keycode: Int64) {
        log.debug("keyDown: keycode=\(keycode)")
    }

    private func handleFnChange(pressed: Bool) {
        if pressed && !fnDown {
            fnDown = true
            fnPressStart = .now
            log.info("Fn press")
            onFnPress?()
        } else if !pressed && fnDown {
            fnDown = false
            let held = fnPressStart.map { Date.now.timeIntervalSince($0) } ?? 0
            fnPressStart = nil
            log.info("Fn release after \(Int(held * 1000))ms")
            onFnRelease?(held)
        }
    }

    private func handleEscape() {
        log.info("Esc pressed")
        onEsc?()
    }
}
