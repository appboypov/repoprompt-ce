@testable import RepoPrompt
import XCTest

final class ChatNameExtractorTests: XCTestCase {
    func testExtractsQuotedSelfClosingChatName() {
        var content = "<chatName=\"Implementation Plan\"/>\nBody"

        let name = ChatNameExtractor.extractAndRemove(from: &content)

        XCTAssertEqual(name, "Implementation Plan")
        XCTAssertEqual(content, "\nBody")
    }

    func testExtractsUnquotedNonSelfClosingChatName() {
        var content = "Intro\n<chatName=Plan>\nBody"

        let name = ChatNameExtractor.extractAndRemove(from: &content)

        XCTAssertEqual(name, "Plan")
        XCTAssertEqual(content, "Intro\n\nBody")
    }

    func testNonMatchReturnsNilAndLeavesContentUnchanged() {
        var content = "Intro\nNo chat name here.\nBody"
        let original = content

        let name = ChatNameExtractor.extractAndRemove(from: &content)

        XCTAssertNil(name)
        XCTAssertEqual(content, original)
    }

    func testEmptyQuotedNameReturnsNilAndLeavesContentUnchanged() {
        var content = "Intro\n<chatName=\"\"/>\nBody"
        let original = content

        let name = ChatNameExtractor.extractAndRemove(from: &content)

        XCTAssertNil(name)
        XCTAssertEqual(content, original)
    }

    func testMissingNameReturnsNilAndLeavesContentUnchanged() {
        var content = "Intro\n<chatName/>\nBody"
        let original = content

        let name = ChatNameExtractor.extractAndRemove(from: &content)

        XCTAssertNil(name)
        XCTAssertEqual(content, original)
    }

    func testPreservesSurroundingContentWhenRemovingSnippet() {
        var content = "Before <chatName = \"Review Notes\" /> after"

        let name = ChatNameExtractor.extractAndRemove(from: &content)

        XCTAssertEqual(name, "Review Notes")
        XCTAssertEqual(content, "Before  after")
    }
}
