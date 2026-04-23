import OSLog

extension Logger {
    /// Builds a `com.drgmr.Voice` logger with the given category. Every
    /// file that logs should go through this so the subsystem string is
    /// not duplicated.
    nonisolated static func voice(_ category: String) -> Logger {
        Logger(subsystem: "com.drgmr.Voice", category: category)
    }
}
