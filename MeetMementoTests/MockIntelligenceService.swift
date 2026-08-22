import Foundation
@testable import MeetMemento

/// Deterministic IntelligenceService double for onboarding / profile tests.
final class MockIntelligenceService: IntelligenceService, @unchecked Sendable {
    var availabilityResult: IntelligenceAvailability = .available(.z0Device)
    var estimateResult: ProfileEstimateResult?
    var estimateError: Error?
    var estimateCallCount = 0
    var lastEstimateReflection: String?

    func ask(_ question: String, history: [ChatTurn], entries: [Entry], images: [Data] = []) async throws -> AskResult {
        AskResult(
            heading1: nil,
            heading2: nil,
            body: "mock reply",
            citations: [],
            zoneUsed: .z0Device,
            wasDegraded: false,
            promptVersion: "ask@6",
            modelIdentifier: "mock"
        )
    }

    func summarizeConversation(_ turns: [ChatTurn]) async throws -> GenerationOutcome<String> {
        GenerationOutcome(value: "mock summary", zoneUsed: .z0Device,
                          modelIdentifier: "mock", wasDegraded: false, latency: .zero)
    }

    func estimateProfile(reflection: String) async throws -> ProfileEstimateResult {
        estimateCallCount += 1
        lastEstimateReflection = reflection
        if let estimateError { throw estimateError }
        if let estimateResult { return estimateResult }
        return ProfileEstimateResult(
            themeIds: ["mindfulness", "stress", "not_a_real_theme", "goals"],
            secondaryThemeIds: ["gratitude", "fake_secondary"],
            promptLens: "Lean toward noticing stress and clarity without prescribing fixes.",
            zoneUsed: .z0Device,
            wasDegraded: false,
            promptVersion: "profile-estimate@1",
            modelIdentifier: "mock"
        )
    }

    func availability() async -> IntelligenceAvailability {
        availabilityResult
    }
}
