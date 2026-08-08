import XCTest
@testable import MeetMemento

final class ThemeCatalogTests: XCTestCase {

    func test_catalog_hasUniqueIdsAndOneWordDisplayNames() {
        let ids = ThemeCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "theme ids must be unique")
        XCTAssertGreaterThanOrEqual(ThemeCatalog.all.count, 100)

        for theme in ThemeCatalog.all {
            XCTAssertFalse(theme.displayName.contains(" "), "\(theme.id) displayName should be one word")
            XCTAssertFalse(theme.displayName.isEmpty)
            XCTAssertEqual(ThemeCatalog.theme(id: theme.id)?.id, theme.id)
        }
    }

    func test_validate_stripsUnknownsCapsAndDedupes() {
        let result = ThemeCatalog.validate(
            ["awareness", "not_a_real_theme", "awareness", "stress", "joy", "calm", "hope", "fear", "love"],
            max: 6
        )
        XCTAssertEqual(result, ["awareness", "stress", "joy", "calm", "hope", "fear"])
        XCTAssertFalse(result.contains("not_a_real_theme"))
    }

    func test_legacyGoalMapping_mapsOriginalEight() {
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Self awareness"), "awareness")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Emotion mapping"), "emotion")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Calming control"), "regulation")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Stress relief"), "stress")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Thoughtful responses"), "communication")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Self-kindness"), "nurture")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Honesty"), "honesty")
        XCTAssertEqual(ThemeCatalog.legacyGoalMapping("Compassion"), "compassion")
    }

    func test_suggestFromKeywords_findsOverlaps() {
        let ids = ThemeCatalog.suggestFromKeywords(
            "I want less stress and more clarity around work burnout",
            limit: 4
        )
        XCTAssertFalse(ids.isEmpty)
        XCTAssertTrue(ids.contains("stress") || ids.contains("clarity") || ids.contains("burnout") || ids.contains("work"))
    }

    func test_localProfileStore_migratesLegacyGoals() {
        LocalProfileStore.clearAll()
        UserDefaults.standard.set("understand myself", forKey: "memento_personalization_text")
        UserDefaults.standard.set(["Self awareness", "Stress relief"], forKey: "memento_selected_goals")

        let profile = LocalProfileStore.ensureMigratedProfile()
        XCTAssertEqual(profile.reflection, "understand myself")
        XCTAssertEqual(Set(profile.confirmedThemeIds), Set(["awareness", "stress"]))
        XCTAssertEqual(LocalProfileStore.selectedGoals, ["Awareness", "Stress"])

        LocalProfileStore.clearAll()
    }
}
