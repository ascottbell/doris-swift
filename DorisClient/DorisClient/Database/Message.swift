import Foundation
import GRDB

/// Database model for conversation messages
/// Mirrors ConversationMessage but with GRDB persistence support
struct Message: Codable, Identifiable, FetchableRecord, PersistableRecord {
    let id: UUID
    let text: String
    let isUser: Bool
    let timestamp: Date

    static let databaseTableName = "messages"

    init(id: UUID = UUID(), text: String, isUser: Bool, timestamp: Date = Date()) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.timestamp = timestamp
    }

    // MARK: - Database Columns

    enum Columns: String, ColumnExpression {
        case id, text, isUser, timestamp
    }
}

// MARK: - ConversationMessage Mapping

extension Message {
    /// Initialize from a ConversationMessage
    init(from conversation: ConversationMessage) {
        self.init(
            id: conversation.id,
            text: conversation.text,
            isUser: conversation.isUser,
            timestamp: conversation.timestamp
        )
    }

    /// Convert to ConversationMessage for view layer
    func toConversationMessage() -> ConversationMessage {
        ConversationMessage(
            id: id,
            text: text,
            isUser: isUser,
            timestamp: timestamp
        )
    }
}
