import XCTest
@testable import MeetMemento

@MainActor
final class ExperienceProfileBuilderTests: XCTestCase {

    override func tearDown() {
        LocalProfileStore.clearAll()
        super.tearDown()
    }

    func test_rebuildLens_stripsUnknownThemeIdsAndPreservesConfirmed() async throws {
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "I want less stress and more clarity about my work",
            confirmedThemeIds: ["boundaries", "work"],
            suggestedThemeIds: [],
            promptLens: nil,
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: nil
        )

        let mock = MockIntelligenceService()
        mock.estimateResult = ProfileEstimateResult(
            themeIds: ["stress", "clarity", "invented_theme"],
            secondaryThemeIds: ["burnout", "also_fake"],
            promptLens: "Lean toward stress and clarity.",
            zoneUsed: .z0Device,
            wasDegraded: false,
            promptVersion: "profile-estimate@1",
            modelIdentifier: "mock",
            latency: .milliseconds(1)
        )

        let profile = try await ExperienceProfileBuilder.rebuildLens(
            intelligence: mock,
            replaceConfirmedWithSuggestions: false
        )

        XCTAssertEqual(mock.estimateCallCount, 1)
        XCTAssertEqual(profile.confirmedThemeIds, ["boundaries", "work"])
        XCTAssertFalse(profile.suggestedThemeIds.contains("invented_theme"))
        XCTAssertFalse(profile.suggestedThemeIds.contains("also_fake"))
        XCTAssertTrue(profile.suggestedThemeIds.contains("stress"))
        XCTAssertEqual(profile.promptLens, "Lean toward stress and clarity.")
    }

    func test_rebuildLens_emptyReflection_clearsLensWithoutCallingModel() async throws {
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "   ",
            confirmedThemeIds: ["awareness"],
            suggestedThemeIds: [],
            promptLens: "stale lens",
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: nil
        )

        let mock = MockIntelligenceService()
        let profile = try await ExperienceProfileBuilder.rebuildLens(intelligence: mock)

        XCTAssertEqual(mock.estimateCallCount, 0)
        XCTAssertNil(profile.promptLens)
        XCTAssertEqual(profile.confirmedThemeIds, ["awareness"])
    }

    func test_rebuildLens_fallsBackToKeywordsWhenUnavailable() async throws {
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "I feel a lot of stress and burnout at work",
            confirmedThemeIds: ["awareness"],
            suggestedThemeIds: [],
            promptLens: nil,
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: nil
        )

        let mock = MockIntelligenceService()
        mock.estimateError = IntelligenceError.unavailable(.deviceNotEligible)

        let profile = try await ExperienceProfileBuilder.rebuildLens(intelligence: mock)

        XCTAssertEqual(profile.modelIdentifier, "keyword-fallback")
        XCTAssertEqual(profile.confirmedThemeIds, ["awareness"])
        XCTAssertNotNil(profile.promptLens)
        XCTAssertFalse(profile.suggestedThemeIds.isEmpty)
    }

    func test_rebuildLensPreservingThemes_updatesConfirmedSet() async throws {
        LocalProfileStore.personalizationText = "I want more calm and better sleep"
        let mock = MockIntelligenceService()
        mock.estimateResult = ProfileEstimateResult(
            themeIds: ["calm", "sleep"],
            secondaryThemeIds: [],
            promptLens: "Lean toward calm and sleep.",
            zoneUsed: .z0Device,
            wasDegraded: false,
            promptVersion: "profile-estimate@1",
            modelIdentifier: "mock",
            latency: .milliseconds(1)
        )

        let profile = try await ExperienceProfileBuilder.rebuildLensPreservingThemes(
            confirmedThemeIds: ["calm", "sleep", "rest"],
            reflection: "I want more calm and better sleep",
            intelligence: mock
        )

        XCTAssertEqual(Set(profile.confirmedThemeIds), Set(["calm", "sleep", "rest"]))
        XCTAssertEqual(profile.promptLens, "Lean toward calm and sleep.")
    }

    func test_themeAwareChatStarters_preferConfirmedThemes() {
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "stress",
            confirmedThemeIds: ["stress", "clarity"],
            suggestedThemeIds: [],
            promptLens: nil,
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: nil
        )

        let starters = ThemeAwareChatStarters.starters(limit: 3)
        XCTAssertEqual(starters.count, 3)
        let joined = starters.joined(separator: " ").lowercased()
        XCTAssertTrue(joined.contains("stress") || joined.contains("clarity"))
    }

    func test_themeAwareChatStarters_fallbackWhenNoThemes() {
        LocalProfileStore.clearAll()
        let rotated = ThemeAwareChatStarters.rotate(
            genericPool: ["Generic prompt A", "Generic prompt B", "Generic prompt C"],
            limit: 3
        )
        XCTAssertEqual(rotated.count, 3)
        XCTAssertTrue(rotated.allSatisfy { $0.hasPrefix("Generic") })
    }

    func test_deleteEverything_clearsExperienceProfile() {
        UserDefaults.standard.set("Ada", forKey: "memento_first_name")
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "keep me",
            confirmedThemeIds: ["awareness"],
            suggestedThemeIds: ["stress"],
            promptLens: "lens",
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: "mock"
        )

        let store = AppStateStore()
        store.deleteEverything()

        XCTAssertNil(LocalProfileStore.experienceProfile)
        XCTAssertTrue(PromptPersonalization.fromLocalProfile().isEmpty)
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertNil(store.firstName)
    }

    func test_saveExperienceProfile_realignsLensWhenUserDivergesFromSuggestions() async throws {
        let vm = OnboardingViewModel()
        vm.personalizationText = "I want creative play"
        try await vm.saveExperienceProfile(
            themeIds: ["creativity", "play"],
            promptLens: "Lean toward stress patterns.", // stale AFM lens from different themes
            suggestedIds: ["stress", "burnout"]
        )
        let profile = LocalProfileStore.experienceProfile
        XCTAssertEqual(Set(profile?.confirmedThemeIds ?? []), Set(["creativity", "play"]))
        XCTAssertEqual(
            profile?.promptLens,
            ExperienceProfileBuilder.deterministicLens(themes: ["creativity", "play"])
        )
        XCTAssertFalse(profile?.promptLens?.lowercased().contains("stress") == true)
    }

    func test_dualProfile_differentThemes_differentPromptLeanAndStarters() {
        // Profile A — stress lean
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "I want to understand my stress",
            confirmedThemeIds: ["stress", "burnout"],
            suggestedThemeIds: [],
            promptLens: "Lean toward stress patterns.",
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: "mock"
        )
        let askA = PromptRegistry.instructions(
            for: .ask,
            personalization: .fromLocalProfile()
        )
        let startersA = ThemeAwareChatStarters.starters(limit: 3)

        // Profile B — creativity lean
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "I want to explore creativity",
            confirmedThemeIds: ["creativity", "play"],
            suggestedThemeIds: [],
            promptLens: "Lean toward creative expression.",
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: "mock"
        )
        let askB = PromptRegistry.instructions(
            for: .ask,
            personalization: .fromLocalProfile()
        )
        let startersB = ThemeAwareChatStarters.starters(limit: 3)

        XCTAssertTrue(askA.version.hasSuffix("+p2"))
        XCTAssertTrue(askB.version.hasSuffix("+p2"))
        XCTAssertTrue(askA.text.contains("Stress") || askA.text.contains("stress"))
        XCTAssertTrue(askB.text.contains("Creativity") || askB.text.contains("creative"))
        XCTAssertNotEqual(askA.text, askB.text)
        // Facts/constitution stay shared — L0 phrase present in both.
        XCTAssertTrue(askA.text.contains("mirror, not a therapist"))
        XCTAssertTrue(askB.text.contains("mirror, not a therapist"))

        let aJoined = startersA.joined().lowercased()
        let bJoined = startersB.joined().lowercased()
        XCTAssertTrue(aJoined.contains("stress") || aJoined.contains("burnout"))
        XCTAssertTrue(bJoined.contains("creativity") || bJoined.contains("play"))
    }
}
