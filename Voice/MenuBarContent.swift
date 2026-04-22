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

        if let text = controller.lastTranscription, !text.isEmpty {
            Divider()
            Text("Last: \(text.prefix(60))")
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
}
