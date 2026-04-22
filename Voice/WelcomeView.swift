import AppKit
import ApplicationServices
import AVFoundation
import Combine
import CoreGraphics
import SwiftUI

struct WelcomeView: View {
    @Bindable var controller: AppController

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.09, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                AppLogo()

                Group {
                    switch controller.modelLoadState {
                    case .preparing:
                        LoadingStage(message: "Preparing…", progress: nil)
                    case .downloading(let fraction):
                        LoadingStage(
                            message: downloadingMessage(for: fraction),
                            progress: fraction
                        )
                    case .loading:
                        LoadingStage(message: "Optimizing the model for your Mac…", progress: nil)
                    case .ready:
                        ReadyStage(onStart: { controller.finishOnboarding() })
                    case .failed(let message):
                        FailedStage(message: message, onRetry: { controller.retryModelLoad() })
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.smooth(duration: 0.28), value: stateKey)
            }
            .padding(40)
        }
        .frame(minWidth: 520, minHeight: 520)
        .foregroundStyle(.white)
    }

    /// Key used purely to trigger the crossfade; reduces the
    /// `.downloading(fraction:)` case to a single identity so the animation
    /// doesn't re-fire on every progress tick.
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
        return String(format: "Downloading speech model — %.0f MB of %.0f MB", doneMB, approxTotalMB)
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
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)

            Image(systemName: "mic.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Loading stage

private struct LoadingStage: View {
    let message: String
    /// When non-nil, renders a determinate bar. Nil means indeterminate spinner.
    let progress: Double?

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Voice")
                .font(.system(size: 28, weight: .bold))

            Text("Setting up the on-device speech model.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))

            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .frame(maxWidth: 360)
                    .padding(.top, 6)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .tint(.white)
                    .padding(.vertical, 4)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)

            Text("First time only. Audio stays on your Mac — nothing leaves your device.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
    }
}

// MARK: - Ready stage

private struct ReadyStage: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Text("You're all set")
                .font(.system(size: 28, weight: .bold))

            Text("Hold or tap Fn anywhere to dictate.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))

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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .frame(maxWidth: 440)
    }
}

private struct ShortcutRow: View {
    let key: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Text(key)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                )
                .frame(minWidth: 52)

            Text(description)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))

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
            Text("Permissions Voice needs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))

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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
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
        // Triggers the macOS prompt. Grant takes effect on next launch.
        _ = CGRequestListenEventAccess()
        refresh()
    }

    private func requestAccessibility() {
        // The AX framework exports kAXTrustedCheckOptionPrompt as a CFString
        // global var, which Swift 6 flags as not concurrency-safe. Its value
        // is the string literal below and is documented to be stable.
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
                .foregroundStyle(isGranted ? Color.green : Color.white.opacity(0.35))
                .font(.system(size: 18))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            if !isGranted {
                Button("Grant", action: onRequest)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .tint(.white)
            } else {
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
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
                .font(.system(size: 22, weight: .bold))

            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button(action: onRetry) {
                Text("Try again")
                    .frame(minWidth: 160)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.white)
        }
    }
}
