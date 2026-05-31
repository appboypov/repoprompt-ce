import Foundation

struct WorkspaceRootShellProjection: Identifiable, Equatable {
    let id: UUID
    let name: String
    let fullPath: String
    let standardizedFullPath: String
    let isSystemRoot: Bool
}
