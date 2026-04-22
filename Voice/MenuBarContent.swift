import AppKit
import SwiftUI

struct MenuBarContent: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        switch controller.state {
        case .idle:
            Text("Ready — hold or tap Fn")
        case .recording:
            Text("Recording…")
        case .transcribing:
            Text("Transcribing…")
        }

        let recent = Array(controller.recentHistory.prefix(5))
        if !recent.isEmpty {
            Divider()
            Section("Recent") {
                ForEach(recent, id: \.id) { entry in
                    Button {
                        copyToClipboard(entry.finalText)
                    } label: {
                        Text(preview(for: entry))
                    }
                }
            }
        }

        if let err = controller.errorMessage {
            Divider()
            Text(err).foregroundStyle(.red)
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Voice") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func preview(for entry: TranscriptionEntry) -> String {
        let maxLen = 60
        let text = entry.finalText.replacingOccurrences(of: "\n", with: " ")
        if text.count <= maxLen { return text }
        return String(text.prefix(maxLen)) + "…"
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
