@testable import RepoPrompt
import XCTest

final class PromptContextResolvedFileTreeTests: XCTestCase {
    func testNoneModeDoesNotRenderFileTreeEvenWhenIncluded() {
        let context = makeContext(includeFileTree: true, fileTreeMode: .none)

        XCTAssertFalse(context.rendersFileTree)
        XCTAssertEqual(context.effectiveFileTreeMode, .none)
    }

    func testDisabledFileTreeForcesEffectiveNoneMode() {
        let context = makeContext(includeFileTree: false, fileTreeMode: .selected)

        XCTAssertFalse(context.rendersFileTree)
        XCTAssertEqual(context.effectiveFileTreeMode, .none)
    }

    func testSelectedAndAutoModesRenderWhenIncluded() {
        let selected = makeContext(includeFileTree: true, fileTreeMode: .selected)
        let auto = makeContext(includeFileTree: true, fileTreeMode: .auto)

        XCTAssertTrue(selected.rendersFileTree)
        XCTAssertEqual(selected.effectiveFileTreeMode, .selected)
        XCTAssertTrue(auto.rendersFileTree)
        XCTAssertEqual(auto.effectiveFileTreeMode, .auto)
    }

    private func makeContext(
        includeFileTree: Bool,
        fileTreeMode: FileTreeOption
    ) -> PromptContextResolved {
        PromptContextResolved(
            includeFiles: true,
            includeUserPrompt: true,
            includeMetaPrompts: true,
            includeFileTree: includeFileTree,
            fileTreeMode: fileTreeMode,
            codeMapUsage: .auto,
            gitInclusion: .none,
            storedPromptIds: nil
        )
    }
}
