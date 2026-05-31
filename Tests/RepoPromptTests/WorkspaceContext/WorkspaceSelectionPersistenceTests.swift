@testable import RepoPrompt
import XCTest

final class WorkspaceSelectionPersistenceTests: XCTestCase {
    override func tearDown() async throws {
        await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.removeAllForTesting()
        try await super.tearDown()
    }

    func testDiskWriterPreservesNewerSelectionRevisionAgainstLaterStalePayload() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceSelectionPersistenceTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let url = tempDir.appendingPathComponent("workspace.json")
        await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.removeAllForTesting()

        let workspaceID = UUID()
        let tabID = UUID()
        let correct = Self.workspace(
            id: workspaceID,
            tabID: tabID,
            selection: Self.selection(count: 7),
            dateModified: Date(timeIntervalSince1970: 100),
            promptText: "correct"
        )
        let correctData = try JSONEncoder().encode(correct)
        let correctMetadata = WorkspaceManagerViewModel.metadata(
            for: correct,
            source: "test.correctSelection",
            activeSelectionRevision: 1
        )

        await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.enqueueWorkspace(data: correctData, url: url, metadata: correctMetadata)
        await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.flush(url: url)

        let stale = Self.workspace(
            id: workspaceID,
            tabID: tabID,
            selection: Self.selection(count: 15, includeSlices: true),
            dateModified: Date(timeIntervalSince1970: 200),
            promptText: "stale-non-selection-field"
        )
        let staleData = try JSONEncoder().encode(stale)
        let staleMetadata = WorkspaceManagerViewModel.metadata(
            for: stale,
            source: "test.staleSelection",
            activeSelectionRevision: 0
        )

        await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.enqueueWorkspace(data: staleData, url: url, metadata: staleMetadata)
        await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.flush(url: url)

        let decoded = try JSONDecoder().decode(WorkspaceModel.self, from: Data(contentsOf: url))
        let activeSelection = try XCTUnwrap(decoded.composeTabs.first(where: { $0.id == tabID })?.selection)
        XCTAssertEqual(activeSelection, correct.composeTabs[0].selection)
        XCTAssertEqual(decoded.composeTabs[0].promptText, "stale-non-selection-field")
    }

    func testDiskWriterMergesNewerSelectionIntoNewerDiskInsteadOfSkipping() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceSelectionPersistenceTests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let url = tempDir.appendingPathComponent("workspace.json")
        await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.removeAllForTesting()

        let workspaceID = UUID()
        let tabID = UUID()
        let staleDisk = Self.workspace(
            id: workspaceID,
            tabID: tabID,
            selection: Self.selection(count: 15, includeSlices: true),
            dateModified: Date(timeIntervalSince1970: 300),
            promptText: "disk-field"
        )
        try JSONEncoder().encode(staleDisk).write(to: url, options: .atomic)

        let incoming = Self.workspace(
            id: workspaceID,
            tabID: tabID,
            selection: Self.selection(count: 7),
            dateModified: Date(timeIntervalSince1970: 200),
            promptText: "incoming-field"
        )
        let metadata = WorkspaceManagerViewModel.metadata(
            for: incoming,
            source: "test.newerSelectionOlderPayload",
            activeSelectionRevision: 2
        )

        try await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.enqueueWorkspace(
            data: JSONEncoder().encode(incoming),
            url: url,
            metadata: metadata
        )
        await WorkspaceManagerViewModel.WorkspaceDiskWriter.shared.flush(url: url)

        let decoded = try JSONDecoder().decode(WorkspaceModel.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.composeTabs[0].selection, incoming.composeTabs[0].selection)
        XCTAssertEqual(decoded.composeTabs[0].promptText, "disk-field")
    }

    func testApplySelectionToWorkspaceUpdatesActiveTabOnly() {
        let workspaceID = UUID()
        let tabID = UUID()
        let stale = Self.selection(count: 15, includeSlices: true)
        let latest = Self.selection(count: 7)
        let workspace = Self.workspace(
            id: workspaceID,
            tabID: tabID,
            selection: stale,
            dateModified: Date(timeIntervalSince1970: 100),
            promptText: "keep prompt"
        )

        let result = WorkspaceManagerViewModel.workspaceByApplyingSelection(latest, toActiveTab: tabID, in: workspace)

        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.workspace.composeTabs[0].selection, latest)
        XCTAssertEqual(result.workspace.composeTabs[0].promptText, "keep prompt")
        XCTAssertEqual(result.workspace.repoPaths, workspace.repoPaths)
    }

    private static func workspace(
        id: UUID,
        tabID: UUID,
        selection: StoredSelection,
        dateModified: Date,
        promptText: String
    ) -> WorkspaceModel {
        let tab = ComposeTabState(id: tabID, name: "T1", selection: selection, promptText: promptText)
        return WorkspaceModel(
            id: id,
            dateModified: dateModified,
            name: "Selection Persistence",
            repoPaths: ["/tmp/root"],
            composeTabs: [tab],
            activeComposeTabID: tabID
        )
    }

    private static func selection(count: Int, includeSlices: Bool = false) -> StoredSelection {
        let paths = (0 ..< count).map { "/tmp/root/file\($0).swift" }
        let slices: [String: [LineRange]] = if includeSlices, let first = paths.first {
            [first: [LineRange(start: 1, end: 3), LineRange(start: 8, end: 13)]]
        } else {
            [:]
        }
        return StoredSelection(
            selectedPaths: paths,
            autoCodemapPaths: Array(paths.prefix(max(0, count / 3))),
            slices: slices,
            codemapAutoEnabled: !includeSlices
        )
    }
}
