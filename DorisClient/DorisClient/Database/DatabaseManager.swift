import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()

    private let dbPool: DatabasePool

    private init() {
        do {
            let fileManager = FileManager.default
            let appSupportURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = appSupportURL.appendingPathComponent("doris.sqlite")

            var config = Configuration()
            #if DEBUG
            config.prepareDatabase { db in
                db.trace { print("SQL: \($0)") }
            }
            #endif

            dbPool = try DatabasePool(path: dbURL.path, configuration: config)
            try migrator.migrate(dbPool)
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_createMessages") { db in
            // Create messages table
            try db.create(table: "messages") { t in
                t.column("id", .text).primaryKey()
                t.column("text", .text).notNull()
                t.column("isUser", .integer).notNull()
                t.column("timestamp", .text).notNull()
            }

            // Create FTS5 virtual table for full-text search
            try db.create(virtualTable: "messages_fts", using: FTS5()) { t in
                t.synchronize(withTable: "messages")
                t.column("text")
            }
        }

        return migrator
    }

    // MARK: - CRUD Operations

    /// Insert a new message into the database
    func insertMessage(_ message: Message) throws {
        try dbPool.write { db in
            try message.insert(db)
        }
    }

    /// Fetch recent messages with pagination support
    /// - Parameters:
    ///   - limit: Maximum number of messages to return
    ///   - offset: Number of messages to skip (for pagination)
    /// - Returns: Array of messages ordered by timestamp descending (newest first)
    func fetchRecentMessages(limit: Int, offset: Int = 0) throws -> [Message] {
        try dbPool.read { db in
            try Message
                .order(Message.Columns.timestamp.desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    /// Search messages using FTS5 full-text search
    /// - Parameter query: Search query string
    /// - Returns: Array of messages matching the query, ordered by relevance
    func searchMessages(query: String) throws -> [Message] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return try dbPool.read { db in
            let pattern = FTS5Pattern(matchingAllTokensIn: query)
            let sql = """
                SELECT messages.*
                FROM messages
                JOIN messages_fts ON messages_fts.rowid = messages.rowid
                WHERE messages_fts MATCH ?
                ORDER BY bm25(messages_fts)
                """
            return try Message.fetchAll(db, sql: sql, arguments: [pattern])
        }
    }

    /// Get total count of messages in the database
    func messageCount() throws -> Int {
        try dbPool.read { db in
            try Message.fetchCount(db)
        }
    }
}
