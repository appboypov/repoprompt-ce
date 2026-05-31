import MCP
@testable import RepoPrompt
import XCTest

@MainActor
final class ManageWorktreeToolServiceTests: XCTestCase {
    func testWorktreeManageCapabilityIsSeparateFromGitRead() {
        XCTAssertEqual(MCPWindowToolName.manageWorktree, "manage_worktree")
        XCTAssertTrue(MCPToolCapabilities.capabilities(for: MCPWindowToolName.manageWorktree).contains(.worktreeManage))
        XCTAssertFalse(MCPToolCapabilities.capabilities(for: MCPWindowToolName.manageWorktree).contains(.gitRead))
        XCTAssertTrue(MCPToolCapabilities.toolNames(for: [.worktreeManage]).contains(MCPWindowToolName.manageWorktree))
        XCTAssertTrue(DiscoverMCPToolPolicy.restrictedTools.contains(MCPWindowToolName.manageWorktree))
    }

    func testManageWorktreeUsesMigratedRoutingCompatibility() {
        XCTAssertFalse(ServerNetworkManager.shouldUseGenericTabBindingCompatibility(for: MCPWindowToolName.manageWorktree))
        XCTAssertFalse(ServerNetworkManager.shouldInjectLegacyTabIDForCompatibility(for: MCPWindowToolName.manageWorktree))
    }

    func testCatalogPlacesManageWorktreeImmediatelyAfterGit() {
        let ordered = MCPWindowToolGroup.orderedToolNames
        let gitIndex = ordered.firstIndex(of: MCPWindowToolName.git)
        let worktreeIndex = ordered.firstIndex(of: MCPWindowToolName.manageWorktree)
        XCTAssertNotNil(gitIndex)
        XCTAssertNotNil(worktreeIndex)
        XCTAssertEqual(worktreeIndex, gitIndex.map { $0 + 1 })
        XCTAssertFalse(ordered.contains("merge_worktree"))
        XCTAssertTrue(MCPToolCapabilities.capabilities(for: "merge_worktree").isEmpty)
    }

    func testManageWorktreeSchemaIncludesMergeOpsAndFields() async throws {
        let window = Self.makeWindowWithoutAutoStart()
        let tools = await window.mcpServer.windowMCPTools
        let manageWorktree = try XCTUnwrap(tools.first { $0.name == MCPWindowToolName.manageWorktree })
        let properties = try Self.schemaProperties(for: manageWorktree)
        let opEnum = properties["op"]?.objectValue?["enum"]?.arrayValue?.compactMap(\.stringValue) ?? []
        for op in ["preview", "apply", "status", "continue", "abort"] {
            XCTAssertTrue(opEnum.contains(op), "manage_worktree op enum should include merge op \(op)")
        }
        for field in ["operation_id", "target", "target_worktree_id", "confirm_preview", "confirm", "publish_artifacts", "context_lines", "detect_renames"] {
            XCTAssertNotNil(properties[field], "manage_worktree schema should advertise merge field \(field)")
        }
    }

    func testManageWorktreeReplyEncodesSnakeCaseVisualBindingFields() throws {
        let dto = ToolResultDTOs.ManageWorktreeReplyDTO(
            op: "bind",
            repository: .init(
                repositoryID: "gitrepo_123",
                repoKey: "repo-123",
                displayName: "Repo",
                rootPath: "/tmp/repo",
                commonGitDir: "/tmp/repo/.git",
                mainWorktreeRoot: "/tmp/repo"
            ),
            worktree: Self.worktreeDTO(),
            binding: Self.bindingDTO(id: "new", worktreeID: "wt_new"),
            previousBinding: Self.bindingDTO(id: "old", worktreeID: "wt_old")
        )

        let value = try Self.value(dto)
        let object = try XCTUnwrap(value.objectValue)
        XCTAssertNotNil(object["previous_binding"])
        XCTAssertNil(object["previousBinding"])

        let repository = try XCTUnwrap(object["repository"]?.objectValue)
        XCTAssertEqual(repository["repository_id"]?.stringValue, "gitrepo_123")
        XCTAssertEqual(repository["common_git_dir"]?.stringValue, "/tmp/repo/.git")
        XCTAssertEqual(repository["main_worktree_root"]?.stringValue, "/tmp/repo")

        let worktree = try XCTUnwrap(object["worktree"]?.objectValue)
        XCTAssertEqual(worktree["worktree_id"]?.stringValue, "wt_123")
        XCTAssertEqual(worktree["is_main"]?.boolValue, false)
        XCTAssertEqual(worktree["is_current"]?.boolValue, true)
        XCTAssertEqual(worktree["is_detached"]?.boolValue, false)
        let visual = try XCTUnwrap(worktree["visual"]?.objectValue)
        XCTAssertEqual(visual["color_hex"]?.stringValue, "#2563EB")
        XCTAssertEqual(visual["icon_name"]?.stringValue, "circle.fill")
        XCTAssertEqual(visual["marker_style"]?.stringValue, "ring")

        let previous = try XCTUnwrap(object["previous_binding"]?.objectValue)
        XCTAssertEqual(previous["worktree_id"]?.stringValue, "wt_old")
        XCTAssertEqual(previous["logical_root_path"]?.stringValue, "/tmp/repo")
        XCTAssertEqual(previous["visual_color_hex"]?.stringValue, "#7C3AED")
    }

    func testManageWorktreeMergeReplyNestsMergeBlock() throws {
        let dto = ToolResultDTOs.ManageWorktreeReplyDTO(
            op: "preview",
            merge: .init(
                status: "preview",
                operationID: "merge_123",
                sessionID: "session_123",
                source: Self.mergeEndpointDTO(label: "feature", path: "/tmp/source", branch: "feature"),
                target: Self.mergeEndpointDTO(label: "main", path: "/tmp/target", branch: "main"),
                visualization: .init(
                    requested: true,
                    limit: 2,
                    text: "target\nsource",
                    lines: ["target", "source"],
                    sourceWorktreeID: "wt_feature",
                    targetWorktreeID: "wt_main",
                    source: "manage_worktree.preview"
                ),
                nextActions: ["Apply after approval: manage_worktree {\"op\":\"apply\"}"]
            )
        )

        let object = try XCTUnwrap(Self.value(dto).objectValue)
        XCTAssertEqual(object["op"]?.stringValue, "preview")
        XCTAssertNil(object["operation_id"])
        let merge = try XCTUnwrap(object["merge"]?.objectValue)
        XCTAssertEqual(merge["operation_id"]?.stringValue, "merge_123")
        XCTAssertEqual(merge["visualization"]?.objectValue?["source"]?.stringValue, "manage_worktree.preview")
        XCTAssertEqual(merge["next_actions"]?.arrayValue?.first?.stringValue, "Apply after approval: manage_worktree {\"op\":\"apply\"}")
    }

    func testFormatterShowsListVisualIdentityAndBoundedGraph() throws {
        let dto = ToolResultDTOs.ManageWorktreeReplyDTO(
            op: "list",
            repository: .init(
                repositoryID: "gitrepo_123",
                repoKey: "repo-123",
                displayName: "Repo",
                rootPath: "/tmp/repo",
                commonGitDir: "/tmp/repo/.git",
                mainWorktreeRoot: "/tmp/repo"
            ),
            worktrees: [Self.worktreeDTO()],
            graph: .init(
                requested: true,
                limit: 12,
                lines: ["* abc1234 (HEAD -> feature/demo) Demo commit", "* def5678 Base commit"],
                source: "git log --graph --decorate --oneline --color=never -n 12"
            )
        )
        let blocks = try ToolOutputFormatter.formatManageWorktree(args: [:], value: Self.value(dto))
        let text = try Self.onlyText(blocks)

        XCTAssertTrue(text.contains("## Manage Worktree List"))
        XCTAssertTrue(text.contains("Repo (`repo-123`)"))
        XCTAssertTrue(text.contains("`wt_123`"))
        XCTAssertTrue(text.contains("feature/demo"))
        XCTAssertTrue(text.contains("#2563EB"))
        XCTAssertTrue(text.contains("### Commit / Worktree Graph"))
        XCTAssertTrue(text.contains("bounded to 12 lines"))
        XCTAssertTrue(text.contains("* abc1234 (HEAD -> feature/demo) Demo commit"))
        XCTAssertFalse(text.contains("placeholder"))
    }

    func testFormatterShowsPreviousBindingOnReplace() throws {
        let dto = ToolResultDTOs.ManageWorktreeReplyDTO(
            op: "bind",
            worktree: Self.worktreeDTO(),
            binding: Self.bindingDTO(id: "new", worktreeID: "wt_new"),
            previousBinding: Self.bindingDTO(id: "old", worktreeID: "wt_old")
        )
        let text = try Self.onlyText(ToolOutputFormatter.formatManageWorktree(args: [:], value: Self.value(dto)))
        XCTAssertTrue(text.contains("### Binding"))
        XCTAssertTrue(text.contains("wt_new"))
        XCTAssertTrue(text.contains("### Previous Binding"))
        XCTAssertTrue(text.contains("wt_old"))
        XCTAssertTrue(text.contains("circle.fill"))
        XCTAssertTrue(text.contains("ring"))
    }

    private static func worktreeDTO() -> ToolResultDTOs.ManageWorktreeReplyDTO.WorktreeDTO {
        .init(
            worktreeID: "wt_123",
            specifier: "@id:wt_123",
            path: "/tmp/repo-wt",
            gitDir: "/tmp/repo/.git/worktrees/repo-wt",
            name: "repo-wt",
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
            status: .init(staged: 1, modified: 2, untracked: 3, isDirty: true)
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

    private static func bindingDTO(id: String, worktreeID: String) -> ToolResultDTOs.ManageWorktreeReplyDTO.BindingDTO {
        .init(
            id: id,
            repositoryID: "gitrepo_123",
            repoKey: "repo-123",
            logicalRootPath: "/tmp/repo",
            logicalRootName: "Repo",
            worktreeID: worktreeID,
            worktreeRootPath: "/tmp/repo-wt",
            worktreeName: "repo-wt",
            branch: "feature/demo",
            head: "abcdef0",
            visualLabel: "demo",
            visualColorHex: "#7C3AED",
            boundAt: "2026-05-22T00:00:00Z",
            source: "manage_worktree.bind"
        )
    }

    private static func makeWindowWithoutAutoStart() -> WindowState {
        let previousAutoStart = GlobalSettingsStore.shared.mcpAutoStart()
        GlobalSettingsStore.shared.setMCPAutoStart(false, commit: false)
        let window = WindowState()
        GlobalSettingsStore.shared.setMCPAutoStart(previousAutoStart, commit: false)
        return window
    }

    private static func schemaProperties(for tool: RepoPrompt.Tool) throws -> [String: Value] {
        let schema = try XCTUnwrap(Value(tool.inputSchema).objectValue)
        return try XCTUnwrap(schema["properties"]?.objectValue)
    }

    private static func value(_ dto: some Encodable) throws -> Value {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(dto)
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
}
