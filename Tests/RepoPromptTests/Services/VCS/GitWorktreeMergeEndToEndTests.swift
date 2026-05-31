@testable import RepoPrompt
import XCTest

final class GitWorktreeMergeEndToEndTests: XCTestCase {
    func testPreviewDirtySourceCleanApplyAndStalePreviewWithRealWorktrees() async throws {
        let clean = try Fixture(prefix: "CleanApply")
        defer { clean.cleanup() }
        try clean.commitFile("Source.txt", contents: "source\n", message: "Source change", cwd: clean.source)

        let preview = try await clean.preview(publishArtifacts: true)
        XCTAssertFalse(preview.operationID.isEmpty)
        XCTAssertTrue(preview.inspection.blockers.isEmpty, preview.inspection.blockers.map(\.message).joined(separator: "\n"))
        XCTAssertTrue(preview.inspection.visualization.contains("merge preview"), preview.inspection.visualization)
        let artifacts = try XCTUnwrap(preview.artifacts)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.mapPath), artifacts.mapPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.sidecarPath), artifacts.sidecarPath)

        let completed = try await VCSService().applyGitWorktreeMerge(.init(preview: preview))
        XCTAssertEqual(completed.status, .completed)
        XCTAssertNotNil(completed.mergeCommit)
        XCTAssertEqual(try clean.readFile("Source.txt", cwd: clean.repo), "source\n")
        XCTAssertEqual(try clean.parentCount(ref: "HEAD", cwd: clean.repo), 3)

        let dirty = try Fixture(prefix: "DirtySource")
        defer { dirty.cleanup() }
        try "dirty\n".write(to: dirty.source.appendingPathComponent("Dirty.txt"), atomically: true, encoding: .utf8)
        let dirtyPreview = try await dirty.preview(publishArtifacts: false)
        XCTAssertTrue(dirtyPreview.inspection.isBlocked)
        XCTAssertTrue(dirtyPreview.inspection.blockers.contains { $0.code == .sourceDirty })

        let stale = try Fixture(prefix: "StalePreview")
        defer { stale.cleanup() }
        try stale.commitFile("Source.txt", contents: "source\n", message: "Source change", cwd: stale.source)
        let stalePreview = try await stale.preview(publishArtifacts: false)
        try stale.commitFile("Target.txt", contents: "target\n", message: "Target change", cwd: stale.repo)
        let targetHeadAfterIntentionalChange = try stale.gitOutput(["rev-parse", "HEAD"], cwd: stale.repo).trimmingCharacters(in: .whitespacesAndNewlines)
        let targetTreeAfterIntentionalChange = try stale.gitOutput(["rev-parse", "HEAD^{tree}"], cwd: stale.repo).trimmingCharacters(in: .whitespacesAndNewlines)
        let statusAfterIntentionalChange = try stale.gitOutput(["status", "--porcelain"], cwd: stale.repo)

        let staleResult = try await VCSService().applyGitWorktreeMerge(.init(preview: stalePreview))
        XCTAssertEqual(staleResult.status, .stale)
        XCTAssertEqual(staleResult.staleReason, "Target worktree changed since preview.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.repo.appendingPathComponent("Source.txt").path))
        XCTAssertEqual(try stale.gitOutput(["rev-parse", "HEAD"], cwd: stale.repo).trimmingCharacters(in: .whitespacesAndNewlines), targetHeadAfterIntentionalChange)
        XCTAssertEqual(try stale.gitOutput(["rev-parse", "HEAD^{tree}"], cwd: stale.repo).trimmingCharacters(in: .whitespacesAndNewlines), targetTreeAfterIntentionalChange)
        XCTAssertEqual(try stale.gitOutput(["status", "--porcelain"], cwd: stale.repo), statusAfterIntentionalChange)
    }

    func testConflictApplyReconcileAbortAndManualContinueWithRealWorktrees() async throws {
        let abortFixture = try Fixture(prefix: "ConflictAbort")
        defer { abortFixture.cleanup() }
        try abortFixture.commitFile("Common.txt", contents: "target\n", message: "Target edit", cwd: abortFixture.repo)
        try abortFixture.commitFile("Common.txt", contents: "source\n", message: "Source edit", cwd: abortFixture.source)

        let abortPreview = try await abortFixture.preview(publishArtifacts: false)
        let reloadedApplyingOperation = AgentWorktreeMergeCoordinator.makeOperation(preview: abortPreview, status: .applying)
        let conflict = try await VCSService().applyGitWorktreeMerge(.init(preview: abortPreview))

        XCTAssertEqual(conflict.status, .conflicted)
        XCTAssertEqual(conflict.conflictFiles, ["Common.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: abortFixture.repo.appendingPathComponent(".git/MERGE_HEAD").path))

        let reconciled = await AgentSessionWorktreeMergeReconciler.reconcile(
            reloadedApplyingOperation,
            hooks: .live(vcsService: VCSService())
        )
        XCTAssertEqual(reconciled.status, .conflicted)
        XCTAssertEqual(reconciled.conflictFiles, ["Common.txt"])

        let abortResult = try await VCSService().abortGitWorktreeMerge(.init(target: abortPreview.inspection.target))
        XCTAssertTrue(abortResult.aborted)
        XCTAssertEqual(try abortFixture.readFile("Common.txt", cwd: abortFixture.repo), "target\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: abortFixture.repo.appendingPathComponent(".git/MERGE_HEAD").path))

        let continueFixture = try Fixture(prefix: "ConflictContinue")
        defer { continueFixture.cleanup() }
        try continueFixture.commitFile("Common.txt", contents: "target\n", message: "Target edit", cwd: continueFixture.repo)
        try continueFixture.commitFile("Common.txt", contents: "source\n", message: "Source edit", cwd: continueFixture.source)

        let continuePreview = try await continueFixture.preview(publishArtifacts: false)
        let continueConflict = try await VCSService().applyGitWorktreeMerge(.init(preview: continuePreview))
        XCTAssertEqual(continueConflict.status, .conflicted)

        try "resolved\n".write(to: continueFixture.repo.appendingPathComponent("Common.txt"), atomically: true, encoding: .utf8)
        try continueFixture.runGit(["add", "Common.txt"], cwd: continueFixture.repo)
        let continued = try await VCSService().continueGitWorktreeMerge(.init(
            source: continuePreview.inspection.source,
            target: continuePreview.inspection.target,
            sourceHead: continuePreview.inspection.sourceHead,
            targetHeadBefore: continuePreview.inspection.targetHead,
            commitMessage: "Resolve worktree merge"
        ))

        XCTAssertEqual(continued.status, .completed)
        XCTAssertNotNil(continued.mergeCommit)
        XCTAssertEqual(try continueFixture.readFile("Common.txt", cwd: continueFixture.repo), "resolved\n")
        XCTAssertEqual(try continueFixture.parentCount(ref: "HEAD", cwd: continueFixture.repo), 3)
    }
}

private struct Fixture {
    let sandbox: URL
    let repo: URL
    let source: URL
    let workspace: URL

    init(prefix: String) throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitWorktreeMergeEndToEndTests-\(prefix)-\(suffix)", isDirectory: true)
        repo = sandbox.appendingPathComponent("repo", isDirectory: true).standardizedFileURL
        source = sandbox.appendingPathComponent("source", isDirectory: true).standardizedFileURL
        workspace = sandbox.appendingPathComponent("workspace", isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Self.runGit(["init"], cwd: repo)
        try Self.runGit(["config", "user.name", "RepoPrompt Test"], cwd: repo)
        try Self.runGit(["config", "user.email", "repoprompt@example.test"], cwd: repo)
        try Self.runGit(["config", "commit.gpgSign", "false"], cwd: repo)
        try Self.runGit(["checkout", "-b", "main"], cwd: repo)
        try "base\n".write(to: repo.appendingPathComponent("Common.txt"), atomically: true, encoding: .utf8)
        try Self.runGit(["add", "Common.txt"], cwd: repo)
        try Self.runGit(["commit", "-m", "Initial commit"], cwd: repo)
        try Self.runGit(["worktree", "add", "-b", "feature/source", source.path, "HEAD"], cwd: repo)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: sandbox)
    }

    func preview(publishArtifacts: Bool) async throws -> GitWorktreeMergePreview {
        let git = GitService()
        let sourceEndpoint = try await endpoint(for: source, using: git)
        let targetEndpoint = try await endpoint(for: repo, using: git)
        return try await VCSService().previewGitWorktreeMerge(.init(
            source: sourceEndpoint,
            target: targetEndpoint,
            workspaceDirectory: workspace,
            publishArtifacts: publishArtifacts
        ))
    }

    func endpoint(for path: URL, using git: GitService) async throws -> GitWorktreeMergeEndpoint {
        let worktrees = try await git.listWorktrees(at: repo)
        let standardized = path.standardizedFileURL.path
        let descriptor = try XCTUnwrap(worktrees.first { $0.path == standardized })
        return try GitWorktreeMergeEndpoint(descriptor: descriptor)
    }

    func commitFile(_ relativePath: String, contents: String, message: String, cwd: URL) throws {
        let url = cwd.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try runGit(["add", relativePath], cwd: cwd)
        try runGit(["commit", "-m", message], cwd: cwd)
    }

    func readFile(_ relativePath: String, cwd: URL) throws -> String {
        try String(contentsOf: cwd.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func parentCount(ref: String, cwd: URL) throws -> Int {
        try gitOutput(["rev-list", "--parents", "-n", "1", ref], cwd: cwd)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .count
    }

    func runGit(_ arguments: [String], cwd: URL) throws {
        try Self.runGit(arguments, cwd: cwd)
    }

    func gitOutput(_ arguments: [String], cwd: URL) throws -> String {
        try Self.gitOutput(arguments, cwd: cwd)
    }

    private static func runGit(_ arguments: [String], cwd: URL) throws {
        _ = try gitOutput(arguments, cwd: cwd)
    }

    private static func gitOutput(_ arguments: [String], cwd: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "GitWorktreeMergeEndToEndTests.git",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed: \(text)"]
            )
        }
        return text
    }
}
