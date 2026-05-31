@testable import RepoPrompt
import XCTest

final class CodexNativeSessionControllerInterruptTests: XCTestCase {
    func testActiveTurnMismatchParserExtractsFoundTurnID() {
        let description = "turn/interrupt failed: expected active turn id `turn-old` but found `turn-new`"

        XCTAssertEqual(
            CodexNativeSessionController.activeTurnMismatchActualTurnID(fromErrorDescription: description),
            "turn-new"
        )
    }

    func testActiveTurnMismatchParserRejectsUnrelatedAndMalformedErrors() {
        XCTAssertNil(CodexNativeSessionController.activeTurnMismatchActualTurnID(fromErrorDescription: "network failed"))
        XCTAssertNil(CodexNativeSessionController.activeTurnMismatchActualTurnID(fromErrorDescription: "expected active turn id `old` but found ``"))
        XCTAssertNil(CodexNativeSessionController.activeTurnMismatchActualTurnID(fromErrorDescription: "expected active turn id `old` but found turn-new"))
    }

    func testResolvedInterruptTurnIDDoesNotUseCachedTurnAfterSuccessfulNoActiveRefresh() {
        XCTAssertNil(
            CodexNativeSessionController.resolvedInterruptTurnID(
                cachedTurnID: "stale-turn",
                refreshResult: .refreshed(nil)
            )
        )
        XCTAssertNil(
            CodexNativeSessionController.resolvedInterruptTurnID(
                cachedTurnID: "stale-turn",
                refreshResult: .refreshed(" \t\n")
            )
        )
    }

    func testResolvedInterruptTurnIDFallsBackToCachedTurnOnlyWhenRefreshFails() {
        XCTAssertEqual(
            CodexNativeSessionController.resolvedInterruptTurnID(
                cachedTurnID: "stale-turn",
                refreshResult: .failed
            ),
            "stale-turn"
        )
        XCTAssertEqual(
            CodexNativeSessionController.resolvedInterruptTurnID(
                cachedTurnID: "stale-turn",
                refreshResult: .refreshed("fresh-turn")
            ),
            "fresh-turn"
        )
    }
}
