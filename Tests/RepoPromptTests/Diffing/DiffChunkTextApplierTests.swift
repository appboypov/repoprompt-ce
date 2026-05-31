@testable import RepoPrompt
import XCTest

final class DiffChunkTextApplierTests: XCTestCase {
    func testAdjustsLaterStartLineAfterInsertion() throws {
        let original = "a\nb\nc\nd"
        let chunks = [
            DiffChunk(
                lines: [DiffLine(content: "+inserted")],
                startLine: 2
            ),
            DiffChunk(
                lines: [
                    DiffLine(content: "-d"),
                    DiffLine(content: "+D")
                ],
                startLine: 3
            )
        ]

        let result = try DiffChunkTextApplier.apply(chunks: chunks, to: original)

        XCTAssertEqual(result, "a\nb\ninserted\nc\nD")
    }

    func testAdjustsLaterStartLineAfterDeletion() throws {
        let original = "a\nb\nc\nd"
        let chunks = [
            DiffChunk(
                lines: [DiffLine(content: "-b")],
                startLine: 1
            ),
            DiffChunk(
                lines: [
                    DiffLine(content: "-d"),
                    DiffLine(content: "+D")
                ],
                startLine: 3
            )
        ]

        let result = try DiffChunkTextApplier.apply(chunks: chunks, to: original)

        XCTAssertEqual(result, "a\nc\nD")
    }

    func testPreservesOriginalLineEnding() throws {
        let original = "one\r\ntwo\r\nthree"
        let chunks = [
            DiffChunk(
                lines: [
                    DiffLine(content: "-two"),
                    DiffLine(content: "+TWO")
                ],
                startLine: 1
            )
        ]

        let result = try DiffChunkTextApplier.apply(chunks: chunks, to: original)

        XCTAssertEqual(result, "one\r\nTWO\r\nthree")
        XCTAssertFalse(result.contains("one\nTWO"))
    }

    func testPreservesOriginalTrailingNewline() throws {
        let original = "one\ntwo\n"
        let chunks = [
            DiffChunk(
                lines: [
                    DiffLine(content: "-two"),
                    DiffLine(content: "+TWO")
                ],
                startLine: 1
            )
        ]

        let result = try DiffChunkTextApplier.apply(chunks: chunks, to: original)

        XCTAssertEqual(result, "one\nTWO\n")
    }

    func testReturnsOriginalTextForEmptyChunkInput() throws {
        let original = "one\r\ntwo\r\n"

        let result = try DiffChunkTextApplier.apply(chunks: [], to: original)

        XCTAssertEqual(result, original)
    }

    func testAppliesChunksInInputOrder() throws {
        let original = "a\nb"
        let chunks = [
            DiffChunk(
                lines: [DiffLine(content: "+first")],
                startLine: 1
            ),
            DiffChunk(
                lines: [DiffLine(content: "+second")],
                startLine: 1
            )
        ]

        let result = try DiffChunkTextApplier.apply(chunks: chunks, to: original)

        XCTAssertEqual(result, "a\nsecond\nfirst\nb")
    }

    func testAppliesDecodedIndentation() throws {
        let original = "func f() {\n}"
        let chunks = [
            DiffChunk(
                lines: [DiffLine(content: "+<s4>let value = 1")],
                startLine: 1
            )
        ]

        let result = try DiffChunkTextApplier.apply(chunks: chunks, to: original)

        XCTAssertEqual(result, "func f() {\n    let value = 1\n}")
    }
}
