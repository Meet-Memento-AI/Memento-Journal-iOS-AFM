import XCTest
@testable import MeetMemento

@MainActor
final class ExperienceProfileBuilderTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "memento_first_name")
        UserDefaults.standard.removeObject(forKey: "memento_last_name")
        LocalProfileStore.clearAll()
        super.tearDown()
    }

    func test_rebuildLens_stripsUnknownThemeIdsAndPreservesConfirmed() async throws {
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "I want less stress and more clarity about my work",
            confirmedThemeIds: ["boundaries", "work_life_balance"],
            suggestedThemeIds: [],
            promptLens: nil,
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: nil
        )

        let mock = MockIntelligenceService()
        mock.estimateResult = ProfileEstimateResult(
            themeIds: ["stress", "goals", "invented_theme"],
            secondaryThemeIds: ["sleep", "also_fake"],
            promptLens: "Lean toward stress and goals.",
            zoneUsed: .z0Device,
            wasDegraded: false,
            promptVersion: "profile-estimate@1",
            modelIdentifier: "mock"
        )

        let profile = try await ExperienceProfileBuilder.rebuildLens(
            intelligence: mock,
            replaceConfirmedWithSuggestions: false
        )

        XCTAssertEqual(mock.estimateCallCount, 1)
        XCTAssertEqual(profile.confirmedThemeIds, ["boundaries", "work_life_balance"])
        XCTAssertFalse(profile.suggestedThemeIds.contains("invented_theme"))
        XCTAssertFalse(profile.suggestedThemeIds.contains("also_fake"))
        XCTAssertTrue(profile.suggestedThemeIds.contains("stress"))
        XCTAssertEqual(profile.promptLens, "Lean toward stress and goals.")
    }

    func test_rebuildLens_emptyReflection_clearsLensWithoutCallingModel() async throws {
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "   ",
            confirmedThemeIds: ["mindfulness"],
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
        XCTAssertEqual(profile.confirmedThemeIds, ["mindfulness"])
    }

    func test_rebuildLens_fallsBackToKeywordsWhenUnavailable() async throws {
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "I feel a lot of stress and burnout at work",
            confirmedThemeIds: ["mindfulness"],
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
        XCTAssertEqual(profile.confirmedThemeIds, ["mindfulness"])
        XCTAssertNotNil(profile.promptLens)
        XCTAssertFalse(profile.suggestedThemeIds.isEmpty)
    }

    func test_rebuildLensPreservingThemes_updatesConfirmedSet() async throws {
        LocalProfileStore.personalizationText = "I want more calm and better sleep"
        let mock = MockIntelligenceService()
        mock.estimateResult = ProfileEstimateResult(
            themeIds: ["mindfulness", "sleep"],
            secondaryThemeIds: [],
            promptLens: "Lean toward mindfulness and sleep.",
            zoneUsed: .z0Device,
            wasDegraded: false,
            promptVersion: "profile-estimate@1",
            modelIdentifier: "mock"
        )

        let profile = try await ExperienceProfileBuilder.rebuildLensPreservingThemes(
            confirmedThemeIds: ["mindfulness", "sleep", "rest"],
            reflection: "I want more calm and better sleep",
            intelligence: mock
        )

        XCTAssertEqual(Set(profile.confirmedThemeIds), Set(["mindfulness", "sleep", "rest"]))
        XCTAssertEqual(profile.promptLens, "Lean toward mindfulness and sleep.")
    }

    func test_themeAwareChatStarters_preferConfirmedThemes() {
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "stress",
            confirmedThemeIds: ["stress", "goals"],
            suggestedThemeIds: [],
            promptLens: nil,
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: nil
        )

        let starters = ThemeAwareChatStarters.starters(limit: 3)
        XCTAssertEqual(starters.count, 3)
        let joined = starters.map(\.prompt).joined(separator: " ").lowercased()
        XCTAssertTrue(joined.contains("stress") || joined.contains("goals"))
        let allowedPills = Set(ThemeCatalog.displayNames(for: ["stress", "goals"]))
        XCTAssertTrue(starters.allSatisfy { allowedPills.contains($0.themeName ?? "") })
    }

    func test_themeAwareChatStarters_fallbackWhenNoThemes() {
        LocalProfileStore.clearAll()
        let rotated = ThemeAwareChatStarters.rotate(
            genericPool: ["Generic prompt A", "Generic prompt B", "Generic prompt C"],
            limit: 3
        )
        XCTAssertEqual(rotated.count, 3)
        XCTAssertTrue(rotated.allSatisfy { $0.prompt.hasPrefix("Generic") })
        let defaultPills = Set(["Mindfulness", "Goals", "Sleep"])
        XCTAssertTrue(rotated.allSatisfy { defaultPills.contains($0.themeName ?? "") })
    }

    func test_themeAwareChatStarters_rotate_isGenericFirstWithAtMostOneThemed() {
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "stress",
            confirmedThemeIds: ["stress", "goals"],
            suggestedThemeIds: [],
            promptLens: nil,
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: nil
        )
        let rotated = ThemeAwareChatStarters.rotate(
            genericPool: ["Generic prompt A", "Generic prompt B", "Generic prompt C"],
            limit: 3
        )
        XCTAssertEqual(rotated.count, 3)
        let themedCount = rotated.filter { !$0.prompt.hasPrefix("Generic") }.count
        XCTAssertEqual(themedCount, 1)
        XCTAssertEqual(rotated.filter { $0.prompt.hasPrefix("Generic") }.count, 2)
        let allowedPills = Set(ThemeCatalog.displayNames(for: ["stress", "goals"]))
        XCTAssertTrue(rotated.allSatisfy { allowedPills.contains($0.themeName ?? "") })
        XCTAssertEqual(Set(rotated.compactMap(\.themeName)).count, 2)
    }

    func test_deterministicLens_doesNotEnumerateThemes() {
        let lens = ExperienceProfileBuilder.deterministicLens(themes: ["stress", "anxiety", "goals"])
        XCTAssertEqual(lens, "Stay conversational. Prefer open questions over advice.")
        XCTAssertFalse(lens?.lowercased().contains("stress") == true)
        XCTAssertFalse(lens?.lowercased().contains("anxiety") == true)
    }

    func test_deleteEverything_clearsExperienceProfile() {
        UserDefaults.standard.set("Ada", forKey: "memento_first_name")
        UserDefaults.standard.set("Lovelace", forKey: "memento_last_name")
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "keep me",
            confirmedThemeIds: ["mindfulness"],
            suggestedThemeIds: ["stress"],
            promptLens: "lens",
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: "mock"
        )

        let store = AppStateStore()
        store.deleteEverything()

        XCTAssertNil(LocalProfileStore.experienceProfile)
        XCTAssertNotEqual(UserDefaults.standard.string(forKey: "memento_first_name"), "Ada")
        XCTAssertNil(UserDefaults.standard.string(forKey: "memento_last_name"))
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertNil(store.firstName)
    }

    func test_saveExperienceProfile_realignsLensWhenUserDivergesFromSuggestions() async throws {
        let vm = OnboardingViewModel()
        vm.personalizationText = "I want creative play"
        try await vm.saveExperienceProfile(
            themeIds: ["writing", "inspiration"],
            promptLens: "Lean toward stress patterns.", // stale AFM lens from different themes
            suggestedIds: ["stress", "sleep"]
        )
        let profile = LocalProfileStore.experienceProfile
        XCTAssertEqual(Set(profile?.confirmedThemeIds ?? []), Set(["writing", "inspiration"]))
        XCTAssertEqual(
            profile?.promptLens,
            ExperienceProfileBuilder.deterministicLens(themes: ["writing", "inspiration"])
        )
        XCTAssertFalse(profile?.promptLens?.lowercased().contains("stress") == true)
    }

    func test_dualProfile_differentThemes_differentPromptLeanAndStarters() {
        // Profile A — stress lean
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "I want to understand my stress",
            confirmedThemeIds: ["stress", "anxiety"],
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
            confirmedThemeIds: ["creative_blocks", "inspiration"],
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

        XCTAssertTrue(askA.version.hasSuffix("+p4"))
        XCTAssertTrue(askB.version.hasSuffix("+p4"))
        XCTAssertTrue(askA.text.contains("stress") || askA.text.contains("Stress"))
        XCTAssertTrue(askB.text.contains("creative") || askB.text.contains("Creative"))
        XCTAssertFalse(askA.text.contains("Themes they chose:"))
        XCTAssertFalse(askB.text.contains("Themes they chose:"))
        XCTAssertNotEqual(askA.text, askB.text)
        // Facts/constitution stay shared — L0 phrase present in both.
        // (ask@10 wording: "a quiet companion, not a search engine and not a therapist")
        XCTAssertTrue(askA.text.contains("not a search engine and not a therapist"))
        XCTAssertTrue(askB.text.contains("not a search engine and not a therapist"))

        let aJoined = startersA.map(\.prompt).joined().lowercased()
        let bJoined = startersB.map(\.prompt).joined().lowercased()
        XCTAssertTrue(aJoined.contains("stress") || aJoined.contains("anxiety"))
        XCTAssertTrue(bJoined.contains("creative") || bJoined.contains("inspiration"))
    }
}
