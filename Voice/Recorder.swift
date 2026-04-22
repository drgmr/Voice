@preconcurrency import AVFoundation
import CoreAudio
import CoreMedia
import Foundation
import os

/// Mutable reference cell used to thread single-owner state through callbacks
/// that Swift 6 cannot prove are serially invoked.
nonisolated private final class SafeBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Captures microphone audio using AVCaptureSession + AVCaptureAudioDataOutput
/// and delivers 16 kHz mono Float32 samples — Whisper's native input.
///
/// Why not AVAudioEngine: AVAudioEngine's input node goes through an AUHAL
/// that, on macOS, constructs a "default device aggregate" combining the
/// system's default input + output devices. When those devices have mismatched
/// stream formats or channel counts (common with AirPods in the mix), the
/// aggregate setup throws `-10877` (kAudioUnitErr_InvalidPropertyValue),
/// cascading into a libdispatch assertion crash inside Apple's AudioAnalytics
/// service queue. Setting `kAudioOutputUnitProperty_CurrentDevice` after the
/// fact doesn't unwind the earlier damage.
///
/// AVCaptureSession binds to a specific `AVCaptureDevice` from construction,
/// no aggregate device is built, and `AVCaptureAudioDataOutput.audioSettings`
/// does the format conversion for us.
final class Recorder: NSObject, @unchecked Sendable {
    private let session = AVCaptureSession()
    private var currentInput: AVCaptureDeviceInput?
    private var currentOutput: AVCaptureAudioDataOutput?

    private let bufferLock = OSAllocatedUnfairLock(initialState: [Float]())
    private let processingQueue = DispatchQueue(label: "com.drgmr.Voice.recorder.capture")
    private let log = Logger(subsystem: "com.drgmr.Voice", category: "recorder")
    private let firstBufferLogged = SafeBox(false)

    enum RecorderError: Error, LocalizedError {
        case noInputDevice
        case inputAddFailed
        case outputAddFailed

        var errorDescription: String? {
            switch self {
            case .noInputDevice: "No audio input device available."
            case .inputAddFailed: "Could not attach audio input to capture session."
            case .outputAddFailed: "Could not attach audio output to capture session."
            }
        }
    }

    override init() {
        super.init()
    }

    func start() throws {
        teardown()
        bufferLock.withLock { $0.removeAll(keepingCapacity: true) }
        firstBufferLogged.value = false

        guard let device = preferredInputDevice() else {
            log.error("No AVCaptureDevice available for audio")
            throw RecorderError.noInputDevice
        }
        log.info("Capture device: \(device.localizedName, privacy: .public) [uid=\(device.uniqueID, privacy: .public)]")

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw RecorderError.inputAddFailed
        }
        session.addInput(input)
        currentInput = input

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        output.setSampleBufferDelegate(self, queue: processingQueue)
        guard session.canAddOutput(output) else {
            throw RecorderError.outputAddFailed
        }
        session.addOutput(output)
        currentOutput = output

        session.startRunning()
        log.info("AVCaptureSession started (requested 16 kHz mono Float32)")
    }

    func stop() -> [Float] {
        if session.isRunning {
            session.stopRunning()
        }
        teardown()
        let result = bufferLock.withLock { samples -> [Float] in
            let out = samples
            samples.removeAll(keepingCapacity: false)
            return out
        }
        let seconds = Double(result.count) / 16_000.0
        log.info("Recorder.stop — \(result.count) samples captured (\(String(format: "%.2f", seconds))s)")
        return result
    }

    func cancel() {
        if session.isRunning {
            session.stopRunning()
        }
        teardown()
        bufferLock.withLock { $0.removeAll(keepingCapacity: false) }
        log.info("Recorder.cancel — buffer cleared")
    }

    private func teardown() {
        if let input = currentInput {
            session.removeInput(input)
            currentInput = nil
        }
        if let output = currentOutput {
            session.removeOutput(output)
            currentOutput = nil
        }
    }

    // MARK: - Device selection

    private func preferredInputDevice() -> AVCaptureDevice? {
        let devices = Self.availableInputDevices()

        // Explicit user preference (set via Settings → General).
        if let savedID = UserDefaults.standard.string(forKey: Preferences.inputDeviceKey),
           let match = devices.first(where: { $0.uniqueID == savedID }) {
            return match
        }

        // Automatic: prefer the CoreAudio-reported built-in microphone by
        // UID. This avoids Bluetooth HFP aggregate-device pitfalls.
        if let builtInUID = Self.builtInMicrophoneUID(),
           let match = devices.first(where: { $0.uniqueID == builtInUID }) {
            return match
        }

        // Fallback: name heuristic.
        if let named = devices.first(where: {
            $0.localizedName.localizedCaseInsensitiveContains("MacBook")
            || $0.localizedName.localizedCaseInsensitiveContains("Built-in")
        }) {
            return named
        }

        // Last resort: system default.
        return AVCaptureDevice.default(for: .audio)
    }

    /// All audio input devices discoverable by AVCapture, for Settings UI.
    static func availableInputDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private static func builtInMicrophoneUID() -> String? {
        guard let deviceID = findBuiltInMicrophoneID() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &unmanaged)
        guard status == noErr, let unmanaged else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    private static func findBuiltInMicrophoneID() -> AudioDeviceID? {
        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            0, nil,
            &propertySize
        )
        guard status == noErr else { return nil }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            0, nil,
            &propertySize,
            &devices
        )
        guard status == noErr else { return nil }

        for deviceID in devices {
            var inputStreamsAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputStreamsSize: UInt32 = 0
            let streamsStatus = AudioObjectGetPropertyDataSize(
                deviceID, &inputStreamsAddr, 0, nil, &inputStreamsSize
            )
            guard streamsStatus == noErr, inputStreamsSize > 0 else { continue }

            var transportType: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let transportStatus = AudioObjectGetPropertyData(
                deviceID, &transportAddr, 0, nil, &transportSize, &transportType
            )
            guard transportStatus == noErr else { continue }

            if transportType == kAudioDeviceTransportTypeBuiltIn {
                return deviceID
            }
        }

        return nil
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension Recorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let pointer = dataPointer else { return }

        let floatCount = length / MemoryLayout<Float>.size
        guard floatCount > 0 else { return }

        let samples = pointer.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
            Array(UnsafeBufferPointer(start: floats, count: floatCount))
        }

        if !firstBufferLogged.value {
            firstBufferLogged.value = true
            log.info("First audio sample buffer — \(samples.count) samples (delivered pre-resampled)")
        }

        bufferLock.withLock { $0.append(contentsOf: samples) }
    }
}
