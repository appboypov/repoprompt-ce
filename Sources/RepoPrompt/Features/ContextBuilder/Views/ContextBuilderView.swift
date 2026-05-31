import SwiftUI

struct ContextBuilderView: View {
    var availableWidth: CGFloat
    @ObservedObject var windowState: WindowState
    @ObservedObject var contextBuilderAgentViewModel: ContextBuilderAgentViewModel

    var body: some View {
        ContextBuilderAgentView(
            viewModel: contextBuilderAgentViewModel,
            oracleViewModel: windowState.oracleViewModel,
            windowID: windowState.windowID,
            availableWidth: availableWidth
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if windowState.kind != .contextBuilder {
                windowState.kind = .contextBuilder
            }
        }
        .onDisappear {
            guard !windowState.isClosing,
                  !WindowStatesManager.shared.isTerminating else { return }
            if windowState.kind == .contextBuilder {
                windowState.kind = .standard
            }
        }
    }
}
