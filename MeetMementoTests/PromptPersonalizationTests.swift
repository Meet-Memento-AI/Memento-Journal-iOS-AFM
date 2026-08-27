import XCTest
@testable import MeetMemento

final class PromptPersonalizationTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "memento_first_name")
        UserDefaults.standard.removeObject(forKey: "memento_last_name")
        LocalProfileStore.clearAll()
        super.tearDown()
    }

    func test_emptyPersonalization_keepsBasePromptAndVersion() {
        let resolved = PromptRegistry.instructions(for: .ask, personalization: .none)
        XCTAssertEqual(resolved.version, "ask@15")
        // Assert on the section HEADER, not the bare phrase. ask@4 added
        // `Never recite … the "About this person" section` to the Hard bans, so
        // the base prompt legitimately contains that phrase and the old
        // `contains("About this person")` assertion has been failing on main
        // ever since. What this test actually means is "no personalization
        // section was appended", and only the header proves that.
        XCTAssertFalse(resolved.text.contains("About this person (quiet background"))
    }

    func test_personalizedPrompt_appendsSectionAndVersionSuffix() {
        let p = PromptPersonalization(
            firstName: "Sebastian",
            reflection: "I want to understand my stress patterns",
            goals: ["Awareness", "Stress"],
            promptLens: "Lean toward noticing stress patterns without prescribing fixes."
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@15+p4")
        XCTAssertTrue(resolved.text.contains("About this person"))
        XCTAssertTrue(resolved.text.contains("Sebastian"))
        XCTAssertTrue(resolved.text.contains("first or last"))
        XCTAssertTrue(resolved.text.contains("never both in one reply"))
        XCTAssertFalse(resolved.text.contains("I want to understand my stress patterns"))
        XCTAssertFalse(resolved.text.contains("Awareness, Stress"))
        XCTAssertFalse(resolved.text.contains("Themes they chose:"))
        XCTAssertTrue(resolved.text.contains("Faint lens (not an agenda):"))
        XCTAssertTrue(resolved.text.contains("Conversation first"))
        XCTAssertTrue(resolved.text.contains("never recite this back"))
    }

    func test_reflectionOnly_doesNotAppendL1() {
        let p = PromptPersonalization(
            firstName: nil,
            reflection: "I want to understand my stress patterns more deeply",
            goals: [],
            promptLens: nil
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@15")
        XCTAssertFalse(resolved.text.contains("About this person (quiet background"))
        XCTAssertFalse(resolved.text.contains("I want to understand my stress patterns more deeply"))
    }

    func test_askLens_isTruncated() {
        let long = String(repeating: "b", count: 200)
        let p = PromptPersonalization(firstName: nil, reflection: nil, goals: [], promptLens: long)
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertFalse(resolved.text.contains(long))
        XCTAssertTrue(resolved.text.contains(String(repeating: "b", count: PromptRegistry.maxAskPromptLensChars) + "…"))
    }

    func test_degradedVariant_skipsReflectionAndThemeRoster() {
        let p = PromptPersonalization(
            firstName: nil,
            reflection: "my long reflection text",
            goals: ["Honesty"],
            promptLens: "Stay conversational."
        )
        let resolved = PromptRegistry.instructions(for: .ask, degraded: true, personalization: p)
        XCTAssertEqual(resolved.version, "ask-degraded@15+p4")
        XCTAssertFalse(resolved.text.contains("my long reflection text"))
        XCTAssertFalse(resolved.text.contains("Honesty"))
        XCTAssertTrue(resolved.text.contains("Conversation first"))
    }

    func test_summaryPrompt_ignoresPersonalization() {
        let p = PromptPersonalization(firstName: "Sam", reflection: nil, goals: ["Honesty"], promptLens: nil)
        let resolved = PromptRegistry.instructions(for: .summary, personalization: p)
        XCTAssertEqual(resolved.version, "summarize@2")
        XCTAssertFalse(resolved.text.contains("About this person"))
        XCTAssertTrue(resolved.text.contains("title:"))
        XCTAssertTrue(resolved.text.contains("Chat Reflection"))
    }

    func test_profileEstimatePrompt_isBundled() {
        let resolved = PromptRegistry.instructions(for: .profileEstimate)
        XCTAssertEqual(resolved.version, "profile-estimate@2")
        XCTAssertTrue(resolved.text.contains("closed catalog") || resolved.text.contains("theme ids"))
        XCTAssertTrue(resolved.text.contains("Conversation-first") || resolved.text.contains("one short third-person clause"))
    }

    func test_fromLocalProfile_roundTrip() {
        UserDefaults.standard.set("  Sebastian ", forKey: "memento_first_name")
        UserDefaults.standard.set("  Mendoza ", forKey: "memento_last_name")
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "understand myself better",
            confirmedThemeIds: ["mindfulness"],
            suggestedThemeIds: ["mindfulness", "stress"],
            promptLens: "Lean toward self-awareness questions.",
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            modelIdentifier: nil
        )

        let p = PromptPersonalization.fromLocalProfile()
        XCTAssertEqual(p.firstName, "Sebastian")
        XCTAssertEqual(p.lastName, "Mendoza")
        XCTAssertEqual(p.reflection, "understand myself better")
        XCTAssertEqual(p.goals, ["Mindfulness"])
        XCTAssertEqual(p.promptLens, "Lean toward self-awareness questions.")
        XCTAssertFalse(p.isEmpty)
        XCTAssertTrue(p.hasAskPersonalization)
        XCTAssertEqual(p.spokenName, "Sebastian Mendoza")
        XCTAssertTrue(p.nameCueLine?.contains("[Name: Sebastian Mendoza") == true)
    }

    func test_nameAntiRepeat_whenLastAssistantUsedAName() {
        let p = PromptPersonalization(
            firstName: "Sebastian", lastName: "Mendoza",
            reflection: nil, goals: [], promptLens: nil
        )
        let usedFirst = [ChatTurn(role: .assistant, text: "Hey Sebastian. How has the week been?")]
        XCTAssertEqual(p.nameAntiRepeatLine(from: usedFirst), "[Don't use their name this turn.]")
        let usedLast = [ChatTurn(role: .assistant, text: "Take care, Mendoza.")]
        XCTAssertEqual(p.nameAntiRepeatLine(from: usedLast), "[Don't use their name this turn.]")
        let unused = [ChatTurn(role: .assistant, text: "Hey. How has the week been?")]
        XCTAssertNil(p.nameAntiRepeatLine(from: unused))
        let possessive = [ChatTurn(role: .assistant, text: "Sebastian's week sounded full.")]
        XCTAssertEqual(p.nameAntiRepeatLine(from: possessive), "[Don't use their name this turn.]")
    }

    func test_nameAntiRepeat_requiresWholeToken() {
        let p = PromptPersonalization(
            firstName: "Ann", lastName: "Li",
            reflection: nil, goals: [], promptLens: nil
        )
        XCTAssertTrue(PromptPersonalization.textContainsSpokenName("Hey Ann.", name: "Ann"))
        XCTAssertFalse(PromptPersonalization.textContainsSpokenName("The annual review was a lot.", name: "Ann"))
        XCTAssertFalse(PromptPersonalization.textContainsSpokenName("I applied.", name: "Li"))
        XCTAssertTrue(PromptPersonalization.textContainsSpokenName("Take care, Li.", name: "Li"))
        XCTAssertNil(p.nameAntiRepeatLine(from: [
            ChatTurn(role: .assistant, text: "The annual review was a lot.")
        ]))
        XCTAssertEqual(
            p.nameAntiRepeatLine(from: [ChatTurn(role: .assistant, text: "Hey Ann. How was it?")]),
            "[Don't use their name this turn.]"
        )
    }

    func test_lastNameOnly_countsAsPersonalization() {
        let p = PromptPersonalization(
            firstName: nil,
            lastName: "Mendoza",
            reflection: nil,
            goals: [],
            promptLens: nil
        )
        XCTAssertTrue(p.hasAskPersonalization)
        XCTAssertEqual(p.spokenName, "Mendoza")
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@15+p4")
        XCTAssertTrue(resolved.text.contains("Mendoza"))
        XCTAssertTrue(resolved.text.contains("first or last"))
        XCTAssertFalse(resolved.text.contains("Use it sparingly"))
    }

    func test_nameCueLine_omitsWhenNoName() {
        let p = PromptPersonalization(
            firstName: nil, lastName: nil, reflection: nil, goals: [], promptLens: "Stay conversational."
        )
        XCTAssertNil(p.nameCueLine)
        XCTAssertTrue(p.hasAskPersonalization)
    }

    func test_fromLocalProfile_emptyWhenNothingStored() {
        // Write values we control, then clear. Do not require the simulator's
        // leftover display name to be empty — the host app may still hold one.
        UserDefaults.standard.set("TempFirst", forKey: "memento_first_name")
        UserDefaults.standard.set("TempLast", forKey: "memento_last_name")
        LocalProfileStore.clearAll()
        XCTAssertEqual(PromptPersonalization.fromLocalProfile().lastName, "TempLast")

        UserDefaults.standard.removeObject(forKey: "memento_first_name")
        UserDefaults.standard.removeObject(forKey: "memento_last_name")
        LocalProfileStore.clearAll()
        let p = PromptPersonalization.fromLocalProfile()
        XCTAssertNotEqual(p.firstName, "TempFirst")
        XCTAssertNil(p.lastName)
        XCTAssertNil(p.promptLens)
        XCTAssertTrue(p.goals.isEmpty)
    }
}
