import AppKit
import ApplicationServices
import AVFoundation
import Combine
import CoreGraphics
import SwiftUI

struct WelcomeView: View {
    @Bindable var controller: AppController

    var body: some View {
        VStack(spacing: 22) {
            AppLogo()

            Group {
                switch controller.modelLoadState {
                case .preparing:
                    LoadingStage(
                        title: "Welcome to Voice",
                        subtitle: "Press the Fn key anywhere to dictate.",
                        progress: nil,
                        statusMessage: "Preparing…"
                    )
                case .downloading(let fraction):
                    LoadingStage(
                        title: "Welcome to Voice",
                        subtitle: "Press the Fn key anywhere to dictate.",
                        progress: fraction,
                        statusMessage: downloadingMessage(for: fraction)
                    )
                case .loading:
                    LoadingStage(
                        title: "Welcome to Voice",
                        subtitle: "Press the Fn key anywhere to dictate.",
                        progress: nil,
                        statusMessage: "Optimizing the model for your Mac…"
                    )
                case .ready:
                    ReadyStage(onStart: { controller.finishOnboarding() })
                case .failed(let message):
                    FailedStage(message: message, onRetry: { controller.retryModelLoad() })
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.smooth(duration: 0.28), value: stateKey)

            Spacer(minLength: 4)

            ModelFooter()
        }
        .padding(.horizontal, 48)
        .padding(.top, 32)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var stateKey: String {
        switch controller.modelLoadState {
        case .preparing: "preparing"
        case .downloading: "downloading"
        case .loading: "loading"
        case .ready: "ready"
        case .failed: "failed"
        }
    }

    private func downloadingMessage(for fraction: Double) -> String {
        let approxTotalMB = 617.0
        let doneMB = approxTotalMB * fraction
        return String(format: "%.0f MB of %.0f MB", doneMB, approxTotalMB)
    }
}

// MARK: - Logo

private struct AppLogo: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.37, green: 0.36, blue: 0.90), Color(red: 0.04, green: 0.52, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)

            Image(systemName: "mic.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Loading stage

private struct LoadingStage: View {
    let title: String
    let subtitle: String
    /// When non-nil, renders a determinate bar. Nil means indeterminate spinner.
    let progress: Double?
    let statusMessage: String

    var body: some View {
        VStack(spacing: 18) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                HStack {
                    Text("Downloading speech model…")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }

                Text("One-time download. Runs locally from here on — nothing leaves your Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 420)
        }
    }
}

// MARK: - Ready stage

private struct ReadyStage: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("You're all set")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.primary)

            Text("Hold or tap Fn anywhere to start dictating.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            shortcutCard
            PermissionsCard()

            Button(action: onStart) {
                Text("Get Started")
                    .font(.headline)
                    .frame(minWidth: 200)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
    }

    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShortcutRow(key: "Fn", description: "Hold to record while pressed, release to paste.")
            ShortcutRow(key: "Fn", description: "Quick-tap to start. Tap again to stop.")
            ShortcutRow(key: "esc", description: "Cancel recording or transcription at any time.")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .frame(maxWidth: 440)
    }
}

private struct ShortcutRow: View {
    let key: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Text(key)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                )
                .frame(minWidth: 44)

            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.8))

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Permissions inside welcome

private struct PermissionsCard: View {
    @State private var micStatus: AVAuthorizationStatus = .notDetermined
    @State private var accessibilityGranted: Bool = false
    @State private var inputMonitoringGranted: Bool = false

    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)

            PermissionItemRow(
                title: "Microphone",
                subtitle: "To capture your voice.",
                isGranted: micStatus == .authorized,
                onRequest: requestMicrophone
            )
            PermissionItemRow(
                title: "Input Monitoring",
                subtitle: "To detect the Fn hotkey anywhere.",
                isGranted: inputMonitoringGranted,
                onRequest: requestInputMonitoring
            )
            PermissionItemRow(
                title: "Accessibility",
                subtitle: "To paste transcriptions into the frontmost app.",
                isGranted: accessibilityGranted,
                onRequest: requestAccessibility
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .frame(maxWidth: 440)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private func refresh() {
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    private func requestMicrophone() {
        Task { @MainActor in
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refresh()
        }
    }

    private func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        refresh()
    }

    private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }
}

private struct PermissionItemRow: View {
    let title: String
    let subtitle: String
    let isGranted: Bool
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isGranted ? Color.green : Color.secondary.opacity(0.5))
                .font(.system(size: 18))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isGranted {
                Button("Grant", action: onRequest)
                    .controlSize(.small)
            } else {
                Text("Granted")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Footer

private struct ModelFooter: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
            Text("whisper-large-v3-turbo · Apple Silicon · ~617 MB")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Failed stage

private struct FailedStage: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.yellow)

            Text("Model load failed")
                .font(.system(size: 20, weight: .bold))

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button(action: onRetry) {
                Text("Try again")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}
