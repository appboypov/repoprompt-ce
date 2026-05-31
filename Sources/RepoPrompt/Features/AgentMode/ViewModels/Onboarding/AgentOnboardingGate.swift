//
//  AgentOnboardingGate.swift
//  RepoPrompt
//
//  Created by RepoPrompt on 2026-02-05.
//

import Foundation

// MARK: - Agent Onboarding Gate

/// Determines whether the Agent Mode onboarding wizard should be presented.
/// Shows only if the user has never seen it.
enum AgentOnboardingGate {
    private static let hasSeenOnboardingKey = "agentOnboardingHasSeen"

    @MainActor static func shouldShow() -> Bool {
        !UserDefaults.standard.bool(forKey: hasSeenOnboardingKey)
    }

    @MainActor static func markSeen() {
        UserDefaults.standard.set(true, forKey: hasSeenOnboardingKey)
        WindowStatesManager.applyProAutoRestoreDefaultIfUnset()
    }
}

// MARK: - Presentation Coordinator

/// In-memory coordinator that ensures only one window presents the onboarding
/// per app launch. Prevents "open 2 windows → 2 onboarding sheets" problem.
@MainActor
final class AgentOnboardingPresentationCoordinator {
    static let shared = AgentOnboardingPresentationCoordinator()

    private var presentedThisLaunch = false

    private init() {}

    /// Attempts to claim the presentation slot. Returns `true` exactly once per launch.
    func claimPresentationSlot() -> Bool {
        guard !presentedThisLaunch else { return false }
        presentedThisLaunch = true
        return true
    }
}
