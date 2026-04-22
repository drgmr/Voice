import Foundation
import os
import WhisperKit

// WhisperKit manages its own internal synchronization; the Core ML
// models it wraps are thread-safe. Under Swift 6 strict concurrency we
// need it Sendable to hand it to the @concurrent transcribe method.
extension WhisperKit: @unchecked @retroactive Sendable {}

/// Local Whisper transcription via WhisperKit + Core ML. Lazily loads the
/// chip-recommended model on first use; the first call blocks until download
/// and specialization complete (can take minutes over slow networks). All
/// subsequent calls reuse the loaded pipeline.
actor Transcriber {
    private var whisperKit: WhisperKit?
    private let log = Logger(subsystem: "com.drgmr.Voice", category: "transcriber")

    func transcribe(samples: [Float]) async -> String {
        guard !samples.isEmpty else {
            log.info("Transcribe called with 0 samples — skipping")
            return ""
        }

        let start = Date()
        do {
            let whisper = try await loadedPipeline()
            log.info("Transcribing \(samples.count) samples (\(String(format: "%.2f", Double(samples.count) / 16_000.0))s)…")
            let results = try await whisper.transcribe(audioArray: samples)
            let text = results.map(\.text).joined(separator: " ")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let elapsed = Date().timeIntervalSince(start)
            log.info("Transcribe completed in \(String(format: "%.2f", elapsed))s → \(trimmed.count) chars")
            return trimmed
        } catch {
            log.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            return "[transcribe error: \(error.localizedDescription)]"
        }
    }

    private func loadedPipeline() async throws -> WhisperKit {
        if let whisperKit { return whisperKit }

        let modelName = WhisperKit.recommendedModels().default
        log.info("Loading WhisperKit model: \(modelName, privacy: .public) — first call may download ~600MB")
        let start = Date()

        let config = WhisperKitConfig(
            model: modelName,
            verbose: false,
            logLevel: .info,
            load: true,
            download: true
        )
        let instance = try await WhisperKit(config)
        whisperKit = instance
        let elapsed = Date().timeIntervalSince(start)
        log.info("WhisperKit model loaded in \(String(format: "%.2f", elapsed))s")
        return instance
    }
}
