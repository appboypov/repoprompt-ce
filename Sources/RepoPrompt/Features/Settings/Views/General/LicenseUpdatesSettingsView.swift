import SwiftUI

struct LicenseUpdatesSettingsView: View {
    @ObservedObject var windowState: WindowState
    private var sparkleManager: SparkleUpdaterManager {
        SparkleUpdaterManager.shared
    }

    var closeAction: (() -> Void)?

    init(windowState: WindowState, closeAction: (() -> Void)? = nil) {
        self.windowState = windowState
        self.closeAction = closeAction
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingSection(
                    title: "Software Updates",
                    description: "Manage application updates"
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: sparkleManager.updateAvailable ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                                .foregroundColor(sparkleManager.updateAvailable ? .blue : .green)

                            Text(
                                sparkleManager.updateAvailable ?
                                    "Version \(sparkleManager.updateVersion ?? "Unknown") is available" :
                                    "You have the latest version"
                            )
                            .foregroundColor(sparkleManager.updateAvailable ? .blue : .secondary)

                            Spacer()

                            Button("Check for Updates") {
                                sparkleManager.checkForUpdates()
                                closeAction?()
                            }
                            .buttonStyle(.bordered)
                        }

                        if sparkleManager.updateAvailable {
                            Button("Install Update") {
                                sparkleManager.installUpdate()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Toggle(
                            "Automatically check for updates",
                            isOn: Binding(
                                get: { SparkleUpdaterManager.shared.automaticallyChecksForUpdates },
                                set: { SparkleUpdaterManager.shared.automaticallyChecksForUpdates = $0 }
                            )
                        )
                    }
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
