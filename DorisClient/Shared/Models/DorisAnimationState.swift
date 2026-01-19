import Foundation

/// All possible states for the Doris animation
enum DorisAnimationState: Equatable {
    case idle
    case listening(power: Double)
    case thinking
    case speaking(power: Double)

    static func == (lhs: DorisAnimationState, rhs: DorisAnimationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.listening, .listening): return true
        case (.thinking, .thinking): return true
        case (.speaking, .speaking): return true
        default: return false
        }
    }

    var isCircle: Bool {
        switch self {
        case .idle, .listening, .speaking: return true
        case .thinking: return false
        }
    }

    var power: Double {
        switch self {
        case .idle: return 0
        case .listening(let p), .speaking(let p): return p
        case .thinking: return 0
        }
    }
}
