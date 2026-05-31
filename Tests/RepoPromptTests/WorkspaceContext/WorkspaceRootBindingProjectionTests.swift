import Foundation
@testable import RepoPrompt
import XCTest

final class WorkspaceRootBindingProjectionTests: XCTestCase {
    func testSingleBoundRootProjectsRelativeAndLogicalPathsToWorktree() {
        let logicalRoot = WorkspaceRootRef(
            id: UUID(),
            name: "Project",
            fullPath: "/repo/project"
        )
        let physicalRoot = WorkspaceRootRef(
            id: UUID(),
            name: "Project",
            fullPath: "/tmp/worktrees/project-agent"
        )
        let binding = AgentSessionWorktreeBinding(
            id: "binding-1",
            repositoryID: "repo-1",
            repoKey: "repo-key",
            logicalRootPath: logicalRoot.fullPath,
            logicalRootName: logicalRoot.name,
            worktreeID: "wt-1",
            worktreeRootPath: physicalRoot.fullPath,
            source: "test"
        )
        let projection = WorkspaceRootBindingProjection(
            sessionID: UUID(),
            boundRoots: [.init(logicalRoot: logicalRoot, physicalRoot: physicalRoot, binding: binding)]
        )

        XCTAssertEqual(
            projection.translateInputPath("Sources/App.swift"),
            "/tmp/worktrees/project-agent/Sources/App.swift"
        )
        XCTAssertEqual(
            projection.translateInputPath("/repo/project/Sources/App.swift"),
            "/tmp/worktrees/project-agent/Sources/App.swift"
        )
        XCTAssertEqual(
            projection.translateInputPath("Project/Sources/App.swift"),
            "/tmp/worktrees/project-agent/Sources/App.swift"
        )
        XCTAssertEqual(
            projection.translateInputPath("/tmp/worktrees/project-agent/Sources/App.swift"),
            "/tmp/worktrees/project-agent/Sources/App.swift"
        )
        XCTAssertEqual(
            projection.projectedLogicalDisplayPath(forPhysicalPath: "/tmp/worktrees/project-agent/Sources/App.swift"),
            "Sources/App.swift"
        )
        XCTAssertNil(projection.projectedLogicalDisplayPath(forPhysicalPath: "/repo/project/Sources/App.swift"))
    }

    func testSingleBoundRootDoesNotStealUnboundRootAlias() {
        let logicalRoot = WorkspaceRootRef(id: UUID(), name: "Project", fullPath: "/repo/project")
        let docsRoot = WorkspaceRootRef(id: UUID(), name: "Docs", fullPath: "/repo/docs")
        let physicalRoot = WorkspaceRootRef(id: UUID(), name: "Project", fullPath: "/tmp/worktrees/project-agent")
        let binding = AgentSessionWorktreeBinding(
            id: "binding-1",
            repositoryID: "repo-1",
            repoKey: "repo-key",
            logicalRootPath: logicalRoot.fullPath,
            logicalRootName: logicalRoot.name,
            worktreeID: "wt-1",
            worktreeRootPath: physicalRoot.fullPath,
            source: "test"
        )
        let projection = WorkspaceRootBindingProjection(
            sessionID: UUID(),
            boundRoots: [.init(logicalRoot: logicalRoot, physicalRoot: physicalRoot, binding: binding)],
            visibleLogicalRoots: [logicalRoot, docsRoot]
        )

        XCTAssertEqual(projection.translateInputPath("Docs/README.md"), "Docs/README.md")
        XCTAssertEqual(
            projection.translateInputPath("Project/Sources/App.swift"),
            "/tmp/worktrees/project-agent/Sources/App.swift"
        )
        XCTAssertEqual(
            projection.projectedLogicalDisplayPath(forPhysicalPath: "/tmp/worktrees/project-agent/Sources/App.swift"),
            "Project/Sources/App.swift"
        )
    }

    func testBoundRootsForMetadataAreDeterministicallySorted() {
        let firstLogical = WorkspaceRootRef(id: UUID(), name: "A", fullPath: "/repo/a")
        let secondLogical = WorkspaceRootRef(id: UUID(), name: "B", fullPath: "/repo/b")
        let firstPhysical = WorkspaceRootRef(id: UUID(), name: "A", fullPath: "/tmp/wt/a")
        let secondPhysical = WorkspaceRootRef(id: UUID(), name: "B", fullPath: "/tmp/wt/b")
        let projection = WorkspaceRootBindingProjection(
            sessionID: UUID(),
            boundRoots: [
                .init(logicalRoot: secondLogical, physicalRoot: secondPhysical, binding: Self.binding(logicalRoot: secondLogical, physicalRoot: secondPhysical, worktreeID: "wt-b")),
                .init(logicalRoot: firstLogical, physicalRoot: firstPhysical, binding: Self.binding(logicalRoot: firstLogical, physicalRoot: firstPhysical, worktreeID: "wt-a"))
            ]
        )

        XCTAssertEqual(projection.boundRootsForMetadata.map(\.logicalRoot.standardizedFullPath), ["/repo/a", "/repo/b"])
        XCTAssertEqual(projection.boundRootsForMetadata.map(\.binding.worktreeID), ["wt-a", "wt-b"])
    }

    func testWorktreeScopeMetadataUsesBindingWorktreeNameForEffectiveName() throws {
        let logicalRoot = WorkspaceRootRef(id: UUID(), name: "Project", fullPath: "/repo/project")
        let physicalRoot = WorkspaceRootRef(id: UUID(), name: "Project", fullPath: "/tmp/worktrees/project-agent")
        let binding = AgentSessionWorktreeBinding(
            id: "binding-1",
            repositoryID: "repo-1",
            repoKey: "repo-key",
            logicalRootPath: logicalRoot.fullPath,
            logicalRootName: logicalRoot.name,
            worktreeID: "wt-1",
            worktreeRootPath: physicalRoot.fullPath,
            worktreeName: "project-agent",
            branch: "feature/demo",
            visualLabel: "Demo Worktree",
            source: "test"
        )
        let projection = WorkspaceRootBindingProjection(
            sessionID: UUID(),
            boundRoots: [.init(logicalRoot: logicalRoot, physicalRoot: physicalRoot, binding: binding)]
        )

        let scope = try XCTUnwrap(ToolResultDTOs.WorktreeScopeDTO.sessionBound(from: projection))
        let mapping = try XCTUnwrap(scope.rootMappings.first)
        XCTAssertEqual(scope.kind, "session_bound_worktree")
        XCTAssertEqual(mapping.logicalRootName, "Project")
        XCTAssertEqual(mapping.logicalRootPath, "/repo/project")
        XCTAssertEqual(mapping.effectiveRootName, "project-agent")
        XCTAssertEqual(mapping.effectiveRootPath, "/tmp/worktrees/project-agent")
        XCTAssertEqual(mapping.worktreeID, "wt-1")
        XCTAssertEqual(mapping.branch, "feature/demo")
        XCTAssertEqual(mapping.label, "Demo Worktree")
    }

    func testFileTreeSnapshotIsDisplayedAsLogicalRoot() {
        let logicalRoot = WorkspaceRootRef(id: UUID(), name: "Project", fullPath: "/repo/project")
        let physicalRoot = WorkspaceRootRef(id: UUID(), name: "Project", fullPath: "/tmp/worktrees/project-agent")
        let binding = AgentSessionWorktreeBinding(
            id: "binding-1",
            repositoryID: "repo-1",
            repoKey: "repo-key",
            logicalRootPath: logicalRoot.fullPath,
            logicalRootName: logicalRoot.name,
            worktreeID: "wt-1",
            worktreeRootPath: physicalRoot.fullPath,
            source: "test"
        )
        let projection = WorkspaceRootBindingProjection(
            sessionID: UUID(),
            boundRoots: [.init(logicalRoot: logicalRoot, physicalRoot: physicalRoot, binding: binding)]
        )
        let rootID = UUID()
        let childID = UUID()
        let snapshot = FileTreeSelectionSnapshot(
            roots: [
                FileTreeFolderSnapshot(
                    id: rootID,
                    name: "project-agent",
                    fullPath: "/tmp/worktrees/project-agent",
                    standardizedFullPath: "/tmp/worktrees/project-agent",
                    standardizedRootPath: "/tmp/worktrees/project-agent",
                    children: [
                        .folder(FileTreeFolderSnapshot(
                            id: childID,
                            name: "Sources",
                            fullPath: "/tmp/worktrees/project-agent/Sources",
                            standardizedFullPath: "/tmp/worktrees/project-agent/Sources",
                            standardizedRootPath: "/tmp/worktrees/project-agent",
                            children: []
                        ))
                    ]
                )
            ],
            selectedFileIDs: [],
            mode: "full",
            showFullPaths: false,
            onlyIncludeRootsWithSelectedFiles: false,
            includeLegend: false
        )

        let logicalized = projection.logicalizeFileTreeSnapshot(snapshot)

        XCTAssertEqual(logicalized.roots.first?.name, "Project")
        XCTAssertEqual(logicalized.roots.first?.standardizedFullPath, "/repo/project")
        XCTAssertEqual(logicalized.roots.first?.standardizedRootPath, "/repo/project")
        guard case let .folder(child)? = logicalized.roots.first?.children.first else {
            return XCTFail("Expected logicalized child folder")
        }
        XCTAssertEqual(child.standardizedFullPath, "/repo/project/Sources")
        XCTAssertEqual(child.standardizedRootPath, "/repo/project")
    }

    private static func binding(
        logicalRoot: WorkspaceRootRef,
        physicalRoot: WorkspaceRootRef,
        worktreeID: String
    ) -> AgentSessionWorktreeBinding {
        AgentSessionWorktreeBinding(
            id: "binding-\(worktreeID)",
            repositoryID: "repo-\(worktreeID)",
            repoKey: "repo-key",
            logicalRootPath: logicalRoot.fullPath,
            logicalRootName: logicalRoot.name,
            worktreeID: worktreeID,
            worktreeRootPath: physicalRoot.fullPath,
            worktreeName: physicalRoot.fullPath.split(separator: "/").last.map(String.init),
            source: "test"
        )
    }
}
