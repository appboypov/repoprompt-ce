import Foundation

extension ContextBuilderResponseType {
    var headlessMode: HeadlessMode? {
        switch self {
        case .plan:
            .plan
        case .question:
            .chat
        case .review:
            .review
        case .clarify:
            nil
        }
    }
}
