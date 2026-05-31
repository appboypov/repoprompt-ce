import Foundation

extension HeadlessMode {
    var mcpModeName: String {
        switch self {
        case .plan:
            "plan"
        case .review:
            "review"
        case .chat:
            "chat"
        }
    }
}
