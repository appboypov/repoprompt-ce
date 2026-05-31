@testable import RepoPrompt
import XCTest

final class AIQueriesServiceCodexPolicyTests: XCTestCase {
    func testOracleCodexRequestStartsNewThreadsEphemerally() {
        XCTAssertTrue(
            AIQueriesService.shouldStartNewCodexThreadsEphemerally(
                for: .codexCliGpt5Medium,
                queryOrigin: .oracle
            )
        )
    }

    func testOrdinaryCodexChatRemainsPersistentByDefault() {
        XCTAssertFalse(
            AIQueriesService.shouldStartNewCodexThreadsEphemerally(
                for: .codexCliGpt5Medium,
                queryOrigin: .standardChat
            )
        )
    }

    func testOracleNonCodexRequestDoesNotApplyCodexThreadPolicy() {
        XCTAssertFalse(
            AIQueriesService.shouldStartNewCodexThreadsEphemerally(
                for: .claude4Sonnet,
                queryOrigin: .oracle
            )
        )
    }
}
