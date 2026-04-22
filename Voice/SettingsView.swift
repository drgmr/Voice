import SwiftUI

struct SettingsView: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            PlaceholderTab(title: "Vocabulary", hint: "Fuzzy substitution rules — coming in M1.")
                .tabItem { Label("Vocabulary", systemImage: "book") }

            PlaceholderTab(title: "History", hint: "Transcription history with search and re-paste — coming in M1.")
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            PlaceholderTab(title: "Permissions", hint: "Microphone, Accessibility, and Input Monitoring status — coming in M1.")
                .tabItem { Label("Permissions", systemImage: "checkmark.shield") }
        }
        .frame(minWidth: 560, minHeight: 400)
    }
}

private struct GeneralTab: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        Form {
            Section("Activation") {
                LabeledContent("Hotkey") {
                    Text("Fn").font(.body.monospaced())
                }
                Text("Press and hold Fn to record, or quick-tap to toggle. Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("State") {
                LabeledContent("Current") {
                    Text(stateLabel).monospaced()
                }
                if let last = controller.lastTranscription {
                    LabeledContent("Last result") {
                        Text(last)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }
                }
                if let err = controller.errorMessage {
                    Text(err).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var stateLabel: String {
        switch controller.state {
        case .idle: "idle"
        case .recording: "recording"
        case .transcribing: "transcribing"
        }
    }
}

private struct PlaceholderTab: View {
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.title2.bold())
            Text(hint).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
