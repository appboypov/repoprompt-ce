import Foundation

@MainActor
protocol MCPWindowToolProviding {
    var group: MCPWindowToolGroup { get }
    func buildTools() -> [Tool]
}

@MainActor
final class MCPWindowToolCatalogService: WindowScopedService {
    let windowID: Int

    private let providers: [any MCPWindowToolProviding]
    private var toolsCache: [Tool]?

    init(windowID: Int, providers: [any MCPWindowToolProviding]) {
        self.windowID = windowID
        self.providers = providers
    }

    var tools: [Tool] {
        get async {
            if let toolsCache {
                return toolsCache
            }
            var providersByGroup: [MCPWindowToolGroup: [any MCPWindowToolProviding]] = [:]
            for provider in providers {
                providersByGroup[provider.group, default: []].append(provider)
            }
            let built = MCPWindowToolGroup.allCases.flatMap { group in
                providersByGroup[group]?.flatMap { $0.buildTools() } ?? []
            }
            toolsCache = built
            return built
        }
    }

    func invalidateToolsCache() {
        toolsCache = nil
    }
}
