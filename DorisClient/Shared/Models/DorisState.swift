import Foundation

enum DorisState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error(String)
}

/// Message model for conversation history
struct ConversationMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date
}
