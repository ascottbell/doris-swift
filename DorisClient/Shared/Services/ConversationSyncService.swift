import Foundation
import Combine

/// Syncs conversation history across devices using iCloud key-value store
@MainActor
class ConversationSyncService: ObservableObject {
    static let shared = ConversationSyncService()

    private let store = NSUbiquitousKeyValueStore.default
    private let historyKey = "doris_conversation_history"
    private let maxMessages = 100  // Keep last 100 messages

    private init() {
        // Register for external changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )

        // Start syncing
        store.synchronize()
    }

    /// Load conversation history from iCloud
    func loadHistory() -> [ConversationMessage] {
        guard let data = store.data(forKey: historyKey),
              let messages = try? JSONDecoder().decode([SyncedMessage].self, from: data) else {
            print("ConversationSync: No history in iCloud or decode failed")
            return []
        }

        print("ConversationSync: Loaded \(messages.count) messages from iCloud")
        return messages.map { $0.toConversationMessage() }
    }

    /// Save conversation history to iCloud
    func saveHistory(_ messages: [ConversationMessage]) {
        // Keep only the most recent messages
        let recentMessages = Array(messages.suffix(maxMessages))

        let syncedMessages = recentMessages.map { SyncedMessage(from: $0) }

        guard let data = try? JSONEncoder().encode(syncedMessages) else {
            print("ConversationSync: Failed to encode messages")
            return
        }

        store.set(data, forKey: historyKey)
        store.synchronize()
        print("ConversationSync: Saved \(recentMessages.count) messages to iCloud")
    }

    /// Clear history from iCloud
    func clearHistory() {
        store.removeObject(forKey: historyKey)
        store.synchronize()
        print("ConversationSync: Cleared history from iCloud")
    }

    @objc private func storeDidChange(_ notification: Notification) {
        // Notify that history changed externally
        print("ConversationSync: External change detected")
        NotificationCenter.default.post(name: .conversationHistoryDidChange, object: nil)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let conversationHistoryDidChange = Notification.Name("conversationHistoryDidChange")
}

// MARK: - Synced Message (Codable wrapper)

private struct SyncedMessage: Codable {
    let id: String
    let text: String
    let isUser: Bool
    let timestamp: Date

    init(from message: ConversationMessage) {
        self.id = message.id.uuidString
        self.text = message.text
        self.isUser = message.isUser
        self.timestamp = message.timestamp
    }

    func toConversationMessage() -> ConversationMessage {
        ConversationMessage(
            id: UUID(uuidString: id) ?? UUID(),
            text: text,
            isUser: isUser,
            timestamp: timestamp
        )
    }
}
