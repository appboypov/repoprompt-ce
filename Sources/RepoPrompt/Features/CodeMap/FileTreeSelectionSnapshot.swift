import Foundation

struct FileTreeSelectionSnapshot {
    let roots: [FileTreeFolderSnapshot]
    let selectedFileIDs: Set<UUID>
    let mode: String
    let showFullPaths: Bool
    let onlyIncludeRootsWithSelectedFiles: Bool
    let includeLegend: Bool
    let showCodeMapMarkers: Bool
    let maxDepth: Int?

    init(
        roots: [FileTreeFolderSnapshot],
        selectedFileIDs: Set<UUID>,
        mode: String,
        showFullPaths: Bool,
        onlyIncludeRootsWithSelectedFiles: Bool,
        includeLegend: Bool,
        showCodeMapMarkers: Bool = true,
        maxDepth: Int? = nil
    ) {
        self.roots = roots
        self.selectedFileIDs = selectedFileIDs
        self.mode = mode
        self.showFullPaths = showFullPaths
        self.onlyIncludeRootsWithSelectedFiles = onlyIncludeRootsWithSelectedFiles
        self.includeLegend = includeLegend
        self.showCodeMapMarkers = showCodeMapMarkers
        self.maxDepth = maxDepth
    }
}

struct FileTreeFolderSnapshot: Hashable {
    let id: UUID
    let name: String
    let fullPath: String
    let standardizedFullPath: String
    let standardizedRootPath: String
    let children: [FileTreeNodeSnapshot]
}

struct FileTreeFileSnapshot: Hashable {
    let id: UUID
    let name: String
    let fileExtension: String?
    let hasCodeMap: Bool
}

indirect enum FileTreeNodeSnapshot: Hashable {
    case folder(FileTreeFolderSnapshot)
    case file(FileTreeFileSnapshot)

    var id: UUID {
        switch self {
        case let .folder(folder): folder.id
        case let .file(file): file.id
        }
    }

    var name: String {
        switch self {
        case let .folder(folder): folder.name
        case let .file(file): file.name
        }
    }
}
