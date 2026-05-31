import MCP
@testable import RepoPrompt
import XCTest

@MainActor
final class ToolOutputFormatterWorktreeTests: XCTestCase {
    func testCreateOutputIncludesUsefulNextStepCommands() throws {
        let dto = ToolResultDTOs.ManageWorktreeReplyDTO(
            op: "create",
            worktree: Self.worktreeDTO(),
            createdWorktree: Self.worktreeDTO()
        )

        let text = try Self.onlyText(ToolOutputFormatter.formatManageWorktree(args: [:], value: Self.value(dto)))

        XCTAssertTrue(text.contains("### Created"))
        XCTAssertTrue(text.contains("### Next Steps"))
        XCTAssertTrue(text.contains("\"op\":\"show\""))
        XCTAssertTrue(text.contains("\"op\":\"bind\""))
        XCTAssertTrue(text.contains("\"op\":\"start\""))
        XCTAssertTrue(text.contains("\"worktree_id\":\"wt_feature\""))
    }

    func testBindOutputIncludesPreviousBindingAndNextStepCommands() throws {
        let dto = ToolResultDTOs.ManageWorktreeReplyDTO(
            op: "bind",
            worktree: Self.worktreeDTO(),
            binding: Self.bindingDTO(id: "new", worktreeID: "wt_feature"),
            previousBinding: Self.bindingDTO(id: "old", worktreeID: "wt_previous")
        )

        let text = try Self.onlyText(ToolOutputFormatter.formatManageWorktree(args: [:], value: Self.value(dto)))

        XCTAssertTrue(text.contains("### Binding"))
        XCTAssertTrue(text.contains("### Previous Binding"))
        XCTAssertTrue(text.contains("wt_previous"))
        XCTAssertTrue(text.contains("### Next Steps"))
        XCTAssertTrue(text.contains("agent_run"))
        XCTAssertFalse(text.contains("<session_id>"), "A completed bind should not suggest rebinding with a placeholder session id.")
    }

    func testGraphDTOEncodesInspectableMetadata() throws {
        let dto = ToolResultDTOs.ManageWorktreeReplyDTO(
            op: "list",
            worktrees: [Self.worktreeDTO()],
            graph: .init(
                requested: true,
                limit: 2,
                lines: ["* abc1234 (HEAD -> feature/demo) Demo", "* def5678 main"],
                source: "git log --graph --decorate --oneline --color=never -n 2"
            )
        )

        let object = try XCTUnwrap(Self.value(dto).objectValue)
        let graph = try XCTUnwrap(object["graph"]?.objectValue)
        XCTAssertEqual(graph["limit"]?.intValue, 2)
        XCTAssertEqual(graph["line_count"]?.intValue, 2)
        XCTAssertEqual(graph["truncated"]?.boolValue, false)
        XCTAssertEqual(graph["source"]?.stringValue, "git log --graph --decorate --oneline --color=never -n 2")
        XCTAssertEqual(graph["lines"]?.arrayValue?.first?.stringValue, "* abc1234 (HEAD -> feature/demo) Demo")
    }

    func testMergePreviewOutputUsesManageWorktreeHeaderAndNestedMergeBlock() throws {
        let dto = ToolResultDTOs.ManageWorktreeReplyDTO(
            op: "preview",
            merge: Self.mergeDTO(status: "preview")
        )

        let text = try Self.onlyText(ToolOutputFormatter.formatManageWorktree(args: [:], value: Self.value(dto)))

        XCTAssertTrue(text.contains("## Manage Worktree Preview"), text)
        XCTAssertTrue(text.contains("### ASCII Visualization"), text)
        XCTAssertTrue(text.contains("### Preflight"), text)
        XCTAssertTrue(text.contains("### Artifacts"), text)
        XCTAssertTrue(text.contains("Apply after approval: manage_worktree"), text)
        XCTAssertFalse(text.contains("## Merge Worktree"), text)
    }

    func testMergeConflictOutputShowsConflictsAndContinueActions() throws {
        let dto = ToolResultDTOs.ManageWorktreeReplyDTO(
            op: "apply",
            merge: Self.mergeDTO(
                status: "conflicted",
                conflictFiles: ["Sources/App.swift"],
                nextActions: [
                    "Continue after resolving: manage_worktree {\"op\":\"continue\",\"operation_id\":\"merge_123\",\"confirm\":true}",
                    "Abort if needed: manage_worktree {\"op\":\"abort\",\"operation_id\":\"merge_123\",\"confirm\":true}"
                ]
            )
        )

        let text = try Self.onlyText(ToolOutputFormatter.formatManageWorktree(args: [:], value: Self.value(dto)))

        XCTAssertTrue(text.contains("## Manage Worktree Apply ⚠️"), text)
        XCTAssertTrue(text.contains("### Conflicts"), text)
        XCTAssertTrue(text.contains("Sources/App.swift"), text)
        XCTAssertTrue(text.contains("manage_worktree {\"op\":\"continue\""), text)
    }

    func testFileTreeOutputShowsSessionBoundWorktreeScope() throws {
        let dto = ToolResultDTOs.FileTreeDTO(
            rootsCount: 1,
            usesLegend: false,
            tree: "Project\n└── Sources",
            worktreeScope: Self.scope()
        )

        let text = try Self.onlyText(ToolOutputFormatter.formatFileTree(value: Self.value(dto)))

        Self.assertScopeBlock(in: text)
        XCTAssertTrue(text.contains("Project\n└── Sources"), text)
    }

    func testFileSearchOutputShowsSessionBoundWorktreeScope() throws {
        let dto = ToolResultDTOs.SearchResultDTO(
            totalMatches: 1,
            totalFiles: 1,
            contentMatches: 1,
            pathMatches: 0,
            limitHit: false,
            perFileCounts: [.init(path: "Sources/App.swift", count: 1)],
            pathMatchLines: [],
            contentMatchGroups: [],
            worktreeScope: Self.scope()
        )

        let text = try Self.onlyText(ToolOutputFormatter.formatSearch(value: Self.value(dto)))

        Self.assertScopeBlock(in: text)
        XCTAssertTrue(text.contains("filesystem searches use"), text)
    }

    func testReadFileOutputShowsSessionBoundWorktreeScope() throws {
        let dto = ToolResultDTOs.ReadFileReply(
            content: "print(\"hi\")",
            totalLines: 1,
            firstLine: 1,
            lastLine: 1,
            displayPath: "Sources/App.swift",
            worktreeScope: Self.scope()
        )

        let text = try Self.onlyText(ToolOutputFormatter.formatReadFile(args: ["path": Self.value("Sources/App.swift")], value: Self.value(dto)))

        Self.assertScopeBlock(in: text)
        XCTAssertTrue(text.contains("filesystem reads use"), text)
        XCTAssertTrue(text.contains("```swift"), text)
    }

    func testWorkspaceContextOutputShowsSingleWorktreeScopeBlock() throws {
        let scope = Self.scope()
        let dto = ToolResultDTOs.PromptContextDTO(
            prompt: "",
            selection: nil,
            fileBlocks: nil,
            codeStructure: nil,
            fileTree: .init(
                rootsCount: 1,
                usesLegend: false,
                tree: "Project\n└── Sources",
                worktreeScope: scope
            ),
            tokenStats: nil,
            userTokenStats: nil,
            tokenStatsNote: nil,
            copyPreset: nil,
            copyPresets: nil,
            worktreeScope: scope
        )

        let text = try Self.onlyText(ToolOutputFormatter.formatPromptState(value: Self.value(dto)))

        Self.assertScopeBlock(in: text)
        XCTAssertEqual(Self.occurrences(of: "session-bound worktree", in: text), 1, text)
        XCTAssertTrue(text.contains("### Selected File Tree"), text)
    }

    func testAgentRunOutputShowsWorktreeSummaryAndUnavailableState() throws {
        let snapshot = AgentRunSnapshot(
            op: "start",
            status: "failed",
            sessionID: "session-1",
            session: Session(name: "Feature agent"),
            worktreeBindings: [
                WorktreeBinding(
                    worktreeID: "wt_missing",
                    worktreeRootPath: "/tmp/repo-missing",
                    worktreeName: "repo-missing",
                    branch: "feature/demo",
                    logicalRootName: "Repo",
                    logicalRootPath: "/tmp/repo",
                    visualLabel: "demo",
                    visualColorHex: "#2563EB",
                    unavailable: true
                )
            ]
        )

        let text = try Self.onlyText(ToolOutputFormatter.formatAgentRun(args: ["op": Self.value("start")], value: Self.value(snapshot)))

        XCTAssertTrue(text.contains("- Worktree: **demo**"))
        XCTAssertTrue(text.contains("branch `feature/demo`"))
        XCTAssertTrue(text.contains("`wt_missing`"))
        XCTAssertTrue(text.contains("path `/tmp/repo-missing`"))
        XCTAssertTrue(text.contains("⚠️ unavailable"))
    }

    private static func scope() -> ToolResultDTOs.WorktreeScopeDTO {
        ToolResultDTOs.WorktreeScopeDTO(
            kind: "session_bound_worktree",
            displayIdentity: "logical_canonical_root",
            effectiveIdentity: "bound_worktree_root",
            rootMappings: [
                .init(
                    logicalRootName: "Project",
                    logicalRootPath: "/repo/project",
                    effectiveRootName: "project-agent",
                    effectiveRootPath: "/tmp/worktrees/project-agent",
                    worktreeID: "wt_123",
                    worktreeName: "project-agent",
                    branch: "feature/demo",
                    label: "Demo Worktree"
                )
            ]
        )
    }

    private static func assertScopeBlock(in text: String) {
        XCTAssertTrue(text.contains("session-bound worktree"), text)
        XCTAssertTrue(text.contains("Displayed paths use logical/canonical roots"), text)
        XCTAssertTrue(text.contains("/repo/project"), text)
        XCTAssertTrue(text.contains("/tmp/worktrees/project-agent"), text)
        XCTAssertTrue(text.contains("wt_123"), text)
        XCTAssertTrue(text.contains("branch `feature/demo`"), text)
        XCTAssertTrue(text.contains("label `Demo Worktree`"), text)
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func mergeDTO(
        status: String,
        conflictFiles: [String]? = nil,
        nextActions: [String]? = nil
    ) -> ToolResultDTOs.ManageWorktreeReplyDTO.MergeDTO {
        .init(
            status: status,
            operationID: "merge_123",
            sessionID: "session_123",
            source: mergeEndpointDTO(label: "feature", path: "/tmp/repo-feature", branch: "feature/demo"),
            target: mergeEndpointDTO(label: "main", path: "/tmp/repo-main", branch: "main"),
            mergeBase: "1111111",
            sourceHead: "2222222",
            targetHeadBefore: "3333333",
            visualization: .init(
                requested: true,
                limit: 24,
                text: "target main\nsource feature",
                lines: ["target main", "source feature"],
                sourceWorktreeID: "wt_feature",
                targetWorktreeID: "wt_main",
                source: "manage_worktree.preview"
            ),
            preflight: .init(
                blocked: false,
                blockers: [],
                conflictPrediction: .init(status: "clean", files: [], message: nil)
            ),
            summary: .init(commits: 2, files: 4, insertions: 20, deletions: 5),
            artifacts: .init(
                snapshotID: "snapshot_123",
                snapshotDirectory: "/tmp/snapshot",
                manifestPath: "/tmp/snapshot/MAP.txt",
                mapPath: "/tmp/snapshot/MAP.txt",
                allPatchPath: "/tmp/snapshot/all.patch",
                sidecarPath: "/tmp/snapshot/merge_preview.json"
            ),
            conflictFiles: conflictFiles,
            nextActions: nextActions ?? ["Apply after approval: manage_worktree {\"op\":\"apply\",\"operation_id\":\"merge_123\",\"confirm_preview\":true}"]
        )
    }

    private static func mergeEndpointDTO(
        label: String,
        path: String,
        branch: String?
    ) -> ToolResultDTOs.ManageWorktreeReplyDTO.MergeDTO.EndpointDTO {
        .init(
            worktreeID: "wt_\(label)",
            repoKey: "repo-123",
            path: path,
            name: label,
            branch: branch,
            head: "0000000000000000000000000000000000000000",
            shortHead: "0000000",
            isMain: label == "main",
            label: label
        )
    }

    private static func worktreeDTO() -> ToolResultDTOs.ManageWorktreeReplyDTO.WorktreeDTO {
        .init(
            worktreeID: "wt_feature",
            specifier: "@id:wt_feature",
            path: "/tmp/repo-feature",
            gitDir: "/tmp/repo/.git/worktrees/repo-feature",
            name: "repo-feature",
            branch: "feature/demo",
            head: "abcdef0",
            isMain: false,
            isCurrent: true,
            isDetached: false,
            isLocked: false,
            lockReason: nil,
            isPrunable: false,
            prunableReason: nil,
            visual: .init(label: "demo", colorHex: "#2563EB", iconName: "circle.fill", markerStyle: "ring"),
            status: nil
        )
    }

    private static func bindingDTO(id: String, worktreeID: String) -> ToolResultDTOs.ManageWorktreeReplyDTO.BindingDTO {
        .init(
            id: id,
            repositoryID: "gitrepo_123",
            repoKey: "repo-123",
            logicalRootPath: "/tmp/repo",
            logicalRootName: "Repo",
            worktreeID: worktreeID,
            worktreeRootPath: "/tmp/repo-feature",
            worktreeName: "repo-feature",
            branch: "feature/demo",
            head: "abcdef0",
            visualLabel: "demo",
            visualColorHex: "#2563EB",
            boundAt: "2026-05-22T00:00:00Z",
            source: "manage_worktree.bind"
        )
    }

    private static func value(_ value: some Encodable) throws -> Value {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private static func onlyText(_ blocks: [MCP.Tool.Content]) throws -> String {
        let first = try XCTUnwrap(blocks.first)
        guard case let .text(text, _, _) = first else {
            XCTFail("Expected text content")
            return ""
        }
        return text
    }

    private struct AgentRunSnapshot: Encodable {
        let op: String
        let status: String
        let sessionID: String
        let session: Session
        let worktreeBindings: [WorktreeBinding]

        private enum CodingKeys: String, CodingKey {
            case op, status, session
            case sessionID = "session_id"
            case worktreeBindings = "worktree_bindings"
        }
    }

    private struct Session: Encodable {
        let name: String
    }

    private struct WorktreeBinding: Encodable {
        let worktreeID: String
        let worktreeRootPath: String
        let worktreeName: String
        let branch: String
        let logicalRootName: String
        let logicalRootPath: String
        let visualLabel: String
        let visualColorHex: String
        let unavailable: Bool

        private enum CodingKeys: String, CodingKey {
            case branch, unavailable
            case worktreeID = "worktree_id"
            case worktreeRootPath = "worktree_root_path"
            case worktreeName = "worktree_name"
            case logicalRootName = "logical_root_name"
            case logicalRootPath = "logical_root_path"
            case visualLabel = "visual_label"
            case visualColorHex = "visual_color_hex"
        }
    }
}
