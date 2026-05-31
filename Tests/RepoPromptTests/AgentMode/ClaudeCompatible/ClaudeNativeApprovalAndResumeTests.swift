import Foundation
@testable import RepoPrompt
import XCTest

final class ClaudeNativeApprovalAndResumeTests: XCTestCase {
    func testRepoPromptPermissionAutoApprovalAndAllowPayloadPreserveToolUseID() throws {
        let repoPromptPayload: [String: Any] = [
            "tool_name": "mcp__RepoPromptCE__read_file",
            "tool_use_id": "toolu_read_1",
            "input": ["path": "Sources/App.swift"],
            "permission_suggestions": [["type": "tool", "name": "mcp__RepoPromptCE__read_file"]]
        ]

        let match = try XCTUnwrap(ClaudeNativeProcessSessionController.repoPromptPermissionAutoApprovalMatch(
            toolName: "mcp__RepoPromptCE__read_file",
            requestPayload: repoPromptPayload
        ))
        XCTAssertEqual(match.source, .topLevelToolName)
        XCTAssertEqual(match.normalizedToolName, "read_file")

        let allowOnce = ClaudeNativeProcessSessionController.allowPermissionResponsePayload(
            pendingRequest: repoPromptPayload,
            includeUpdatedPermissions: false
        )
        XCTAssertEqual(allowOnce["behavior"] as? String, "allow")
        XCTAssertEqual(allowOnce["toolUseID"] as? String, "toolu_read_1")
        XCTAssertNil(allowOnce["updatedPermissions"])
        XCTAssertEqual((allowOnce["updatedInput"] as? [String: Any])?["path"] as? String, "Sources/App.swift")

        let allowForSession = ClaudeNativeProcessSessionController.allowPermissionResponsePayload(
            pendingRequest: repoPromptPayload,
            includeUpdatedPermissions: true
        )
        XCTAssertEqual((allowForSession["updatedPermissions"] as? [[String: Any]])?.first?["name"] as? String, "mcp__RepoPromptCE__read_file")

        let nestedMatch = try XCTUnwrap(ClaudeNativeProcessSessionController.repoPromptPermissionAutoApprovalMatch(
            toolName: "Bash",
            requestPayload: [
                "permission_suggestions": [["rules": [["toolName": "mcp__RepoPromptCE__read_file"]]]]
            ]
        ))
        XCTAssertEqual(nestedMatch.source, .nestedToolName)
        XCTAssertEqual(nestedMatch.normalizedToolName, "read_file")

        XCTAssertNil(ClaudeNativeProcessSessionController.repoPromptPermissionAutoApprovalMatch(
            toolName: "Bash",
            requestPayload: ["input": ["command": "rm -rf /tmp/example"]]
        ))
    }
}
