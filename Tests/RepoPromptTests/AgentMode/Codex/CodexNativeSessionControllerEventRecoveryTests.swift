import Foundation
@testable import RepoPrompt
import XCTest

final class CodexNativeSessionControllerEventRecoveryTests: XCTestCase {
    func testNormalizedCommandExecutionLifecycleParsesAsBashCallAndResult() throws {
        let controller = CodexNativeSessionController(
            client: CodexAppServerClient(),
            runID: UUID(),
            tabID: UUID(),
            windowID: 1,
            workspacePath: nil
        )

        let started = try XCTUnwrap(controller.test_parseToolLifecycleEvent(
            method: "item/started",
            params: [
                "threadId": "thread-active",
                "turnId": "turn-current",
                "item": [
                    "type": "commandExecution",
                    "id": "call_exec_1",
                    "command": "echo hi",
                    "cwd": "/tmp/work",
                    "processId": "47551",
                    "commandActions": [["type": "unknown", "command": "echo hi"]]
                ]
            ]
        ))

        XCTAssertEqual(started.kind, "call")
        XCTAssertEqual(started.name, "bash")
        XCTAssertNotNil(started.invocationID)
        let argsObject = try XCTUnwrap(jsonObject(from: started.argsJSON))
        XCTAssertEqual(argsObject["command"] as? String, "echo hi")
        XCTAssertEqual(argsObject["cwd"] as? String, "/tmp/work")
        XCTAssertEqual(argsObject["processId"] as? String, "47551")
        XCTAssertEqual((argsObject["commandActions"] as? [[String: Any]])?.count, 1)

        let completed = try XCTUnwrap(controller.test_parseToolLifecycleEvent(
            method: "item/completed",
            params: [
                "threadId": "thread-active",
                "turnId": "turn-current",
                "item": [
                    "type": "commandExecution",
                    "id": "call_exec_1",
                    "command": "echo hi",
                    "processId": "47551",
                    "status": "completed",
                    "exitCode": 0,
                    "aggregatedOutput": "hi\n"
                ]
            ]
        ))

        XCTAssertEqual(completed.kind, "result")
        XCTAssertEqual(completed.name, "bash")
        XCTAssertEqual(completed.invocationID, started.invocationID)
        XCTAssertEqual(completed.isError, false)
        let resultObject = try XCTUnwrap(jsonObject(from: completed.resultJSON))
        XCTAssertEqual(resultObject["type"] as? String, "commandExecution")
        XCTAssertEqual(resultObject["status"] as? String, "completed")
        XCTAssertEqual(resultObject["processId"] as? String, "47551")
        XCTAssertEqual(resultObject["aggregatedOutput"] as? String, "hi\n")
        XCTAssertEqual(resultObject["exitCode"] as? Int, 0)
    }

    private func jsonObject(from raw: String?) -> [String: Any]? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
