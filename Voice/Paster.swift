import AppKit
import CoreGraphics
import os

@MainActor
final class Paster {
    private static let vKeyCode: CGKeyCode = 0x09
    private static let restoreDelay: Duration = .milliseconds(80)

    private let log = Logger.voice("paster")

    /// Non-destructive pasteboard write used by the menu bar and history
    /// copy buttons. Does not synthesize ⌘V — callers just want the text
    /// on the clipboard for the user to paste later.
    static func writeToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func paste(_ text: String) {
        guard !text.isEmpty else {
            log.info("Paste called with empty text — skipping")
            return
        }

        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        log.info("Paste \(text.count) chars into frontmost app: \(frontApp, privacy: .public)")

        let pasteboard = NSPasteboard.general
        let snapshot = snapshotContents(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        synthesizeCommandV()

        Task { @MainActor in
            try? await Task.sleep(for: Self.restoreDelay)
            restore(snapshot, to: pasteboard)
            log.info("Clipboard restored (\(snapshot.count) prior items)")
        }
    }

    private func snapshotContents(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
    }

    private func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        guard !snapshot.isEmpty else { return }
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = snapshot.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private func synthesizeCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false) else {
            log.error("Failed to build ⌘V CGEvent — aborting paste")
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        log.info("⌘V synthesized — if paste did not land, Accessibility permission is probably missing")
    }
}
