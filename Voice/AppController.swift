import AVFoundation
import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class AppController {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
    }

    private(set) var state: State = .idle
    private(set) var recordingStartedAt: Date?
    private(set) var lastTranscription: String?
    private(set) var errorMessage: String?

    /// Recording started via a quick-tap and is waiting for a second tap to stop.
    /// When `true`, the next Fn press stops recording; when `false`, a release
    /// of the current press stops recording (press-and-hold semantics).
    private var awaitingQuickTapStop = false

    private static let quickTapMaxDuration: TimeInterval = 0.28

    private let hotkey = Hotkey()
    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private let postProcessor = PostProcessor()
    private let paster = Paster()

    private var pillWindow: PillWindowController?

    private let log = Logger(subsystem: "com.drgmr.Voice", category: "controller")

    init() {
        hotkey.onFnPress = { [weak self] in
            self?.handleFnPress()
        }
        hotkey.onFnRelease = { [weak self] held in
            self?.handleFnRelease(held: held)
        }
        hotkey.onEsc = { [weak self] in
            self?.handleEsc()
        }

        do {
            try hotkey.start()
        } catch {
            errorMessage = "Hotkey setup failed: \(error.localizedDescription). Grant Input Monitoring in System Settings."
            log.error("Hotkey start failed: \(error.localizedDescription, privacy: .public)")
        }

        Task { @MainActor [log] in
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            log.info("Microphone permission at startup: \(String(describing: status), privacy: .public)")
            if status == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                log.info("Microphone permission request result: \(granted ? "GRANTED" : "DENIED", privacy: .public)")
            }
        }

        // Float the pill. It observes `state` directly and animates in/out.
        pillWindow = PillWindowController(controller: self)
    }

    // MARK: - Hotkey event handlers (sole entrypoints for Fn/Esc semantics)

    private func handleFnPress() {
        switch state {
        case .idle:
            startRecording()
        case .recording where awaitingQuickTapStop:
            awaitingQuickTapStop = false
            log.info("Fn press — second tap of toggle cycle → stopping")
            Task { await stopAndTranscribe() }
        case .recording:
            log.info("Fn press during hold-recording — ignored (release will stop)")
        case .transcribing:
            log.info("Fn press during transcribing — ignored")
        }
    }

    private func handleFnRelease(held: TimeInterval) {
        switch state {
        case .recording where awaitingQuickTapStop:
            // This is the physical release of the press that just stopped
            // recording. Nothing to do; state will transition to
            // .transcribing via the already-dispatched stopAndTranscribe.
            log.info("Fn release after stop-tap — no-op")
        case .recording:
            if held < Self.quickTapMaxDuration {
                awaitingQuickTapStop = true
                log.info("Fn quick-tap (\(Int(held * 1000))ms) → recording continues, awaiting second tap")
            } else {
                log.info("Fn release after \(Int(held * 1000))ms hold → stopping")
                Task { await stopAndTranscribe() }
            }
        case .idle, .transcribing:
            log.info("Fn release during state=\(String(describing: self.state), privacy: .public) — no-op")
        }
    }

    private func handleEsc() {
        if state != .idle {
            cancel()
        }
    }

    // MARK: - State transitions

    func startRecording() {
        guard state == .idle else {
            log.info("startRecording ignored — state is \(String(describing: self.state), privacy: .public)")
            return
        }
        do {
            try recorder.start()
            recordingStartedAt = .now
            awaitingQuickTapStop = false
            state = .recording
            errorMessage = nil
            log.info("startRecording → state=recording")
        } catch {
            errorMessage = "Recorder start failed: \(error.localizedDescription)"
            log.error("Recorder start failed: \(error.localizedDescription, privacy: .public)")
            state = .idle
        }
    }

    func cancel() {
        if state != .idle {
            recorder.cancel()
            recordingStartedAt = nil
            awaitingQuickTapStop = false
            state = .idle
            log.info("cancel → state=idle")
        } else {
            log.info("cancel ignored — already idle")
        }
    }

    func stopAndTranscribe() async {
        guard state == .recording else {
            log.info("stopAndTranscribe ignored — state is \(String(describing: self.state), privacy: .public)")
            return
        }
        let samples = recorder.stop()
        log.info("stopAndTranscribe → got \(samples.count) samples, state=transcribing")
        state = .transcribing

        let rawText = await transcriber.transcribe(samples: samples)
        guard state == .transcribing else {
            log.info("Transcription completed but state changed — discarding result")
            return
        }
        let rawTrimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        log.info("Raw transcription \(rawTrimmed.count) chars: \"\(rawTrimmed, privacy: .public)\"")

        let cleaned = await postProcessor.process(rawTrimmed)
        guard state == .transcribing else {
            log.info("Post-processing completed but state changed — discarding result")
            return
        }
        log.info("Post-processed \(cleaned.count) chars: \"\(cleaned, privacy: .public)\"")

        if !cleaned.isEmpty {
            paster.paste(cleaned)
            lastTranscription = cleaned
        } else {
            log.info("Empty output — skipping paste")
            lastTranscription = "(empty)"
        }
        recordingStartedAt = nil
        awaitingQuickTapStop = false
        state = .idle
    }
}
