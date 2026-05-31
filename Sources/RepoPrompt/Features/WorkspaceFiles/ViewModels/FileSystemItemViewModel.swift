import Foundation

protocol FileSystemItemViewModel: Identifiable, Equatable {
    var id: UUID { get }
    var name: String { get }
    var nameSortKey: String { get }
    var relativePath: String { get }
    var fullPath: String { get }
    var modificationDate: Date { get }
    var fileExtension: String? { get }
}

enum FileSystemItemType: Identifiable, Equatable, Hashable {
    case folder(FolderViewModel)
    case file(FileViewModel)

    var id: UUID {
        switch self {
        case let .folder(folder): folder.id
        case let .file(file): file.id
        }
    }

    var relativePath: String {
        switch self {
        case let .folder(folder): folder.relativePath
        case let .file(file): file.relativePath
        }
    }

    var fullPath: String {
        switch self {
        case let .folder(folder): folder.fullPath
        case let .file(file): file.fullPath
        }
    }

    static func == (lhs: FileSystemItemType, rhs: FileSystemItemType) -> Bool {
        switch (lhs, rhs) {
        case let (.folder(lhsFolder), .folder(rhsFolder)):
            lhsFolder == rhsFolder
        case let (.file(lhsFile), .file(rhsFile)):
            lhsFile == rhsFile
        case (.folder, .file), (.file, .folder):
            false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .folder(folder):
            hasher.combine("folder")
            hasher.combine(folder.id)
        case let .file(file):
            hasher.combine("file")
            hasher.combine(file.id)
        }
    }
}
