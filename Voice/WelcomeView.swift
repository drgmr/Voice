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
                    case .preparing, .loading:
                        LoadingStage()
                    case .ready:
                        ReadyStage(onStart: { controller.finishOnboarding() })
                    case .failed(let message):
                        FailedStage(message: message, onRetry: { controller.retryModelLoad() })
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.smooth(duration: 0.35), value: controller.modelLoadState)
            }
            .padding(40)
        }
        .frame(minWidth: 520, minHeight: 480)
        .foregroundStyle(.white)
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
    var body: some View {
        VStack(spacing: 14) {
            Text("Welcome to Voice")
                .font(.system(size: 28, weight: .bold))

            Text("Setting up the on-device speech model.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))

            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(.white)
                .padding(.vertical, 8)

            Text("First time only. It runs entirely on your Mac — audio never leaves your device.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
    }
}

// MARK: - Ready stage

private struct ReadyStage: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("You're all set")
                .font(.system(size: 28, weight: .bold))

            Text("Hold or tap Fn anywhere to dictate.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))

            VStack(alignment: .leading, spacing: 12) {
                ShortcutRow(key: "Fn", description: "Hold to record while pressed, release to paste.")
                ShortcutRow(key: "Fn", description: "Quick-tap to start. Tap again to stop.")
                ShortcutRow(key: "esc", description: "Cancel recording or transcription at any time.")
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .frame(maxWidth: 420)

            Button(action: onStart) {
                Text("Get Started")
                    .font(.headline)
                    .frame(minWidth: 200)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 4)
        }
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
