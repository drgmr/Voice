import SwiftUI

@main
struct VoiceApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("Voice", systemImage: menuBarSymbol) {
            MenuBarContent()
                .environment(controller)
        }

        Settings {
            SettingsView()
                .environment(controller)
        }
    }

    private var menuBarSymbol: String {
        switch controller.state {
        case .idle: "mic"
        case .recording: "mic.fill"
        case .transcribing: "waveform"
        }
    }
}
