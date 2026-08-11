//
//  ExperienceProfileTraceabilityTests.swift
//  MeetMementoTests
//
//  REQ-PRM-004: the onboarding estimate's modelIdentifier/promptVersion
//  persist on the ExperienceProfile, and stored profiles from builds without
//  those fields still decode (backward compatibility). Plus the
//  delete-everything hygiene fix: cached embedding vectors are content-derived
//  and must not survive.
//

import XCTest
@testable import MeetMemento

final class ExperienceProfileTraceabilityTests: XCTestCase {

    func test_legacyProfileJSON_withoutTraceability_decodes() throws {
        // The stored shape from builds before promptVersion existed.
        let legacyJSON = """
        {
          "reflection": "I want to understand my stress",
          "confirmedThemeIds": ["stress"],
          "suggestedThemeIds": ["stress", "clarity"],
          "promptLens": "Lean toward stress.",
          "catalogVersion": "themes@1",
          "builtAt": 776000000
        }
        """
        let profile = try JSONDecoder().decode(ExperienceProfile.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(profile.confirmedThemeIds, ["stress"])
        XCTAssertNil(profile.modelIdentifier)
        XCTAssertNil(profile.promptVersion)
    }

    func test_traceability_roundTrips() throws {
        var profile = ExperienceProfile.empty
        profile.confirmedThemeIds = ["stress"]
        profile.modelIdentifier = "apple.system.on-device"
        profile.promptVersion = "profile-estimate@1"

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(ExperienceProfile.self, from: data)
        XCTAssertEqual(decoded.modelIdentifier, "apple.system.on-device")
        XCTAssertEqual(decoded.promptVersion, "profile-estimate@1")
    }

    @MainActor
    func test_saveExperienceProfile_persistsProvenance() async throws {
        LocalProfileStore.experienceProfile = nil
        defer { LocalProfileStore.experienceProfile = nil }

        let vm = OnboardingViewModel()
        vm.personalizationText = "I want to notice my stress patterns"
        try await vm.saveExperienceProfile(
            themeIds: ["stress"],
            promptLens: "Lean toward stress.",
            suggestedIds: ["stress", "clarity"],
            modelIdentifier: "apple.system.on-device",
            promptVersion: "profile-estimate@1"
        )

        let stored = try XCTUnwrap(LocalProfileStore.experienceProfile)
        XCTAssertEqual(stored.modelIdentifier, "apple.system.on-device")
        XCTAssertEqual(stored.promptVersion, "profile-estimate@1")
    }

    func test_embeddingCache_isClearable() {
        let service = EmbeddingService.shared
        service.clearCache()
        XCTAssertEqual(service.cachedEntryCount, 0)

        // Populate (only possible where NLEmbedding assets exist — the clear
        // contract is what matters either way).
        _ = service.embedEntry(id: UUID(), text: "A quiet morning walk by the water.")
        service.clearCache()
        XCTAssertEqual(service.cachedEntryCount, 0, "delete-everything must leave no content-derived vectors")
    }
}
