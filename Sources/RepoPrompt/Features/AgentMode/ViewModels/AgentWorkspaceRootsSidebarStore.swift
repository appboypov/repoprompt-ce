import Combine
import Foundation

struct AgentWorkspaceRootRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let fullPath: String
    let isPrimary: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    /// Bound-worktree visual identity for the active Agent session, when this
    /// logical root is bound (Item 10). Populated by the roots section view,
    /// not by `rows(from:)` — the store stays session-agnostic.
    let worktree: AgentWorktreeIndicator?

    init(
        id: UUID,
        name: String,
        fullPath: String,
        isPrimary: Bool,
        canMoveUp: Bool,
        canMoveDown: Bool,
        worktree: AgentWorktreeIndicator? = nil
    ) {
        self.id = id
        self.name = name
        self.fullPath = fullPath
        self.isPrimary = isPrimary
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.worktree = worktree
    }

    /// Returns a copy of this row carrying `worktree` as its bound-worktree
    /// identity. Used to enrich store-derived rows with active-session state.
    func withWorktree(_ worktree: AgentWorktreeIndicator?) -> AgentWorkspaceRootRow {
        AgentWorkspaceRootRow(
            id: id,
            name: name,
            fullPath: fullPath,
            isPrimary: isPrimary,
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            worktree: worktree
        )
    }
}

@MainActor
final class AgentWorkspaceRootsSidebarStore: ObservableObject {
    @Published private(set) var rootRows: [AgentWorkspaceRootRow] = []
    @Published private(set) var workspaceLabel = "No Workspace"
    @Published private(set) var isExitDisabled = true

    private let rootProjections: @MainActor () -> [WorkspaceRootShellProjection]
    private let rootChanges: AnyPublisher<Void, Never>
    private let workspaceManager: WorkspaceManagerViewModel
    let windowID: Int

    private var cancellables: Set<AnyCancellable> = []
    private var resnapshotTask: Task<Void, Never>?

    var workspaceManagerForPicker: WorkspaceManagerViewModel {
        workspaceManager
    }

    init(
        rootProjections: @escaping @MainActor () -> [WorkspaceRootShellProjection],
        rootChanges: AnyPublisher<Void, Never>,
        workspaceManager: WorkspaceManagerViewModel,
        windowID: Int
    ) {
        self.rootProjections = rootProjections
        self.rootChanges = rootChanges
        self.workspaceManager = workspaceManager
        self.windowID = windowID

        resnapshot()
        observeInputs()
    }

    deinit {
        resnapshotTask?.cancel()
    }

    static func rows(from projections: [WorkspaceRootShellProjection]) -> [AgentWorkspaceRootRow] {
        let rootCount = projections.count
        return projections.enumerated().map { index, projection in
            AgentWorkspaceRootRow(
                id: projection.id,
                name: projection.name,
                fullPath: projection.fullPath,
                isPrimary: rootCount > 1 && index == 0,
                canMoveUp: rootCount > 1 && index > 0,
                canMoveDown: rootCount > 1 && index < rootCount - 1
            )
        }
    }

    func addFolder() async throws {
        try await workspaceManager.pickFolderAndOpenWorkspace(
            title: "Add Folder",
            message: "Choose a folder to add to your workspace.",
            behavior: .addToActiveOrCreateNew
        )
    }

    func exitWorkspace() async {
        await workspaceManager.saveAndExitToFallback()
    }

    func removeRoot(rowID: UUID) {
        guard let projection = currentProjection(for: rowID) else { return }
        Task { [workspaceManager] in
            await workspaceManager.removeActiveWorkspaceRoot(path: projection.fullPath)
        }
    }

    func moveRootUp(rowID: UUID) {
        guard let projection = currentProjection(for: rowID) else { return }
        let visibleRootOrder = rootProjections().map(\.fullPath)
        Task { [workspaceManager] in
            await workspaceManager.moveActiveWorkspaceRoot(
                path: projection.fullPath,
                direction: .up,
                visibleRootOrder: visibleRootOrder
            )
        }
    }

    func moveRootDown(rowID: UUID) {
        guard let projection = currentProjection(for: rowID) else { return }
        let visibleRootOrder = rootProjections().map(\.fullPath)
        Task { [workspaceManager] in
            await workspaceManager.moveActiveWorkspaceRoot(
                path: projection.fullPath,
                direction: .down,
                visibleRootOrder: visibleRootOrder
            )
        }
    }

    private func observeInputs() {
        rootChanges
            .sink { [weak self] in
                Task { @MainActor in
                    self?.scheduleResnapshot()
                }
            }
            .store(in: &cancellables)

        workspaceManager.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleResnapshot()
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleResnapshot() {
        resnapshotTask?.cancel()
        resnapshotTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.resnapshot()
            }
        }
    }

    private func resnapshot() {
        let nextRootRows = Self.rows(from: rootProjections())
        let nextWorkspaceLabel = Self.workspaceLabel(for: workspaceManager.activeWorkspace)
        let nextIsExitDisabled = workspaceManager.activeWorkspace?.isSystemWorkspace ?? true

        if rootRows != nextRootRows {
            rootRows = nextRootRows
        }
        if workspaceLabel != nextWorkspaceLabel {
            workspaceLabel = nextWorkspaceLabel
        }
        if isExitDisabled != nextIsExitDisabled {
            isExitDisabled = nextIsExitDisabled
        }
    }

    private func currentProjection(for rowID: UUID) -> WorkspaceRootShellProjection? {
        rootProjections().first { $0.id == rowID }
    }

    private static func workspaceLabel(for workspace: WorkspaceModel?) -> String {
        guard let workspace, !workspace.isSystemWorkspace else { return "No Workspace" }
        let name = workspace.name
        return name.count > 16 ? String(name.prefix(16)) + "…" : name
    }
}
