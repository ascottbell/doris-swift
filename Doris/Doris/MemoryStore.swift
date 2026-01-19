//
//  MemoryStore.swift
//  Doris
//
//  Created by Adam Bell on 12/30/25.
//

import Foundation
import SQLite3

class MemoryStore {
    private var db: OpaquePointer?
    private let dbPath: String
    private let schemaVersion = 3  // Increment when schema changes
    
    init() {
        // Create Application Support directory if needed
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dorisDir = appSupport.appendingPathComponent("Doris")
        
        do {
            try FileManager.default.createDirectory(at: dorisDir, withIntermediateDirectories: true)
            dbPath = dorisDir.appendingPathComponent("doris.db").path
            print("🟢 MemoryStore: Database path: \(dbPath)")
        } catch {
            fatalError("Failed to create Doris directory: \(error)")
        }
        
        openDatabase()
        migrateIfNeeded()
    }
    
    deinit {
        closeDatabase()
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("🔴 MemoryStore: Error opening database")
            return
        }
        print("🟢 MemoryStore: Database opened successfully")
    }
    
    private func closeDatabase() {
        if sqlite3_close(db) != SQLITE_OK {
            print("🔴 MemoryStore: Error closing database")
        }
    }
    
    // MARK: - Schema Migration
    
    private func getCurrentSchemaVersion() -> Int {
        var statement: OpaquePointer?
        let query = "PRAGMA user_version;"
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        
        var version = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            version = Int(sqlite3_column_int(statement, 0))
        }
        sqlite3_finalize(statement)
        return version
    }
    
    private func setSchemaVersion(_ version: Int) {
        let query = "PRAGMA user_version = \(version);"
        sqlite3_exec(db, query, nil, nil, nil)
    }
    
    private func migrateIfNeeded() {
        let currentVersion = getCurrentSchemaVersion()
        print("🟡 MemoryStore: Current schema version: \(currentVersion), target: \(schemaVersion)")
        
        if currentVersion < 1 {
            // Fresh install - create v2 schema directly
            createTablesV2()
            createConversationTables()
            setSchemaVersion(schemaVersion)
            print("🟢 MemoryStore: Created fresh v3 schema")
            return
        }
        
        if currentVersion < 2 {
            // Migrate from v1 to v2
            migrateV1toV2()
            setSchemaVersion(2)
            print("🟢 MemoryStore: Migrated from v1 to v2")
        }
        
        if currentVersion < 3 {
            // Add conversation tables
            createConversationTables()
            setSchemaVersion(3)
            print("🟢 MemoryStore: Migrated to v3 - added conversations")
        }
    }
    
    private func createTablesV2() {
        let createTableQuery = """
            CREATE TABLE IF NOT EXISTS memories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                content TEXT NOT NULL,
                category TEXT NOT NULL,
                source TEXT NOT NULL DEFAULT 'explicit',
                subject TEXT,
                confidence REAL DEFAULT 1.0,
                last_confirmed DATETIME,
                supersedes INTEGER,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (supersedes) REFERENCES memories(id)
            );
            """
        
        if sqlite3_exec(db, createTableQuery, nil, nil, nil) != SQLITE_OK {
            print("🔴 MemoryStore: Error creating memories table")
            return
        }
        
        // Create index on subject for fast lookups
        let indexQuery = "CREATE INDEX IF NOT EXISTS idx_memories_subject ON memories(subject);"
        sqlite3_exec(db, indexQuery, nil, nil, nil)
        
        print("🟢 MemoryStore: Tables created")
    }
    
    private func migrateV1toV2() {
        // Add new columns to existing table
        let migrations = [
            "ALTER TABLE memories ADD COLUMN source TEXT NOT NULL DEFAULT 'explicit';",
            "ALTER TABLE memories ADD COLUMN subject TEXT;",
            "ALTER TABLE memories ADD COLUMN confidence REAL DEFAULT 1.0;",
            "ALTER TABLE memories ADD COLUMN last_confirmed DATETIME;",
            "ALTER TABLE memories ADD COLUMN supersedes INTEGER;",
            "ALTER TABLE memories ADD COLUMN updated_at DATETIME DEFAULT CURRENT_TIMESTAMP;",
            "CREATE INDEX IF NOT EXISTS idx_memories_subject ON memories(subject);"
        ]
        
        for migration in migrations {
            if sqlite3_exec(db, migration, nil, nil, nil) != SQLITE_OK {
                // Column might already exist, that's okay
                print("🟡 MemoryStore: Migration step skipped (may already exist): \(migration.prefix(50))...")
            }
        }
    }
    
    private func createConversationTables() {
        let createConversationsTable = """
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT,
                summary TEXT,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
            );
            """
        
        let createMessagesTable = """
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversation_id INTEGER NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            );
            """
        
        if sqlite3_exec(db, createConversationsTable, nil, nil, nil) != SQLITE_OK {
            print("🔴 MemoryStore: Error creating conversations table")
        }
        
        if sqlite3_exec(db, createMessagesTable, nil, nil, nil) != SQLITE_OK {
            print("🔴 MemoryStore: Error creating messages table")
        }
        
        // Create indexes for fast lookups
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC);", nil, nil, nil)
        
        // FTS5 for full-text search on messages
        let createFTS = """
            CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                content,
                content='messages',
                content_rowid='id'
            );
            """
        sqlite3_exec(db, createFTS, nil, nil, nil)
        
        // Triggers to keep FTS in sync
        let insertTrigger = """
            CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
                INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
            END;
            """
        let deleteTrigger = """
            CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
                INSERT INTO messages_fts(messages_fts, rowid, content) VALUES('delete', old.id, old.content);
            END;
            """
        let updateTrigger = """
            CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
                INSERT INTO messages_fts(messages_fts, rowid, content) VALUES('delete', old.id, old.content);
                INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
            END;
            """
        
        sqlite3_exec(db, insertTrigger, nil, nil, nil)
        sqlite3_exec(db, deleteTrigger, nil, nil, nil)
        sqlite3_exec(db, updateTrigger, nil, nil, nil)
        
        print("🟢 MemoryStore: Conversation tables created with FTS")
    }
    
    // MARK: - Conversation Methods
    
    func createConversation(title: String? = nil) -> Int? {
        let query = "INSERT INTO conversations (title) VALUES (?);"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("🔴 MemoryStore: Error preparing create conversation")
            return nil
        }
        
        if let title = title {
            sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 1)
        }
        
        if sqlite3_step(statement) == SQLITE_DONE {
            let id = Int(sqlite3_last_insert_rowid(db))
            sqlite3_finalize(statement)
            print("🟢 MemoryStore: Created conversation \(id)")
            return id
        }
        
        sqlite3_finalize(statement)
        return nil
    }
    
    func addMessage(conversationId: Int, role: String, content: String) -> Int? {
        let query = "INSERT INTO messages (conversation_id, role, content) VALUES (?, ?, ?);"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("🔴 MemoryStore: Error preparing add message")
            return nil
        }
        
        sqlite3_bind_int(statement, 1, Int32(conversationId))
        sqlite3_bind_text(statement, 2, (role as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (content as NSString).utf8String, -1, nil)
        
        if sqlite3_step(statement) == SQLITE_DONE {
            let id = Int(sqlite3_last_insert_rowid(db))
            sqlite3_finalize(statement)
            
            // Update conversation's updated_at
            let updateQuery = "UPDATE conversations SET updated_at = CURRENT_TIMESTAMP WHERE id = ?;"
            var updateStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, updateQuery, -1, &updateStmt, nil) == SQLITE_OK {
                sqlite3_bind_int(updateStmt, 1, Int32(conversationId))
                sqlite3_step(updateStmt)
                sqlite3_finalize(updateStmt)
            }
            
            return id
        }
        
        sqlite3_finalize(statement)
        return nil
    }
    
    func updateConversationTitle(_ conversationId: Int, title: String) {
        let query = "UPDATE conversations SET title = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        
        sqlite3_bind_text(statement, 1, (title as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 2, Int32(conversationId))
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }
    
    func updateConversationSummary(_ conversationId: Int, summary: String) {
        let query = "UPDATE conversations SET summary = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return }
        
        sqlite3_bind_text(statement, 1, (summary as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 2, Int32(conversationId))
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }
    
    func getConversations(limit: Int = 50, offset: Int = 0) -> [Conversation] {
        let query = """
            SELECT c.id, c.title, c.summary, c.created_at, c.updated_at,
                   (SELECT COUNT(*) FROM messages WHERE conversation_id = c.id) as message_count
            FROM conversations c
            ORDER BY c.updated_at DESC
            LIMIT ? OFFSET ?;
            """
        var statement: OpaquePointer?
        var conversations: [Conversation] = []
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        
        sqlite3_bind_int(statement, 1, Int32(limit))
        sqlite3_bind_int(statement, 2, Int32(offset))
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            
            var title: String? = nil
            if let titleCStr = sqlite3_column_text(statement, 1) {
                title = String(cString: titleCStr)
            }
            
            var summary: String? = nil
            if let summaryCStr = sqlite3_column_text(statement, 2) {
                summary = String(cString: summaryCStr)
            }
            
            var createdAt = Date()
            if let createdCStr = sqlite3_column_text(statement, 3) {
                createdAt = dateFormatter.date(from: String(cString: createdCStr)) ?? Date()
            }
            
            var updatedAt = Date()
            if let updatedCStr = sqlite3_column_text(statement, 4) {
                updatedAt = dateFormatter.date(from: String(cString: updatedCStr)) ?? Date()
            }
            
            let messageCount = Int(sqlite3_column_int(statement, 5))
            
            conversations.append(Conversation(
                id: id,
                title: title,
                summary: summary,
                messageCount: messageCount,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
        
        sqlite3_finalize(statement)
        return conversations
    }
    
    func getConversation(_ id: Int) -> Conversation? {
        let query = """
            SELECT c.id, c.title, c.summary, c.created_at, c.updated_at,
                   (SELECT COUNT(*) FROM messages WHERE conversation_id = c.id) as message_count
            FROM conversations c WHERE c.id = ?;
            """
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        
        sqlite3_bind_int(statement, 1, Int32(id))
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        var conversation: Conversation? = nil
        
        if sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            
            var title: String? = nil
            if let titleCStr = sqlite3_column_text(statement, 1) {
                title = String(cString: titleCStr)
            }
            
            var summary: String? = nil
            if let summaryCStr = sqlite3_column_text(statement, 2) {
                summary = String(cString: summaryCStr)
            }
            
            var createdAt = Date()
            if let createdCStr = sqlite3_column_text(statement, 3) {
                createdAt = dateFormatter.date(from: String(cString: createdCStr)) ?? Date()
            }
            
            var updatedAt = Date()
            if let updatedCStr = sqlite3_column_text(statement, 4) {
                updatedAt = dateFormatter.date(from: String(cString: updatedCStr)) ?? Date()
            }
            
            let messageCount = Int(sqlite3_column_int(statement, 5))
            
            conversation = Conversation(
                id: id,
                title: title,
                summary: summary,
                messageCount: messageCount,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
        
        sqlite3_finalize(statement)
        return conversation
    }
    
    func getMessages(conversationId: Int) -> [ChatMessage] {
        let query = "SELECT id, role, content, created_at FROM messages WHERE conversation_id = ? ORDER BY created_at ASC;"
        var statement: OpaquePointer?
        var messages: [ChatMessage] = []
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        
        sqlite3_bind_int(statement, 1, Int32(conversationId))
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(statement, 0))
            let role = String(cString: sqlite3_column_text(statement, 1))
            let content = String(cString: sqlite3_column_text(statement, 2))
            
            var createdAt = Date()
            if let createdCStr = sqlite3_column_text(statement, 3) {
                createdAt = dateFormatter.date(from: String(cString: createdCStr)) ?? Date()
            }
            
            messages.append(ChatMessage(
                id: id,
                conversationId: conversationId,
                role: role,
                content: content,
                createdAt: createdAt
            ))
        }
        
        sqlite3_finalize(statement)
        return messages
    }
    
    func searchConversations(query searchQuery: String) -> [SearchResult] {
        // Use FTS5 to search message content
        let query = """
            SELECT m.id, m.conversation_id, m.role, m.content, m.created_at,
                   c.title, c.summary
            FROM messages_fts fts
            JOIN messages m ON fts.rowid = m.id
            JOIN conversations c ON m.conversation_id = c.id
            WHERE messages_fts MATCH ?
            ORDER BY rank
            LIMIT 50;
            """
        var statement: OpaquePointer?
        var results: [SearchResult] = []
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("🔴 MemoryStore: Error preparing search query")
            return []
        }
        
        // FTS5 query syntax - wrap in quotes for phrase search or use as-is for word search
        let ftsQuery = searchQuery
        sqlite3_bind_text(statement, 1, (ftsQuery as NSString).utf8String, -1, nil)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let messageId = Int(sqlite3_column_int(statement, 0))
            let conversationId = Int(sqlite3_column_int(statement, 1))
            let role = String(cString: sqlite3_column_text(statement, 2))
            let content = String(cString: sqlite3_column_text(statement, 3))
            
            var createdAt = Date()
            if let createdCStr = sqlite3_column_text(statement, 4) {
                createdAt = dateFormatter.date(from: String(cString: createdCStr)) ?? Date()
            }
            
            var conversationTitle: String? = nil
            if let titleCStr = sqlite3_column_text(statement, 5) {
                conversationTitle = String(cString: titleCStr)
            }
            
            results.append(SearchResult(
                messageId: messageId,
                conversationId: conversationId,
                conversationTitle: conversationTitle,
                role: role,
                content: content,
                createdAt: createdAt
            ))
        }
        
        sqlite3_finalize(statement)
        print("🟡 MemoryStore: Search for '\(searchQuery)' returned \(results.count) results")
        return results
    }
    
    func deleteConversation(_ id: Int) -> Bool {
        // Messages will be cascade deleted due to foreign key
        let query = "DELETE FROM conversations WHERE id = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        
        sqlite3_bind_int(statement, 1, Int32(id))
        let success = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        
        if success {
            print("🟢 MemoryStore: Deleted conversation \(id)")
        }
        return success
    }
    
    // MARK: - Add Memory (v2)
    
    func addMemory(
        content: String,
        category: MemoryCategory,
        source: MemorySource = .explicit,
        subject: String? = nil,
        confidence: Double = 1.0
    ) -> Int? {
        let insertQuery = """
            INSERT INTO memories (content, category, source, subject, confidence, last_confirmed)
            VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP);
            """
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK else {
            print("🔴 MemoryStore: Error preparing insert statement")
            return nil
        }
        
        sqlite3_bind_text(statement, 1, (content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (category.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, (source.rawValue as NSString).utf8String, -1, nil)
        
        if let subject = subject {
            sqlite3_bind_text(statement, 4, (subject as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        
        sqlite3_bind_double(statement, 5, confidence)
        
        if sqlite3_step(statement) == SQLITE_DONE {
            let newId = Int(sqlite3_last_insert_rowid(db))
            print("🟢 MemoryStore: Memory added (id: \(newId)) - [\(category.rawValue)] \(content)")
            sqlite3_finalize(statement)
            return newId
        } else {
            print("🔴 MemoryStore: Error inserting memory")
            sqlite3_finalize(statement)
            return nil
        }
    }
    
    // Legacy support - returns Bool for backward compatibility
    func addMemory(content: String, category: MemoryCategory) -> Bool {
        return addMemory(content: content, category: category, source: .explicit, subject: nil) != nil
    }
    
    // MARK: - Update Memory
    
    func updateMemory(
        id: Int,
        content: String? = nil,
        category: MemoryCategory? = nil,
        subject: String? = nil,
        confidence: Double? = nil
    ) -> Bool {
        var updates: [String] = []
        var values: [Any] = []
        
        if let content = content {
            updates.append("content = ?")
            values.append(content)
        }
        if let category = category {
            updates.append("category = ?")
            values.append(category.rawValue)
        }
        if let subject = subject {
            updates.append("subject = ?")
            values.append(subject)
        }
        if let confidence = confidence {
            updates.append("confidence = ?")
            values.append(confidence)
        }
        
        updates.append("updated_at = CURRENT_TIMESTAMP")
        updates.append("last_confirmed = CURRENT_TIMESTAMP")
        
        let query = "UPDATE memories SET \(updates.joined(separator: ", ")) WHERE id = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("🔴 MemoryStore: Error preparing update statement")
            return false
        }
        
        var bindIndex: Int32 = 1
        for value in values {
            if let str = value as? String {
                sqlite3_bind_text(statement, bindIndex, (str as NSString).utf8String, -1, nil)
            } else if let num = value as? Double {
                sqlite3_bind_double(statement, bindIndex, num)
            }
            bindIndex += 1
        }
        sqlite3_bind_int(statement, bindIndex, Int32(id))
        
        let success = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        
        if success {
            print("🟢 MemoryStore: Memory updated (id: \(id))")
        } else {
            print("🔴 MemoryStore: Error updating memory")
        }
        
        return success
    }
    
    // MARK: - Supersede Memory (for corrections)
    
    func supersedeMemory(oldId: Int, newContent: String, category: MemoryCategory, subject: String? = nil) -> Int? {
        // First, get the old memory to preserve context
        guard let oldMemory = getMemory(byId: oldId) else {
            print("🔴 MemoryStore: Cannot supersede - old memory not found")
            return nil
        }
        
        // Create new memory that supersedes the old one
        let insertQuery = """
            INSERT INTO memories (content, category, source, subject, confidence, supersedes, last_confirmed)
            VALUES (?, ?, 'explicit', ?, 1.0, ?, CURRENT_TIMESTAMP);
            """
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) == SQLITE_OK else {
            print("🔴 MemoryStore: Error preparing supersede insert")
            return nil
        }
        
        sqlite3_bind_text(statement, 1, (newContent as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (category.rawValue as NSString).utf8String, -1, nil)
        
        let effectiveSubject = subject ?? oldMemory.subject
        if let subj = effectiveSubject {
            sqlite3_bind_text(statement, 3, (subj as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        
        sqlite3_bind_int(statement, 4, Int32(oldId))
        
        if sqlite3_step(statement) == SQLITE_DONE {
            let newId = Int(sqlite3_last_insert_rowid(db))
            sqlite3_finalize(statement)
            
            // Mark old memory as superseded by reducing confidence
            _ = updateMemory(id: oldId, confidence: 0.0)
            
            print("🟢 MemoryStore: Memory \(oldId) superseded by \(newId)")
            return newId
        } else {
            sqlite3_finalize(statement)
            return nil
        }
    }
    
    // MARK: - Get Single Memory
    
    func getMemory(byId id: Int) -> Memory? {
        let query = """
            SELECT id, content, category, source, subject, confidence, last_confirmed, supersedes, created_at, updated_at
            FROM memories WHERE id = ?;
            """
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        
        sqlite3_bind_int(statement, 1, Int32(id))
        
        var memory: Memory?
        if sqlite3_step(statement) == SQLITE_ROW {
            memory = parseMemoryFromStatementV2(statement)
        }
        
        sqlite3_finalize(statement)
        return memory
    }
    
    // MARK: - Get All Memories
    
    func getAllMemories(includeSuperseded: Bool = false) -> [Memory] {
        let query: String
        if includeSuperseded {
            query = """
                SELECT id, content, category, source, subject, confidence, last_confirmed, supersedes, created_at, updated_at
                FROM memories ORDER BY created_at DESC;
                """
        } else {
            query = """
                SELECT id, content, category, source, subject, confidence, last_confirmed, supersedes, created_at, updated_at
                FROM memories WHERE confidence > 0 ORDER BY created_at DESC;
                """
        }
        return executeQueryV2(query)
    }
    
    // MARK: - Search Memories
    
    func searchMemories(keyword: String) -> [Memory] {
        let query = """
            SELECT id, content, category, source, subject, confidence, last_confirmed, supersedes, created_at, updated_at
            FROM memories WHERE content LIKE ? AND confidence > 0 ORDER BY confidence DESC, created_at DESC;
            """
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("🔴 MemoryStore: Error preparing search statement")
            return []
        }
        
        let searchPattern = "%\(keyword)%"
        sqlite3_bind_text(statement, 1, (searchPattern as NSString).utf8String, -1, nil)
        
        var memories: [Memory] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let memory = parseMemoryFromStatementV2(statement) {
                memories.append(memory)
            }
        }
        
        sqlite3_finalize(statement)
        print("🟡 MemoryStore: Search for '\(keyword)' returned \(memories.count) results")
        return memories
    }
    
    // MARK: - Get Memories by Subject
    
    func getMemories(bySubject subject: String) -> [Memory] {
        // Search for subject in comma-separated list
        let query = """
            SELECT id, content, category, source, subject, confidence, last_confirmed, supersedes, created_at, updated_at
            FROM memories 
            WHERE (subject LIKE ? OR subject LIKE ? OR subject LIKE ? OR subject = ?)
            AND confidence > 0
            ORDER BY confidence DESC, created_at DESC;
            """
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("🔴 MemoryStore: Error preparing subject query")
            return []
        }
        
        // Match: "subject,...", "...,subject,...", "...,subject", or exact match
        let subjectLower = subject.lowercased()
        sqlite3_bind_text(statement, 1, ("\(subjectLower),%"  as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, ("%,\(subjectLower),%" as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 3, ("%,\(subjectLower)" as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 4, (subjectLower as NSString).utf8String, -1, nil)
        
        var memories: [Memory] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let memory = parseMemoryFromStatementV2(statement) {
                memories.append(memory)
            }
        }
        
        sqlite3_finalize(statement)
        print("🟡 MemoryStore: Found \(memories.count) memories about '\(subject)'")
        return memories
    }
    
    // MARK: - Get All Known Subjects
    
    func getAllSubjects() -> [String] {
        let query = "SELECT DISTINCT subject FROM memories WHERE subject IS NOT NULL AND confidence > 0;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        
        var subjects: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let subjectCString = sqlite3_column_text(statement, 0) {
                let subjectStr = String(cString: subjectCString)
                // Split comma-separated subjects
                for s in subjectStr.split(separator: ",") {
                    subjects.insert(s.trimmingCharacters(in: .whitespaces).lowercased())
                }
            }
        }
        
        sqlite3_finalize(statement)
        return Array(subjects).sorted()
    }
    
    // MARK: - Get Memories by Category
    
    func getMemories(byCategory category: MemoryCategory) -> [Memory] {
        let query = """
            SELECT id, content, category, source, subject, confidence, last_confirmed, supersedes, created_at, updated_at
            FROM memories WHERE category = ? AND confidence > 0 ORDER BY created_at DESC;
            """
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("🔴 MemoryStore: Error preparing category query")
            return []
        }
        
        sqlite3_bind_text(statement, 1, (category.rawValue as NSString).utf8String, -1, nil)
        
        var memories: [Memory] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let memory = parseMemoryFromStatementV2(statement) {
                memories.append(memory)
            }
        }
        
        sqlite3_finalize(statement)
        return memories
    }
    
    // MARK: - Delete Memory
    
    func deleteMemory(id: Int) -> Bool {
        let deleteQuery = "DELETE FROM memories WHERE id = ?;"
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) == SQLITE_OK else {
            print("🔴 MemoryStore: Error preparing delete statement")
            return false
        }
        
        sqlite3_bind_int(statement, 1, Int32(id))
        
        if sqlite3_step(statement) == SQLITE_DONE {
            print("🟢 MemoryStore: Memory deleted (id: \(id))")
            sqlite3_finalize(statement)
            return true
        } else {
            print("🔴 MemoryStore: Error deleting memory")
            sqlite3_finalize(statement)
            return false
        }
    }
    
    // MARK: - Find Similar Memories (for deduplication)
    
    func findSimilarMemories(content: String, subject: String? = nil) -> [Memory] {
        // Extract key words for matching (simple approach - could be improved with NLP)
        let words = content.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 }  // Skip short words
        
        guard !words.isEmpty else { return [] }
        
        var memories: [Memory] = []
        
        // If subject provided, check those first
        if let subject = subject {
            let subjectMemories = getMemories(bySubject: subject)
            memories.append(contentsOf: subjectMemories)
        }
        
        // Also search by content keywords
        for word in words.prefix(3) {  // Check first 3 significant words
            let found = searchMemories(keyword: word)
            for memory in found {
                if !memories.contains(where: { $0.id == memory.id }) {
                    memories.append(memory)
                }
            }
        }
        
        return memories
    }
    
    // MARK: - Helper Methods
    
    private func executeQueryV2(_ query: String) -> [Memory] {
        var statement: OpaquePointer?
        var memories: [Memory] = []
        
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("🔴 MemoryStore: Error preparing query")
            return []
        }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            if let memory = parseMemoryFromStatementV2(statement) {
                memories.append(memory)
            }
        }
        
        sqlite3_finalize(statement)
        print("🟡 MemoryStore: Retrieved \(memories.count) memories")
        return memories
    }
    
    private func parseMemoryFromStatementV2(_ statement: OpaquePointer?) -> Memory? {
        guard let statement = statement else { return nil }
        
        let id = Int(sqlite3_column_int(statement, 0))
        
        guard let contentCString = sqlite3_column_text(statement, 1),
              let categoryCString = sqlite3_column_text(statement, 2),
              let sourceCString = sqlite3_column_text(statement, 3) else {
            return nil
        }
        
        let content = String(cString: contentCString)
        let categoryString = String(cString: categoryCString)
        let sourceString = String(cString: sourceCString)
        
        guard let category = MemoryCategory(rawValue: categoryString) else {
            return nil
        }
        
        let source = MemorySource(rawValue: sourceString) ?? .explicit
        
        // Optional fields
        var subject: String?
        if let subjectCString = sqlite3_column_text(statement, 4) {
            subject = String(cString: subjectCString)
        }
        
        let confidence = sqlite3_column_double(statement, 5)
        
        var lastConfirmed: Date?
        if let lastConfirmedCString = sqlite3_column_text(statement, 6) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            lastConfirmed = dateFormatter.date(from: String(cString: lastConfirmedCString))
        }
        
        var supersedes: Int?
        if sqlite3_column_type(statement, 7) != SQLITE_NULL {
            supersedes = Int(sqlite3_column_int(statement, 7))
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        var createdAt = Date()
        if let createdAtCString = sqlite3_column_text(statement, 8) {
            createdAt = dateFormatter.date(from: String(cString: createdAtCString)) ?? Date()
        }
        
        var updatedAt = Date()
        if let updatedAtCString = sqlite3_column_text(statement, 9) {
            updatedAt = dateFormatter.date(from: String(cString: updatedAtCString)) ?? Date()
        }
        
        return Memory(
            id: id,
            content: content,
            category: category,
            source: source,
            subject: subject,
            confidence: confidence,
            lastConfirmed: lastConfirmed,
            supersedes: supersedes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    // Legacy parser for backward compatibility during migration
    private func parseMemoryFromStatement(_ statement: OpaquePointer?) -> Memory? {
        guard let statement = statement else { return nil }
        
        let id = Int(sqlite3_column_int(statement, 0))
        
        guard let contentCString = sqlite3_column_text(statement, 1),
              let categoryCString = sqlite3_column_text(statement, 2),
              let createdAtCString = sqlite3_column_text(statement, 3) else {
            return nil
        }
        
        let content = String(cString: contentCString)
        let categoryString = String(cString: categoryCString)
        let createdAtString = String(cString: createdAtCString)
        
        guard let category = MemoryCategory(rawValue: categoryString) else {
            return nil
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let createdAt = dateFormatter.date(from: createdAtString) ?? Date()
        
        return Memory(
            id: id,
            content: content,
            category: category,
            source: .explicit,
            subject: nil,
            confidence: 1.0,
            lastConfirmed: nil,
            supersedes: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
    
    // MARK: - Format for System Prompt
    
    func getMemoriesForSystemPrompt() -> String {
        let memories = getAllMemories()
        
        guard !memories.isEmpty else {
            return ""
        }
        
        // Group by subject first, then by category
        var memoriesBySubject: [String: [Memory]] = [:]
        var noSubjectMemories: [Memory] = []
        
        for memory in memories {
            if let subject = memory.subject {
                // Handle comma-separated subjects
                let subjects = subject.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                for s in subjects {
                    memoriesBySubject[s, default: []].append(memory)
                }
            } else {
                noSubjectMemories.append(memory)
            }
        }
        
        var promptAddition = "\n\nHere are things you remember:\n"
        
        // Add subject-grouped memories
        for subject in memoriesBySubject.keys.sorted() {
            promptAddition += "\nAbout \(subject.capitalized):\n"
            for memory in memoriesBySubject[subject]! {
                let confidenceMarker = memory.confidence < 1.0 ? " (uncertain)" : ""
                promptAddition += "- \(memory.content)\(confidenceMarker)\n"
            }
        }
        
        // Add memories without subject, grouped by category
        if !noSubjectMemories.isEmpty {
            var byCategory: [MemoryCategory: [Memory]] = [:]
            for memory in noSubjectMemories {
                byCategory[memory.category, default: []].append(memory)
            }
            
            promptAddition += "\nGeneral:\n"
            for category in MemoryCategory.allCases {
                if let items = byCategory[category], !items.isEmpty {
                    for memory in items {
                        promptAddition += "- [\(category.displayName)] \(memory.content)\n"
                    }
                }
            }
        }
        
        return promptAddition
    }
}

// MARK: - Models

struct Memory: Identifiable {
    let id: Int
    let content: String
    let category: MemoryCategory
    let source: MemorySource
    let subject: String?
    let confidence: Double
    let lastConfirmed: Date?
    let supersedes: Int?
    let createdAt: Date
    let updatedAt: Date
}

enum MemoryCategory: String, CaseIterable {
    case personal = "personal"
    case preference = "preference"
    case fact = "fact"
    case task = "task"
    case relationship = "relationship"
    
    var displayName: String {
        switch self {
        case .personal: return "Personal Info"
        case .preference: return "Preferences"
        case .fact: return "Facts"
        case .task: return "Tasks"
        case .relationship: return "Relationships"
        }
    }
}

enum MemorySource: String {
    case explicit = "explicit"    // User said "remember this"
    case inferred = "inferred"    // Extracted from conversation
}

// MARK: - Conversation Models

struct Conversation: Identifiable {
    let id: Int
    let title: String?
    let summary: String?
    let messageCount: Int
    let createdAt: Date
    let updatedAt: Date
    
    var displayTitle: String {
        title ?? "Conversation \(id)"
    }
}

struct ChatMessage: Identifiable {
    let id: Int
    let conversationId: Int
    let role: String  // "user" or "assistant"
    let content: String
    let createdAt: Date
    
    var isUser: Bool {
        role == "user"
    }
}

struct SearchResult {
    let messageId: Int
    let conversationId: Int
    let conversationTitle: String?
    let role: String
    let content: String
    let createdAt: Date
}
