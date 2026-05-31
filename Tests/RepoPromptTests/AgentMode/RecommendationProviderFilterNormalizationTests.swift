@testable import RepoPrompt
import XCTest

@MainActor
final class RecommendationProviderFilterNormalizationTests: XCTestCase {
    func testRemovedOnlyRecommendationProviderFilterFallsBackToCurrentAllProviders() {
        XCTAssertEqual(
            GlobalSettingsStore.normalizedRecommendationProviderFilter(raw: ["geminiCLI"]),
            Set(RecommendationProviderKind.allCases)
        )
    }

    func testExplicitEmptyRecommendationProviderFilterStaysEmpty() {
        XCTAssertEqual(
            GlobalSettingsStore.normalizedRecommendationProviderFilter(raw: []),
            []
        )
    }

    func testLegacyAllProvidersShapeFallsBackToCurrentAllProviders() {
        XCTAssertEqual(
            GlobalSettingsStore.normalizedRecommendationProviderFilter(raw: ["claudeCode", "codex", "openAI", "anthropic", "geminiCLI"]),
            Set(RecommendationProviderKind.allCases)
        )
    }
}
