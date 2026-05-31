@testable import RepoPrompt
import XCTest

final class MCPFileSearchDisplayPathTests: XCTestCase {
    func testCachedDisplayPathResolverPreservesRepeatedMatchesAndAllRootFallbackAliases() throws {
        let visibleRoot = try WorkspaceRootRef(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            name: "App",
            fullPath: "/tmp/RepoPromptDisplay/AppRoot"
        )
        let hiddenRoot = try WorkspaceRootRef(
            id: XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            name: "Lib",
            fullPath: "/tmp/RepoPromptDisplay/LibRoot"
        )
        let displayPath = MCPServerViewModel.makeCachedMCPDisplayPathResolver(
            visibleRoots: [visibleRoot],
            allRoots: [visibleRoot, hiddenRoot]
        )

        let repeatedVisiblePath = "/tmp/RepoPromptDisplay/AppRoot/Sources/App.swift"
        XCTAssertEqual(displayPath(repeatedVisiblePath), "Sources/App.swift")
        XCTAssertEqual(displayPath(repeatedVisiblePath), "Sources/App.swift")
        XCTAssertEqual(
            displayPath("/tmp/RepoPromptDisplay/LibRoot/Sources/Lib.swift"),
            "Lib/Sources/Lib.swift"
        )
    }
}
