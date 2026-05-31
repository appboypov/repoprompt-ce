import Foundation

struct AppLaunchConfiguration {
    enum ForcedRootRoute: Equatable {
        case main
    }

    static let current = AppLaunchConfiguration(processInfo: .processInfo)

    let isUITestSession: Bool
    let suppressesWindowRestore: Bool
    let suppressesWindowPersistence: Bool
    let suppressesAgentSessionPersistence: Bool
    let suppressesNonessentialLaunchSideEffects: Bool
    let forcedRootRoute: ForcedRootRoute?
    #if DEBUG
        let agentChatStress: AgentChatStressLaunchConfiguration?
    #endif

    private init(processInfo: ProcessInfo) {
        let arguments = Set(processInfo.arguments)
        let environment = processInfo.environment
        let isUITestSession = arguments.contains("-RP_UITEST")
        #if DEBUG
            let agentChatStress = arguments.contains("-RP_AGENT_CHAT_STRESS")
                ? AgentChatStressLaunchConfiguration(environment: environment)
                : nil
            let isAgentChatStressEnabled = agentChatStress != nil
        #else
            let isAgentChatStressEnabled = false
        #endif
        let isDeterministicUITestLaunch = isUITestSession || isAgentChatStressEnabled
        #if DEBUG
            let allowsStressAgentSessionPersistence = agentChatStress?.allowsAgentSessionPersistence ?? false
        #else
            let allowsStressAgentSessionPersistence = false
        #endif

        self.isUITestSession = isUITestSession
        suppressesWindowRestore = isDeterministicUITestLaunch
        suppressesWindowPersistence = isDeterministicUITestLaunch
        suppressesAgentSessionPersistence = isDeterministicUITestLaunch && !allowsStressAgentSessionPersistence
        suppressesNonessentialLaunchSideEffects = isDeterministicUITestLaunch
        forcedRootRoute = isDeterministicUITestLaunch ? .main : nil
        #if DEBUG
            self.agentChatStress = agentChatStress
        #endif
    }
}
