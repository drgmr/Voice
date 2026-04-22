import Foundation
import os

/// A single vocabulary substitution rule. `from` is a phonetic/mis-heard
/// variant as the model might transcribe it; `to` is the canonical form
/// the post-processor should output.
nonisolated struct VocabularyEntry: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var from: String
    var to: String

    init(id: UUID = UUID(), from: String, to: String) {
        self.id = id
        self.from = from
        self.to = to
    }
}

/// JSON-backed vocabulary. Lives at `~/Library/Application Support/Voice/vocabulary.json`
/// so users can hand-edit outside the app if they want. Seeded with sensible
/// defaults on first launch.
actor VocabularyStore {
    let url: URL
    private let log = Logger(subsystem: "com.drgmr.Voice", category: "vocabulary")

    init() throws {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Voice", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        self.url = base.appendingPathComponent("vocabulary.json")
    }

    func load() -> [VocabularyEntry] {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            let defaults = Self.defaultEntries
            try? writeToDisk(defaults)
            log.info("Seeded vocabulary with \(defaults.count) defaults")
            return defaults
        }
        do {
            let data = try Data(contentsOf: url)
            let entries = try JSONDecoder().decode([VocabularyEntry].self, from: data)
            return entries
        } catch {
            log.error("Failed to decode vocabulary.json: \(error.localizedDescription, privacy: .public) — using defaults")
            return Self.defaultEntries
        }
    }

    func save(_ entries: [VocabularyEntry]) throws {
        try writeToDisk(entries)
        log.info("Saved vocabulary (\(entries.count) entries) to \(self.url.path, privacy: .public)")
    }

    private func writeToDisk(_ entries: [VocabularyEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(entries)
        try data.write(to: url, options: .atomic)
    }

    nonisolated static let defaultEntries: [VocabularyEntry] = [
        VocabularyEntry(from: "cloud code", to: "Claude Code"),
        VocabularyEntry(from: "clawed code", to: "Claude Code"),
        VocabularyEntry(from: "clod code", to: "Claude Code"),
        VocabularyEntry(from: "clawed", to: "Claude"),
        VocabularyEntry(from: "clod", to: "Claude"),
        VocabularyEntry(from: "mac os", to: "macOS"),
        VocabularyEntry(from: "i os", to: "iOS"),
        VocabularyEntry(from: "swift ui", to: "SwiftUI"),
        VocabularyEntry(from: "per ambacker", to: "Poernbacher"),
        VocabularyEntry(from: "porn backer", to: "Poernbacher"),
        VocabularyEntry(from: "porn bocker", to: "Poernbacher"),
        VocabularyEntry(from: "my sequel", to: "MySQL"),
        VocabularyEntry(from: "git hub", to: "GitHub"),
        VocabularyEntry(from: "j son", to: "JSON"),
        VocabularyEntry(from: "h t m l", to: "HTML"),
        VocabularyEntry(from: "c s s", to: "CSS"),
        VocabularyEntry(from: "a p i", to: "API"),
        VocabularyEntry(from: "u r l", to: "URL"),
        VocabularyEntry(from: "open a i", to: "OpenAI"),
        VocabularyEntry(from: "whisper kit", to: "WhisperKit"),
        VocabularyEntry(from: "x code", to: "Xcode"),
    ]
}
