import Foundation
import os
import WhisperKit

// WhisperKit manages its own internal synchronization; the Core ML
// models it wraps are thread-safe. Under Swift 6 strict concurrency we
// need it Sendable to hand it to the @concurrent transcribe method.
extension WhisperKit: @unchecked @retroactive Sendable {}

/// Result of one transcription call. `language` is WhisperKit's detected
/// (or forced) language code for the audio — typically a 2-letter ISO code
/// like "en", "pt". Nil if WhisperKit did not report a language.
nonisolated struct TranscriptionOutput: Sendable, Equatable {
    let text: String
    let language: String?
}

/// Local Whisper transcription via WhisperKit + Core ML. Lazily loads the
/// chip-recommended model on first use; the first call blocks until download
/// and specialization complete (can take minutes over slow networks). All
/// subsequent calls reuse the loaded pipeline.
///
/// Concurrency note: because `WhisperKit.init` is non-isolated async, the
/// actor suspends during load. That means prewarm and a user-triggered
/// transcription can interleave inside `loadedPipeline()` via actor
/// reentrancy. To prevent double-loading we cache the in-flight load as a
/// `Task` — the second entrant awaits the same task rather than starting
/// its own.
actor Transcriber {
    private var whisperKit: WhisperKit?
    private var loadTask: Task<WhisperKit, Error>?
    private let log = Logger(subsystem: "com.drgmr.Voice", category: "transcriber")

    /// Load (and download if needed) the recommended WhisperKit model so the
    /// first user transcription doesn't pay the pipeline-load latency. Safe
    /// to call multiple times — subsequent calls are a no-op. Throws on
    /// failure so the welcome flow can surface the error.
    func prewarm() async throws {
        let start = Date()
        _ = try await loadedPipeline()
        let elapsed = Date().timeIntervalSince(start)
        log.info("WhisperKit prewarm complete in \(String(format: "%.2f", elapsed))s")
    }

    func transcribe(samples: [Float]) async -> TranscriptionOutput {
        guard !samples.isEmpty else {
            log.info("Transcribe called with 0 samples — skipping")
            return TranscriptionOutput(text: "", language: nil)
        }

        let start = Date()
        do {
            let whisper = try await loadedPipeline()
            log.info("Transcribing \(samples.count) samples (\(String(format: "%.2f", Double(samples.count) / 16_000.0))s)…")
            let results = try await whisper.transcribe(audioArray: samples)
            let text = results.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let language = results.first.map(\.language)
            let elapsed = Date().timeIntervalSince(start)
            log.info("Transcribe completed in \(String(format: "%.2f", elapsed))s → \(text.count) chars, language=\(language ?? "unknown", privacy: .public)")
            return TranscriptionOutput(text: text, language: language)
        } catch {
            log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            return TranscriptionOutput(
                text: "[transcribe error: \(error.localizedDescription)]",
                language: nil
            )
        }
    }

    private func loadedPipeline() async throws -> WhisperKit {
        if let whisperKit { return whisperKit }

        // Another caller is already loading — attach to its Task.
        if let loadTask {
            return try await loadTask.value
        }

        let modelName = WhisperKit.recommendedModels().default
        log.info("Loading WhisperKit model: \(modelName, privacy: .public) — first call may download ~600MB")
        let start = Date()

        let task = Task { () throws -> WhisperKit in
            let config = WhisperKitConfig(
                model: modelName,
                verbose: false,
                logLevel: .info,
                load: true,
                download: true
            )
            return try await WhisperKit(config)
        }
        loadTask = task

        do {
            let instance = try await task.value
            whisperKit = instance
            loadTask = nil
            let elapsed = Date().timeIntervalSince(start)
            log.info("WhisperKit model loaded in \(String(format: "%.2f", elapsed))s")
            return instance
        } catch {
            loadTask = nil
            throw error
        }
    }
}
