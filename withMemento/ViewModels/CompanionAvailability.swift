//
//  CompanionAvailability.swift
//  withMemento
//
//  Whether the on-device model can answer, read before the first send so Chat
//  can show a designed state instead of a composer whose send would only fail.
//

import Foundation

@MainActor
final class CompanionAvailability: ObservableObject {
    @Published private(set) var unavailableReason: IntelligenceUnavailableReason?

    private let probe: () async -> IntelligenceAvailability

    init(probe: @escaping () async -> IntelligenceAvailability = {
        await FoundationModelsIntelligenceService.shared.availability()
    }) {
        self.probe = probe
    }

    /// Negative results are never cached by the intelligence layer, so this
    /// picks up a model that finished downloading.
    func refresh() async {
        let reason: IntelligenceUnavailableReason?
        if case .unavailable(let unavailable) = await probe() {
            reason = unavailable
        } else {
            reason = nil
        }
        if reason != unavailableReason { unavailableReason = reason }
    }
}
