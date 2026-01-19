import Foundation

enum DorisState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error(String)
}
