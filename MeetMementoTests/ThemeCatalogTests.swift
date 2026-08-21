import XCTest
@testable import MeetMemento

final class ThemeCatalogTests: XCTestCase {

    func test_catalog_hasUniqueIdsAndFiveFamiliesOfEight() {
        let ids = ThemeCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "theme ids must be unique")
        XCTAssertEqual(ThemeCatalog.all.count, 40, "themes@2 ships 5 categories x 8 topics")
        XCTAssertEqual(ThemeCatalog.catalogVersion, "themes@2")
        XCTAssertEqual(ThemeCatalog.maxConfirmedThemes, 6)
        XCTAssertEqual(ThemeCatalog.defaultSuggestionCount, 4)

        for family in ThemeFamily.allCases {
            XCTAssertEqual(ThemeCatalog.themes(in: family).count, 8, "\(family.rawValue) should hold 8 topics")
        }

        for theme in ThemeCatalog.all {
            XCTAssertFalse(theme.displayName.isEmpty)
            XCTAssertEqual(ThemeCatalog.theme(id: theme.id)?.id, theme.id)
        }
    }

    func test_validate_stripsUnknownsCapsAndDedupes() {
        let result = ThemeCatalog.validate(
            ["anxiety", "not_a_real_theme", "anxiety", "stress", "goals", "writing", "trust", "rest", "sleep"],
            max: 6
        )
        XCTAssertEqual(result, ["anxiety", "stress", "goals", "writing", "trust", "rest"])
        XCTAssertFalse(result.contains("not_a_real_theme"))
    }

    func test_legacyGoalMapping_mapsOriginalEight() {
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Self awareness"), "mindfulness")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Emotion mapping"), "therapy")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Calming control"), "stress")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Stress relief"), "stress")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Thoughtful responses"), "communication")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Self-kindness"), "self_esteem")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Honesty"), "trust")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Compassion"), "support")
    }

    func test_suggestFromKeywords_findsOverlaps() {
        let ids = ThemeCatalog.suggestFromKeywords(
            "I want less stress and more balance around work burnout",
            limit: 4
        )
        XCTAssertFalse(ids.isEmpty)
        XCTAssertTrue(ids.contains("stress") || ids.contains("work_life_balance"))
    }

    func test_localProfileStore_migratesLegacyGoals() {
        LocalProfileStore.clearAll()
        UserDefaults.standard.set("understand myself", forKey: "memento_personalization_text")
        UserDefaults.standard.set(["Self awareness", "Stress relief"], forKey: "memento_selected_goals")

        let profile = LocalProfileStore.ensureMigratedProfile()
        XCTAssertEqual(profile.reflection, "understand myself")
        XCTAssertEqual(Set(profile.confirmedThemeIds), Set(["mindfulness", "stress"]))
        XCTAssertEqual(LocalProfileStore.selectedGoals, ["Mindfulness", "Stress"])

        LocalProfileStore.clearAll()
    }
}
