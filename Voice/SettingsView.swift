import AppKit
import AVFoundation
import Combine
import CoreGraphics
import SwiftUI

struct SettingsView: View {
    @State private var selection: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, id: \.self, selection: $selection) { tab in
                NavigationLink(value: tab) {
                    Label(tab.title, systemImage: tab.symbol)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            detail(for: selection)
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    @ViewBuilder
    private func detail(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralTab()
        case .vocabulary: VocabularyTab()
        case .history: HistoryTab()
        case .permissions: PermissionsTab()
        }
    }
}

private enum SettingsTab: String, CaseIterable, Hashable {
    case general
    case vocabulary
    case history
    case permissions

    var title: String {
        switch self {
        case .general: "General"
        case .vocabulary: "Vocabulary"
        case .history: "History"
        case .permissions: "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gear"
        case .vocabulary: "book"
        case .history: "clock.arrow.circlepath"
        case .permissions: "checkmark.shield"
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Environment(AppController.self) private var controller
    @State private var availableDevices: [AVCaptureDevice] = []

    var body: some View {
        @Bindable var preferences = controller.preferences

        Form {
            Section("Activation") {
                LabeledContent("Hotkey") {
                    Text("Fn").font(.body.monospaced())
                }
                Text("Press and hold Fn to record, or quick-tap to toggle. Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Microphone") {
                Picker("Input device", selection: $preferences.inputDeviceID) {
                    Text("Automatic (built-in preferred)").tag(String?.none)
                    Divider()
                    ForEach(availableDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(String?.some(device.uniqueID))
                    }
                }
                Text("Automatic avoids Bluetooth aggregate-device issues by preferring the built-in microphone. Pick a specific device to override.")
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

            Section {
                Button("Show Welcome Again") {
                    controller.showWelcomeAgain()
                }
            } footer: {
                Text("Re-opens the first-run welcome window, including the hotkey cheatsheet and permissions panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            availableDevices = Recorder.availableInputDevices()
        }
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
                TextField("Search transcriptions", text: $query)
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            if displayedEntries.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                List(displayedEntries, id: \.id) { entry in
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
                systemImage: "clock.arrow.circlepath",
                description: Text("Hold or tap Fn to dictate something. Your history will appear here.")
            )
        } else {
            ContentUnavailableView(
                "No matches",
                systemImage: "magnifyingglass",
                description: Text("No transcription contains \"\(trimmed)\".")
            )
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(status.label)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }

            Spacer()

            Button("Open Settings") {
                openSettings()
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}
