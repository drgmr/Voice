import Combine
import SwiftUI

struct PillRootView: View {
    @Bindable var controller: AppController

    var body: some View {
        ZStack {
            switch controller.state {
            case .idle:
                Color.clear
            case .recording:
                RecordingPill(startedAt: controller.recordingStartedAt ?? .now)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85)
                            .combined(with: .opacity)
                            .combined(with: .offset(y: 20)),
                        removal: .opacity.combined(with: .offset(y: -6))
                    ))
            case .transcribing:
                TranscribingPill()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: controller.state)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Shared chrome

private struct PillChrome<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.black.opacity(0.88))
            )
            .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 6)
            .fixedSize()
    }
}

private struct EscHint: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("esc")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.12))
                )
            Text("cancel")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

private struct PillSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: 20)
    }
}

// MARK: - Recording pill

private struct RecordingPill: View {
    let startedAt: Date
    @State private var now: Date = .now

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        PillChrome {
            HStack(spacing: 10) {
                MicTile()
                WaveformBars()
                Text(elapsedString)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                PillSeparator()
                EscHint()
            }
        }
        .onReceive(timer) { now = $0 }
    }

    private var elapsedString: String {
        let interval = max(0, now.timeIntervalSince(startedAt))
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct MicTile: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.22))
                .frame(width: 28, height: 28)
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.red)
                .scaleEffect(pulse ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
        }
        .onAppear { pulse = true }
    }
}

private struct WaveformBars: View {
    private static let count = 9

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.count, id: \.self) { i in
                WaveformBar(seed: Double(i))
            }
        }
        .frame(height: 22)
    }
}

private struct WaveformBar: View {
    let seed: Double
    @State private var amplitude: CGFloat = 0.35

    var body: some View {
        RoundedRectangle(cornerRadius: 1.25, style: .continuous)
            .fill(Color.white)
            .frame(width: 2.5, height: 6 + amplitude * 14)
            .onAppear {
                let duration = 0.42 + (seed.truncatingRemainder(dividingBy: 3)) * 0.08
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                ) {
                    amplitude = CGFloat(0.35 + (seed.truncatingRemainder(dividingBy: 5)) * 0.13)
                }
            }
    }
}

// MARK: - Transcribing pill

private struct TranscribingPill: View {
    var body: some View {
        PillChrome {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.22))
                        .frame(width: 28, height: 28)
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.variableColor.iterative.nonReversing)
                }
                Text("Cleaning up…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                PillSeparator()
                EscHint()
            }
        }
    }
}
