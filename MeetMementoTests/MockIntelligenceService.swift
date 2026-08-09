import Foundation
@testable import MeetMemento

/// Deterministic IntelligenceService double for onboarding / profile tests.
final class MockIntelligenceService: IntelligenceService, @unchecked Sendable {
    var availabilityResult: IntelligenceAvailability = .available(.onDevice)
    var estimateResult: ProfileEstimateResult?
    var estimateError: Error?
    var estimateCallCount = 0
    var lastEstimateReflection: String?

    func ask(_ question: String, history: [ChatTurn], entries: [Entry]) async throws -> AskResult {
        AskResult(
            heading1: nil,
            heading2: nil,
            body: "mock reply",
            citations: [],
            zoneUsed: .onDevice,
            wasDegraded: false,
            promptVersion: "ask@5",
            modelIdentifier: "mock"
        )
    }

    func summarizeConversation(_ turns: [ChatTurn]) async throws -> String {
        "mock summary"
    }

    func estimateProfile(reflection: String) async throws -> ProfileEstimateResult {
        estimateCallCount += 1
        lastEstimateReflection = reflection
        if let estimateError { throw estimateError }
        if let estimateResult { return estimateResult }
        return ProfileEstimateResult(
            themeIds: ["awareness", "stress", "not_a_real_theme", "clarity"],
            secondaryThemeIds: ["hope", "fake_secondary"],
            promptLens: "Lean toward noticing stress and clarity without prescribing fixes.",
            zoneUsed: .onDevice,
            wasDegraded: false,
            promptVersion: "profile-estimate@1",
            modelIdentifier: "mock"
        )
    }

    func availability() async -> IntelligenceAvailability {
        availabilityResult
    }
}
