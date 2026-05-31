import Foundation

/// Narrow per-call context handed to extracted window-tool providers.
struct MCPWindowToolContext {
    let toolName: String
    let windowID: Int
}
