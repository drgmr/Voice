import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            VocabularyTab()
                .tabItem { Label("Vocabulary", systemImage: "book") }

            HistoryTab()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            PlaceholderTab(title: "Permissions", hint: "Microphone, Accessibility, and Input Monitoring status — coming soon.")
                .tabItem { Label("Permissions", systemImage: "checkmark.shield") }
        }
        .frame(minWidth: 620, minHeight: 460)
    }
}

// MARK: - General

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

// MARK: - History

private struct HistoryTab: View {
    @Environment(AppController.self) private var controller
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(controller.recentHistory.count) \(controller.recentHistory.count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear all", systemImage: "trash")
                }
                .disabled(controller.recentHistory.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if controller.recentHistory.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No transcriptions yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Hold or tap Fn to dictate something. Your history will appear here.")
                )
                Spacer()
            } else {
                List(controller.recentHistory, id: \.id) { entry in
                    HistoryRow(entry: entry)
                        .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Clear all transcription history?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) {
                Task { await controller.clearHistory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every stored transcription. Audio was never stored.")
        }
    }
}

private struct HistoryRow: View {
    let entry: TranscriptionEntry

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.finalText)
                .textSelection(.enabled)
                .lineLimit(4)
            HStack(spacing: 6) {
                Text(Self.timeFormatter.string(from: entry.createdAt))
                Text("·")
                Text(durationLabel)
                if let lang = entry.language, !lang.isEmpty {
                    Text("·")
                    Text(lang.uppercased()).monospaced()
                }
                if let app = entry.appBundleId, !app.isEmpty {
                    Text("·")
                    Text(app).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button {
                    copyToClipboard(entry.finalText)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var durationLabel: String {
        let seconds = Double(entry.durationMs) / 1000
        return String(format: "%.1fs", seconds)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - Vocabulary

private struct VocabularyTab: View {
    @Environment(AppController.self) private var controller
    @State private var draftEntries: [VocabularyEntry] = []
    @State private var newFrom: String = ""
    @State private var newTo: String = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if draftEntries.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No vocabulary entries",
                    systemImage: "book",
                    description: Text("Add a rule below. The post-processor will apply it to future transcriptions.")
                )
                Spacer()
            } else {
                List {
                    ForEach($draftEntries) { $entry in
                        VocabularyRow(
                            entry: $entry,
                            onDelete: { delete(entry.id) }
                        )
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            addRow
        }
        .onAppear(perform: sync)
        .onChange(of: controller.vocabulary) { _, _ in sync() }
        .onChange(of: draftEntries) { _, new in
            if new != controller.vocabulary {
                scheduleSave()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Replace mis-transcribed phrases. The post-processor matches fuzzily.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(draftEntries.count) \(draftEntries.count == 1 ? "entry" : "entries")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("When I say", text: $newFrom)
                .textFieldStyle(.roundedBorder)
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            TextField("Write as", text: $newTo)
                .textFieldStyle(.roundedBorder)
            Button(action: add) {
                Label("Add", systemImage: "plus")
            }
            .disabled(!canAdd)
        }
        .padding(16)
    }

    private var canAdd: Bool {
        let from = newFrom.trimmingCharacters(in: .whitespaces)
        let to = newTo.trimmingCharacters(in: .whitespaces)
        return !from.isEmpty && !to.isEmpty
    }

    private func sync() {
        if draftEntries != controller.vocabulary {
            draftEntries = controller.vocabulary
        }
    }

    private func add() {
        let entry = VocabularyEntry(
            from: newFrom.trimmingCharacters(in: .whitespaces),
            to: newTo.trimmingCharacters(in: .whitespaces)
        )
        draftEntries.append(entry)
        newFrom = ""
        newTo = ""
    }

    private func delete(_ id: UUID) {
        draftEntries.removeAll { $0.id == id }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = draftEntries
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await controller.saveVocabulary(snapshot)
        }
    }
}

private struct VocabularyRow: View {
    @Binding var entry: VocabularyEntry
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("When I say", text: $entry.from)
                .textFieldStyle(.roundedBorder)
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            TextField("Write as", text: $entry.to)
                .textFieldStyle(.roundedBorder)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Placeholder

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
