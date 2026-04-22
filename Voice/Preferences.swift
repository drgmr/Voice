import Foundation
import Observation

/// MainActor-isolated settings store backed by UserDefaults. Small and
/// intentionally flat — add a property here when a new user preference is
/// introduced, and watch it from SwiftUI via `@Observable`.
@Observable
@MainActor
final class Preferences {
    var inputDeviceID: String? {
        didSet {
            if let inputDeviceID {
                UserDefaults.standard.set(inputDeviceID, forKey: Self.inputDeviceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.inputDeviceKey)
            }
        }
    }

    var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey)
        }
    }

    /// Shared key name used by both Preferences and Recorder. Kept public so
    /// non-MainActor code can read the raw value directly from UserDefaults
    /// without needing a MainActor hop.
    nonisolated static let inputDeviceKey = "com.drgmr.Voice.inputDeviceID"
    nonisolated static let onboardingKey = "com.drgmr.Voice.hasCompletedOnboarding"

    init() {
        self.inputDeviceID = UserDefaults.standard.string(forKey: Self.inputDeviceKey)
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }
}
