extension WorkspaceFilesViewModel {
    var rootShellProjections: [WorkspaceRootShellProjection] {
        rootFolders.map { root in
            WorkspaceRootShellProjection(
                id: root.id,
                name: root.name,
                fullPath: root.fullPath,
                standardizedFullPath: root.standardizedFullPath,
                isSystemRoot: root.isSystemRoot
            )
        }
    }

    var visibleRootShellProjections: [WorkspaceRootShellProjection] {
        rootShellProjections.filter { !$0.isSystemRoot }
    }

    var visibleRootFolders: [FolderViewModel] {
        rootFolders.filter { !$0.isSystemRoot }
    }
}
