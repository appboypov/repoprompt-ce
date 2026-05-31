import Foundation
@testable import RepoPrompt
import XCTest

@MainActor
final class AgentRunMCPToolServiceStartDefaultTests: XCTestCase {
    func testUntargetedStartWithoutModelIDResolvesThroughPairDefault() throws {
        let defaultLabel = AgentRunMCPToolService.defaultTaskLabelForStart(resolvedTabID: nil)
        XCTAssertEqual(defaultLabel, .pair)

        var requestedRole: AgentModelCatalog.TaskLabelKind?
        let resolved = try AgentMCPSelectionResolver.resolve(
            modelID: nil,
            defaultTaskLabel: defaultLabel,
            availability: .current,
            roleSelectionProvider: { role, _ in
                requestedRole = role
                return AgentModelCatalog.NormalizedAgentSelection(agent: .codexExec, modelRaw: "pair-default-model")
            }
        )

        XCTAssertEqual(requestedRole, .pair)
        XCTAssertEqual(resolved.taskLabelKind, .pair)
        XCTAssertEqual(resolved.agentRaw, AgentProviderKind.codexExec.rawValue)
        XCTAssertEqual(resolved.modelRaw, "pair-default-model")
    }

    func testExplicitTargetTabWithOmittedModelIDPreservesCurrentSelection() {
        let targetTabID = UUID()

        XCTAssertNil(AgentRunMCPToolService.defaultTaskLabelForStart(resolvedTabID: targetTabID))
    }

    func testWorkflowDefaultDoesNotOverridePairForUntargetedStart() {
        XCTAssertEqual(AgentWorkflow.oracleExport.defaultTaskLabelKind, .explore)

        let defaultLabel = AgentRunMCPToolService.defaultTaskLabelForStart(
            resolvedTabID: nil,
            workflow: AgentWorkflow.oracleExport.definition
        )

        XCTAssertEqual(defaultLabel, .pair)
    }

    func testExplicitModelIDTakesPrecedenceOverStartPairDefault() throws {
        let defaultLabel = AgentRunMCPToolService.defaultTaskLabelForStart(resolvedTabID: nil)

        let resolved = try AgentMCPSelectionResolver.resolve(
            modelID: "codexExec:explicit-model",
            defaultTaskLabel: defaultLabel,
            availability: AgentModelCatalog.AvailabilityContext(codexAvailable: true)
        )

        XCTAssertNil(resolved.taskLabelKind)
        XCTAssertEqual(resolved.agentRaw, AgentProviderKind.codexExec.rawValue)
        XCTAssertEqual(resolved.modelRaw, "explicit-model")
    }
}
