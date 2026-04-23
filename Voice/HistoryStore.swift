import Foundation
import GRDB
import os

/// One recorded dictation round-trip, persisted to SQLite.
nonisolated struct TranscriptionEntry: Codable, Identifiable, Sendable, Equatable {
    var id: Int64?
    var createdAt: Date
    var durationMs: Int
    var rawText: String
    var finalText: String
    var language: String?
    var appBundleId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case durationMs = "duration_ms"
        case rawText = "raw_text"
        case finalText = "final_text"
        case language
        case appBundleId = "app_bundle_id"
    }
}

nonisolated extension TranscriptionEntry: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcriptions"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// SQLite-backed transcription history. Database lives under
/// `~/Library/Application Support/Voice/history.sqlite`; audio is never
/// stored, only the raw and post-processed text, timing, language, and
/// the frontmost app's bundle identifier at paste time.
actor HistoryStore {
    let databaseURL: URL

    private let dbQueue: DatabaseQueue
    private let log = Logger.voice("history")

    init() throws {
        self.databaseURL = AppPaths.historyDatabase
        self.dbQueue = try DatabaseQueue(path: databaseURL.path)
        try Self.migrator.migrate(dbQueue)
        log.info("HistoryStore opened at \(self.databaseURL.path, privacy: .public)")
    }

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("create_transcriptions") { db in
            try db.create(table: TranscriptionEntry.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("created_at", .datetime).notNull().indexed()
                t.column("duration_ms", .integer).notNull()
                t.column("raw_text", .text).notNull()
                t.column("final_text", .text).notNull()
                t.column("language", .text)
                t.column("app_bundle_id", .text)
            }
        }
        m.registerMigration("add_fts5_index") { db in
            try db.create(virtualTable: "transcriptions_fts", using: FTS5()) { t in
                t.synchronize(withTable: TranscriptionEntry.databaseTableName)
                t.column("final_text")
            }
        }
        return m
    }

    @discardableResult
    func insert(_ entry: TranscriptionEntry) throws -> TranscriptionEntry {
        var mutable = entry
        try dbQueue.write { db in
            try mutable.insert(db)
        }
        return mutable
    }

    func recent(limit: Int = 50) throws -> [TranscriptionEntry] {
        try dbQueue.read { db in
            try TranscriptionEntry
                .order(Column("created_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func clear() throws {
        _ = try dbQueue.write { db in
            try TranscriptionEntry.deleteAll(db)
        }
        log.info("History cleared")
    }

    func count() throws -> Int {
        try dbQueue.read { db in
            try TranscriptionEntry.fetchCount(db)
        }
    }

    func search(_ query: String, limit: Int = 100) throws -> [TranscriptionEntry] {
        try dbQueue.read { db in
            guard let pattern = FTS5Pattern(matchingAllTokensIn: query) else {
                return []
            }
            let sql = """
                SELECT transcriptions.*
                FROM transcriptions
                JOIN transcriptions_fts ON transcriptions_fts.rowid = transcriptions.id
                WHERE transcriptions_fts MATCH ?
                ORDER BY transcriptions.created_at DESC
                LIMIT ?
                """
            return try TranscriptionEntry.fetchAll(db, sql: sql, arguments: [pattern, limit])
        }
    }
}
