import Foundation
@testable import RepoPrompt
import XCTest

final class CodeMapGoldenTests: XCTestCase {
    func testCEFixturesMatchGoldenCodeMapDescriptions() throws {
        try assertFixturesMatchGoldens(
            relativePaths: CodeMapFixtureRunner.fixtureRelativePaths,
            maximumCount: 5
        )
    }

    func testExpandedLanguageFixturesMatchGoldenCodeMapDescriptions() throws {
        try assertFixturesMatchGoldens(
            relativePaths: CodeMapFixtureRunner.expandedLanguageFixtureRelativePaths,
            maximumCount: 5
        )
    }

    func testCodeMapEdgeFixturesPreserveExportsTypesAndMethods() throws {
        try assertFixturesMatchGoldens(
            relativePaths: CodeMapFixtureRunner.edgeFixtureRelativePaths,
            maximumCount: 3
        )
    }

    func testSnapshotFileTreeMarksCodeMapFixtures() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let actual = CodeMapFixtureRunner.renderFixtureFileTree(tempRoot: tempRoot)
        let expected = try CodeMapFixtureRunner.expectedFileTree()
        XCTAssertEqual(actual, expected)
    }

    func testSnapshotFileTreeNoneModeProducesNoOutputOrLegend() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let actual = CodeMapFixtureRunner.renderFixtureFileTree(tempRoot: tempRoot, mode: "none")
        XCTAssertEqual(actual, "")
        XCTAssertFalse(actual.contains("denotes"))
        XCTAssertFalse(actual.contains("Config:"))
    }

    func testSnapshotFileTreeSelectedModeStillRendersSelectionAndLegend() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let selectedID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        let actual = CodeMapFixtureRunner.renderFixtureFileTree(
            tempRoot: tempRoot,
            mode: "selected",
            selectedFileIDs: [selectedID]
        )

        XCTAssertTrue(actual.contains("sample.swift * +"))
        XCTAssertTrue(actual.contains("(* denotes selected files)"))
        XCTAssertTrue(actual.contains("(+ denotes code-map available)"))
        XCTAssertFalse(actual.contains("worker.go"))
    }

    func testSnapshotFileTreeAutoModeStillRendersFixtureTree() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let actual = CodeMapFixtureRunner.renderFixtureFileTree(tempRoot: tempRoot, mode: "auto")
        let expected = try CodeMapFixtureRunner.expectedFileTree()
        XCTAssertEqual(actual, expected)
    }

    private func makeTempRoot() throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeMapGoldenTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        return tempRoot
    }

    private func assertFixturesMatchGoldens(relativePaths: [String], maximumCount: Int) throws {
        let fixtures = try CodeMapFixtureRunner.loadFixtures(relativePaths: relativePaths)
        XCTAssertEqual(fixtures.map(\.relativePath), relativePaths)
        XCTAssertEqual(fixtures.count, relativePaths.count)
        XCTAssertLessThanOrEqual(fixtures.count, maximumCount)

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeMapGoldenTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        for fixture in fixtures {
            try XCTContext.runActivity(named: fixture.relativePath) { _ in
                let actual = try CodeMapFixtureRunner.renderCodeMap(for: fixture, tempRoot: tempRoot)
                let expected = try CodeMapFixtureRunner.expectedCodeMap(for: fixture)
                XCTAssertEqual(actual, expected)
            }
        }
    }
}
