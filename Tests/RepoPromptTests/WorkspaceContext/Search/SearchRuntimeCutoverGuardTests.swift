import XCTest

final class SearchRuntimeCutoverGuardTests: XCTestCase {
    func testDeletedTreeSearchVMAndWindowStateRuntimeSearchCutover() throws {
        let root = try RepoRoot.url()
        let oldTypeName = "SearchFile" + "TreeViewModel"
        let oldPropertyName = "search" + "ViewModel"
        let deletedPath = root.appendingPathComponent("Sources/RepoPrompt/Features/Search/ViewModels/" + oldTypeName + ".swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedPath.path), "Old tree search VM should remain deleted; runtime search must use WorkspaceSearchService/store-backed paths.")

        let windowStatePath = root.appendingPathComponent("Sources/RepoPrompt/App/WindowState.swift")
        let windowState = try String(contentsOf: windowStatePath, encoding: .utf8)
        XCTAssertFalse(windowState.contains(oldPropertyName), "WindowState must not instantiate old IDE-mode search view model.")
        XCTAssertFalse(windowState.contains(oldTypeName), "WindowState must not reference the old tree search VM type.")
        XCTAssertFalse(windowState.contains("fileManager.search("), "MCP workspaceSearch must not route through WorkspaceFilesViewModel.search.")
    }
}
