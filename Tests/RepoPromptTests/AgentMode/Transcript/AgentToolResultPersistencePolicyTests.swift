@testable import RepoPrompt
import XCTest

final class AgentToolResultPersistencePolicyTests: XCTestCase {
    func testConfirmedOracleSendToolNamesPersistBoundedStructuredSummaries() throws {
        for toolName in ["ask_oracle", "oracle_send"] {
            let rawResponse = String(repeating: "oracle raw response ", count: 40)
            let rawError = String(repeating: "raw oracle error ", count: 20)
            let rawDiff = "diff --git a/File.swift b/File.swift\n@@ -1 +1 @@\n-old\n+new"
            let raw = jsonString([
                "status": "success",
                "chat_id": "chat-123",
                "mode": "review",
                "response": rawResponse,
                "diffs": [["path": "File.swift", "diff": rawDiff]],
                "errors": [rawError]
            ])

            let summary = try XCTUnwrap(persistedSummary(toolName: toolName, rawResultJSON: raw))
            let object = try decodedObject(summary.resultJSON)

            XCTAssertEqual(object["status"] as? String, "success", toolName)
            XCTAssertEqual(object["summary_only"] as? Bool, true, toolName)
            XCTAssertEqual(object["chat_id"] as? String, "chat-123", toolName)
            XCTAssertEqual(object["mode"] as? String, "review", toolName)
            XCTAssertEqual(object["has_response"] as? Bool, true, toolName)
            XCTAssertEqual(object["diff_count"] as? Int, 1, toolName)
            XCTAssertEqual(object["error_count"] as? Int, 1, toolName)
            XCTAssertEqual(object["summary_text"] as? String, "review • 1 diff", toolName)
            XCTAssertNil(object["response"], toolName)
            XCTAssertNil(object["diffs"], toolName)
            XCTAssertNil(object["errors"], toolName)
            XCTAssertFalse(summary.resultJSON.contains(rawResponse), toolName)
            XCTAssertFalse(summary.resultJSON.contains(rawDiff), toolName)
            XCTAssertFalse(summary.resultJSON.contains(rawError), toolName)
            XCTAssertLessThanOrEqual(summary.resultJSON.utf8.count, AgentToolResultPersistencePolicy.maxPersistedToolSummaryBytes, toolName)
        }
    }

    func testOversizedStructuredSummaryFallsBackToMinimalResultJSON() throws {
        let oversizedReviewStatus = String(repeating: "approved-with-a-very-long-note-", count: 120)
        let raw = jsonString([
            "status": "success",
            "edits_requested": 1,
            "edits_applied": 1,
            "review_status": oversizedReviewStatus
        ])

        let summary = try XCTUnwrap(persistedSummary(toolName: "apply_edits", rawResultJSON: raw))
        let object = try decodedObject(summary.resultJSON)

        XCTAssertEqual(object["status"] as? String, "success")
        XCTAssertEqual(object["summary_only"] as? Bool, true)
        XCTAssertNil(object["review_status"])
        XCTAssertFalse(summary.resultJSON.contains(oversizedReviewStatus))
        XCTAssertLessThanOrEqual(summary.resultJSON.utf8.count, AgentToolResultPersistencePolicy.maxPersistedToolSummaryBytes)
    }

    func testAgentManagePersistsSmallDeleteAndSkipCounts() throws {
        let raw = jsonString([
            "status": "success",
            "deleted_sessions": ["a", "b", "c"],
            "skipped_sessions": ["d", "e"],
            "agent": ["id": "agent-1", "name": "Pair Programmer"],
            "sessions": [["name": "raw-session", "state": "closed"]]
        ])

        let summary = try XCTUnwrap(persistedSummary(toolName: "agent_manage", rawResultJSON: raw))
        let object = try decodedObject(summary.resultJSON)

        XCTAssertEqual(object["status"] as? String, "success")
        XCTAssertEqual(object["summary_only"] as? Bool, true)
        XCTAssertEqual(object["deleted_count"] as? Int, 3)
        XCTAssertEqual(object["skipped_count"] as? Int, 2)
        XCTAssertEqual(object["summary_text"] as? String, "3 deleted, 2 skipped")
        XCTAssertNil(object["deleted_sessions"])
        XCTAssertNil(object["skipped_sessions"])
        XCTAssertNil(object["agent"])
        XCTAssertNil(object["sessions"])
        XCTAssertLessThanOrEqual(summary.resultJSON.utf8.count, AgentToolResultPersistencePolicy.maxPersistedToolSummaryBytes)
    }

    func testLegacyChatSendNameDoesNotReceiveOracleStructuredPersistence() throws {
        let raw = jsonString([
            "status": "success",
            "chat_id": "legacy-chat",
            "mode": "review",
            "response": "legacy raw response",
            "diffs": [["path": "File.swift", "diff": "raw diff"]]
        ])

        let summary = try XCTUnwrap(persistedSummary(toolName: "chat_send", rawResultJSON: raw))
        let object = try decodedObject(summary.resultJSON)

        XCTAssertEqual(object["status"] as? String, "success")
        XCTAssertEqual(object["summary_only"] as? Bool, true)
        XCTAssertNil(object["chat_id"])
        XCTAssertNil(object["mode"])
        XCTAssertNil(object["has_response"])
        XCTAssertNil(object["diff_count"])
        XCTAssertNil(object["response"])
        XCTAssertFalse(summary.resultJSON.contains("legacy raw response"))
        XCTAssertFalse(summary.resultJSON.contains("raw diff"))
    }

    func testCursorACPStructuredSummaryKeepsPrecedenceForAllowedOracleTools() throws {
        let raw = jsonString([
            "status": "success",
            "acp_status": "completed",
            "kind": "message",
            "title": "Tool result",
            "chat_id": "chat-789",
            "mode": "review",
            "response": "raw oracle response",
            "content": [[
                "type": "text",
                "text": "cursor acp text payload"
            ]]
        ])

        let summary = try XCTUnwrap(persistedSummary(toolName: "ask_oracle", rawResultJSON: raw))
        let object = try decodedObject(summary.resultJSON)
        let content = try XCTUnwrap(object["content"] as? [[String: Any]])
        let firstContent = try XCTUnwrap(content.first)

        XCTAssertEqual(object["acp_status"] as? String, "completed")
        XCTAssertEqual(object["kind"] as? String, "message")
        XCTAssertEqual(firstContent["text_bytes"] as? Int, "cursor acp text payload".utf8.count)
        XCTAssertNil(object["chat_id"])
        XCTAssertNil(object["mode"])
        XCTAssertNil(object["has_response"])
        XCTAssertNil(object["response"])
        XCTAssertFalse(summary.resultJSON.contains("raw oracle response"))
        XCTAssertLessThanOrEqual(summary.resultJSON.utf8.count, AgentToolResultPersistencePolicy.maxPersistedToolSummaryBytes)
    }

    func testSummaryOnlyFalseOnlyForPromptExportStructuredMetadata() throws {
        let promptRaw = jsonString([
            "op": "export",
            "export": [
                "path": "/tmp/context.txt",
                "tokens": 42,
                "bytes": 2048
            ]
        ])
        let promptSummary = try XCTUnwrap(persistedSummary(toolName: "prompt", rawResultJSON: promptRaw))
        let promptObject = try decodedObject(promptSummary.resultJSON)

        XCTAssertFalse(promptSummary.summaryOnly)
        XCTAssertEqual(promptObject["op"] as? String, "export")
        XCTAssertNil(promptObject["summary_only"])

        let oracleRaw = jsonString([
            "status": "success",
            "chat_id": "chat-456",
            "mode": "plan",
            "response": "short response"
        ])
        let oracleSummary = try XCTUnwrap(persistedSummary(toolName: "ask_oracle", rawResultJSON: oracleRaw))
        let oracleObject = try decodedObject(oracleSummary.resultJSON)

        XCTAssertTrue(oracleSummary.summaryOnly)
        XCTAssertEqual(oracleObject["summary_only"] as? Bool, true)
        XCTAssertEqual(oracleObject["chat_id"] as? String, "chat-456")
        XCTAssertNil(oracleObject["response"])
    }

    private func persistedSummary(toolName: String, rawResultJSON: String) -> AgentPersistedToolResultSummary? {
        let invocationID = UUID()
        let item = AgentChatItem(
            kind: .toolResult,
            text: rawResultJSON,
            toolName: toolName,
            toolInvocationID: invocationID,
            toolResultJSON: rawResultJSON
        )
        let execution = AgentTranscriptToolExecution(
            stableExecutionID: invocationID.uuidString,
            toolName: toolName,
            invocationID: invocationID,
            argsJSON: nil,
            resultJSON: rawResultJSON,
            toolIsError: nil,
            status: .unknown
        )
        return AgentToolResultPersistencePolicy.persistedToolResultSummary(
            for: item,
            toolExecution: execution,
            rawResultTextFallback: rawResultJSON
        )
    }

    private func jsonString(_ object: [String: Any], file: StaticString = #filePath, line: UInt = #line) -> String {
        XCTAssertTrue(JSONSerialization.isValidJSONObject(object), file: file, line: line)
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private func decodedObject(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8), file: file, line: line)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any], file: file, line: line)
    }
}
