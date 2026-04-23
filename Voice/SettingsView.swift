import AppKit
import AVFoundation
import Combine
import CoreGraphics
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            VocabularyTab()
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            HistoryTab()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            PermissionsTab()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 480, idealHeight: 560)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Environment(AppController.self) private var controller
    @State private var availableDevices: [AVCaptureDevice] = []

    var body: some View {
        @Bindable var preferences = controller.preferences

        Form {
            Section {
                LabeledContent("Hotkey") {
                    Text("Fn").font(.body.monospaced())
                }
            } header: {
                Text("Activation")
            } footer: {
                Text("Press and hold Fn to record, or quick-tap to toggle. Esc cancels.")
            }

            Section {
                Picker("Input device", selection: $preferences.inputDeviceID) {
                    Text("Automatic (built-in preferred)").tag(String?.none)
                    Divider()
                    ForEach(availableDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(String?.some(device.uniqueID))
                    }
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text("Automatic avoids Bluetooth aggregate-device issues by preferring the built-in microphone. Pick a specific device to override.")
            }

            Section("State") {
                LabeledContent("Current") {
                    StatePill(state: controller.state)
                }
                if let last = controller.lastTranscription {
                    LabeledContent("Last result") {
                        Text(last)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                }
                if let err = controller.errorMessage {
                    LabeledContent("Error") {
                        Text(err)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section {
                Button("Show Welcome Again") {
                    controller.showWelcomeAgain()
                }
            } footer: {
                Text("Re-opens the first-run welcome window, including the hotkey cheatsheet and permissions panel.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            availableDevices = Recorder.availableInputDevices()
        }
    }
}

private struct StatePill: View {
    let state: AppController.State

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.body.monospaced())
        }
    }

    private var color: Color {
        switch state {
        case .idle: .secondary
        case .recording: .red
        case .transcribing: .orange
        }
    }

    private var label: String {
        switch state {
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
    @State private var query: String = ""
    @State private var searchResults: [TranscriptionEntry] = []
    @State private var searchTask: Task<Void, Never>?

    private var displayedEntries: [TranscriptionEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? controller.recentHistory : searchResults
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcriptions", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                Spacer(minLength: 8)
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear all", systemImage: "trash")
                }
                .disabled(controller.recentHistory.isEmpty)
                .help("Permanently remove every stored transcription")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Group {
                if displayedEntries.isEmpty {
                    emptyState
                } else {
                    List(displayedEntries, id: \.id) { entry in
                        HistoryRow(entry: entry)
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                    .listStyle(.inset)
                    .alternatingRowBackgrounds()
                }
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
        .onChange(of: query) { _, _ in
            scheduleSearch()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            ContentUnavailableView(
                "No transcriptions yet",
                systemImage: "waveform",
                description: Text("Hold or tap Fn anywhere to dictate. Your history will appear here.")
            )
        } else {
            ContentUnavailableView.search(text: trimmed)
        }
    }

    private var countLabel: String {
        let total = controller.recentHistory.count
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "\(total) \(total == 1 ? "entry" : "entries")"
        } else {
            return "\(searchResults.count) of \(total)"
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let current = query
        searchTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                searchResults = []
            } else {
                let results = await controller.searchHistory(trimmed)
                searchResults = results
            }
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
        HStack(alignment: .top, spacing: 10) {
            AppIconChip(bundleID: entry.appBundleId)

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
                    if let app = appName(for: entry.appBundleId) {
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

    private func appName(for bundleID: String?) -> String? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else {
            return bundleID
        }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? bundleID
    }
}

private struct AppIconChip: View {
    let bundleID: String?

    var body: some View {
        ZStack {
            if let icon = appIcon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "app")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .padding(.top, 1)
    }

    private func appIcon(for bundleID: String?) -> NSImage? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Vocabulary

private struct VocabularyTab: View {
    @Environment(AppController.self) private var controller
    @State private var draftEntries: [VocabularyEntry] = []
    @State private var selection: Set<UUID> = []
    @State private var showingAddSheet = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Replace mis-transcribed phrases. The post-processor matches fuzzily.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(draftEntries.count) \(draftEntries.count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Group {
                if draftEntries.isEmpty {
                    ContentUnavailableView {
                        Label("No vocabulary entries", systemImage: "character.book.closed")
                    } description: {
                        Text("Add a rule to replace mis-transcribed phrases. The post-processor will apply it to future transcriptions.")
                    } actions: {
                        Button("Add entry") { showingAddSheet = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Table(of: Binding<VocabularyEntry>.self, selection: $selection) {
                        TableColumn("When I say") { $entry in
                            TextField("", text: $entry.from, prompt: Text("When I say"))
                                .textFieldStyle(.plain)
                        }
                        TableColumn("Write as") { $entry in
                            TextField("", text: $entry.to, prompt: Text("Write as"))
                                .textFieldStyle(.plain)
                        }
                    } rows: {
                        ForEach($draftEntries) { $entry in
                            TableRow($entry)
                        }
                    }
                    .alternatingRowBackgrounds()
                }
            }

            Divider()

            HStack(spacing: 4) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 18)
                }
                .buttonStyle(.borderless)
                .help("Add a new vocabulary rule")

                Button {
                    deleteSelected()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 22, height: 18)
                }
                .buttonStyle(.borderless)
                .disabled(selection.isEmpty)
                .help("Delete selected entries")

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddVocabularySheet { from, to in
                let entry = VocabularyEntry(from: from, to: to)
                draftEntries.append(entry)
            }
        }
        .onAppear(perform: sync)
        .onChange(of: controller.vocabulary) { _, _ in sync() }
        .onChange(of: draftEntries) { _, new in
            if new != controller.vocabulary {
                scheduleSave()
            }
        }
    }

    private func sync() {
        if draftEntries != controller.vocabulary {
            draftEntries = controller.vocabulary
        }
    }

    private func deleteSelected() {
        draftEntries.removeAll { selection.contains($0.id) }
        selection.removeAll()
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

private struct AddVocabularySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var from: String = ""
    @State private var to: String = ""
    let onAdd: (String, String) -> Void

    private var canAdd: Bool {
        !from.trimmingCharacters(in: .whitespaces).isEmpty &&
        !to.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New vocabulary rule")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Form {
                TextField("When I say", text: $from)
                TextField("Write as", text: $to)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd(
                        from.trimmingCharacters(in: .whitespaces),
                        to.trimmingCharacters(in: .whitespaces)
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
            .padding(20)
        }
        .frame(width: 420)
    }
}

// MARK: - Permissions

private struct PermissionsTab: View {
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var accessibilityGranted: Bool = false
    @State private var inputMonitoringGranted: Bool = false

    private let refreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Microphone",
                    description: "Required for audio capture.",
                    status: micRowStatus,
                    openSettings: {
                        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                    }
                )
                PermissionRow(
                    title: "Input Monitoring",
                    description: "Required to detect the Fn hotkey globally.",
                    status: inputMonitoringGranted ? .granted : .denied,
                    openSettings: {
                        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
                    }
                )
                PermissionRow(
                    title: "Accessibility",
                    description: "Required to paste transcribed text via ⌘V synthesis.",
                    status: accessibilityGranted ? .granted : .denied,
                    openSettings: {
                        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                    }
                )
            } footer: {
                Text("After granting a permission, re-launch Voice so the running binary picks up the new grant.")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private var micRowStatus: PermissionRow.Status {
        switch micStatus {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .pending
        @unknown default: .pending
        }
    }

    private func refresh() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct PermissionRow: View {
    enum Status {
        case granted, denied, pending

        var color: Color {
            switch self {
            case .granted: .green
            case .denied: .red
            case .pending: .yellow
            }
        }

        var symbol: String {
            switch self {
            case .granted: "checkmark.circle.fill"
            case .denied: "xmark.circle.fill"
            case .pending: "questionmark.circle.fill"
            }
        }

        var label: String {
            switch self {
            case .granted: "Granted"
            case .denied: "Not granted"
            case .pending: "Not yet requested"
            }
        }
    }

    let title: String
    let description: String
    let status: Status
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .font(.title2)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }

            Spacer()

            Button("Open Settings", action: openSettings)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
