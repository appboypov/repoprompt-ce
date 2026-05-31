@testable import RepoPrompt
import XCTest

final class FileSystemServiceEventPathMappingTests: XCTestCase {
    private var temporaryRoots = FileSystemTemporaryRoots()

    override func tearDownWithError() throws {
        temporaryRoots.removeAll()
        try super.tearDownWithError()
    }

    func testSafeInRootEventPathMapsRelative() async throws {
        let root = try temporaryRoots.makeRoot(suiteName: "FileSystemServiceEventPathMapping")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        let service = try await makeService(root: root)

        let result = await service.mapRelativeEventPathForTesting(root.appendingPathComponent("src/file.txt").path)

        XCTAssertTrue(result.isInside)
        XCTAssertEqual(result.value, "src/file.txt")
    }

    func testOutOfRootEventPathIsRejected() async throws {
        let parent = try temporaryRoots.makeRoot(suiteName: "FileSystemServiceEventPathMapping")
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let outside = parent.appendingPathComponent("outside/file.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = try await makeService(root: root)

        let result = await service.mapRelativeEventPathForTesting(outside.path)

        XCTAssertFalse(result.isInside)
        XCTAssertEqual(result.value, outside.path)
    }

    func testSymlinkCanonicalFallbackMapsUnsafeCanonicalPathInsideRoot() async throws {
        let parent = try temporaryRoots.makeRoot(suiteName: "FileSystemServiceEventPathMapping")
        let realRoot = parent.appendingPathComponent("real-root", isDirectory: true)
        let symlinkRoot = parent.appendingPathComponent("link-root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: realRoot.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: symlinkRoot, withDestinationURL: realRoot)
        let service = try await makeService(root: symlinkRoot)

        let unsafeCanonicalPath = symlinkRoot
            .appendingPathComponent("../real-root/src/file.txt")
            .path
        let result = await service.mapRelativeEventPathForTesting(unsafeCanonicalPath)

        XCTAssertTrue(result.isInside)
        XCTAssertEqual(result.value, "src/file.txt")
    }

    func testRootBoundaryFalsePositiveIsRejected() async throws {
        let parent = try temporaryRoots.makeRoot(suiteName: "FileSystemServiceEventPathMapping")
        let root = parent.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = try await makeService(root: root)
        let falsePositivePath = root.path + "-suffix/file.txt"

        let result = await service.mapRelativeEventPathForTesting(falsePositivePath)

        XCTAssertFalse(result.isInside)
        XCTAssertEqual(result.value, falsePositivePath)
    }

    func testEmptyEventPathIsRejected() async throws {
        let root = try temporaryRoots.makeRoot(suiteName: "FileSystemServiceEventPathMapping")
        let service = try await makeService(root: root)

        let result = await service.mapRelativeEventPathForTesting("")

        XCTAssertFalse(result.isInside)
        XCTAssertEqual(result.value, "")
    }

    func testUnsafeEventPathFallsBackToStandardization() async throws {
        let root = try temporaryRoots.makeRoot(suiteName: "FileSystemServiceEventPathMapping")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        let service = try await makeService(root: root)

        let result = await service.mapRelativeEventPathForTesting(root.path + "//src/./file.txt")

        XCTAssertTrue(result.isInside)
        XCTAssertEqual(result.value, "src/file.txt")
    }

    private func makeService(root: URL) async throws -> FileSystemService {
        try await FileSystemService(
            path: root.path,
            respectGitignore: false,
            respectRepoIgnore: false,
            respectCursorignore: false,
            skipSymlinks: true
        )
    }
}
