import Foundation

/// Single source of truth for on-disk locations the app owns. Pinned
/// under Application Support so the app can reason about presence
/// (onboarding keys off model presence, not a persisted flag) and so
/// nothing leaks into the user's Documents folder.
enum AppPaths {
    /// `~/Library/Application Support/Voice` — the root for all
    /// persistent state the app writes. Created on first access.
    nonisolated static let appSupport: URL = {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        let dir = base.appending(component: "Voice")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// SQLite database backing transcription history.
    nonisolated static let historyDatabase: URL = appSupport.appending(component: "history.sqlite")

    /// JSON file storing the user's vocabulary rules.
    nonisolated static let vocabularyFile: URL = appSupport.appending(component: "vocabulary.json")

    /// WhisperKit download base. HubApi stamps
    /// `models/argmaxinc/whisperkit-coreml/<variant>/` inside this folder.
    nonisolated static let modelsBase: URL = {
        let dir = appSupport.appending(component: "models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
