import XCTest
@testable import MeetMemento

final class Session812Tests: XCTestCase {

    override func tearDown() {
        EntrySaveSideEffects.reset()
        WeeklyReflectionStore.clear()
        LocalProfileStore.clearAll()
        UserDefaults.standard.removeObject(forKey: "memento_first_name")
        UserDefaults.standard.removeObject(forKey: "memento_last_name")
        super.tearDown()
    }

    // MARK: Session 8

    func test_entryReflection_routesOnDeviceInteractive() {
        let row = ModelRouter.row(for: .entryReflection)
        XCTAssertEqual(row?.defaultZone, .z0Device)
        XCTAssertNil(row?.degradedZone)
        XCTAssertEqual(row?.priority, .interactive)
        let resolved = PromptRegistry.resolve(intent: .entryReflection, zone: .z0Device, degraded: false)
        XCTAssertEqual(resolved.version, "entry-reflect@1")
        XCTAssertFalse(resolved.text.isEmpty)
    }

    func test_saveFailure_doesNotScheduleReflection() {
        var scheduled: Entry?
        EntrySaveSideEffects.onSchedule = { scheduled = $0 }
        let entry = Entry(title: "Keep me", text: "original transcript")
        EntrySaveSideEffects.afterSuccessfulSave(entry, saved: false)
        XCTAssertNil(scheduled)
        XCTAssertEqual(entry.text, "original transcript")
        EntrySaveSideEffects.afterSuccessfulSave(entry, saved: true)
        XCTAssertEqual(scheduled?.id, entry.id)
        XCTAssertEqual(scheduled?.text, "original transcript")
    }

    func test_lowSalience_writesNoObservation() {
        XCTAssertFalse(EntryReflectionPolicy.shouldWriteObservation(salience: 0.2))
        XCTAssertTrue(EntryReflectionPolicy.shouldWriteObservation(salience: 0.4))
    }

    func test_moodAndTopicVocab_areClosedAndVersioned() {
        XCTAssertEqual(MoodLabel.allCases.count, 12)
        XCTAssertEqual(TopicLabel.allCases.count, 12)
        XCTAssertTrue(ReflectionVocabulary.version.contains("@"))
    }

    // MARK: Session 9

    func test_weekly_sdkUnsupported_isBaselineNotDegradation() {
        let route = ModelRouter.resolve(
            intent: .weeklyReflection, pinnedToDevice: false, pccCapability: .sdkUnsupported
        )
        XCTAssertEqual(route.executionZone, .z0Device)
        XCTAssertFalse(route.wasDegraded)
        XCTAssertEqual(route.reason, .sdkUnsupported)
        let full = PromptRegistry.resolve(intent: .weeklyReflection, zone: .z0Device, degraded: false)
        let degraded = PromptRegistry.resolve(intent: .weeklyReflection, zone: .z0Device, degraded: true)
        XCTAssertEqual(full.version, "weekly@1")
        XCTAssertEqual(degraded.version, "weekly-degraded@1")
        XCTAssertNotEqual(full.text, degraded.text)
    }

    func test_sparseWeek_marksCoveredWithQuietCopy() {
        let calendar = InsightEngine.isoCalendar(.current)
        let now = Date()
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start),
              let previous = calendar.dateInterval(of: .weekOfYear, for: cursor)
        else {
            return XCTFail("could not form ISO week")
        }
        let week = InsightEngine.orderedInterval(start: previous.start, end: previous.end)
        let entry = Entry(title: "One", text: "A single note.", createdAt: week.start.addingTimeInterval(3_600))
        XCTAssertNotNil(
            WeeklyReflectionCoordinator.previousUncoveredWeek(entries: [entry], now: now, calendar: calendar)
        )
        WeeklyReflectionCoordinator.persistQuiet(weekStart: week.start)
        XCTAssertTrue(WeeklyReflectionStore.hasNothingToSay)
        XCTAssertEqual(WeeklyReflectionStore.latestBody, WeeklyReflectionCoordinator.quietCopy)
        XCTAssertTrue(WeeklyReflectionStore.isCovered(weekStart: week.start))
        XCTAssertNil(
            WeeklyReflectionCoordinator.previousUncoveredWeek(entries: [entry], now: now, calendar: calendar)
        )
    }

    func test_quietCopy_isSpeakable() throws {
        try SpeakabilityLinter.validate(WeeklyReflectionCoordinator.quietCopy)
    }

    // MARK: Session 10

    func test_searchTool_attachesOnlyWhenChannelAllowsRetrieval() {
        XCTAssertTrue(SearchJournalPolicy.shouldAttach(channel: .notebook))
        XCTAssertTrue(SearchJournalPolicy.shouldAttach(channel: .thread))
        XCTAssertFalse(SearchJournalPolicy.shouldAttach(channel: .phatic))
        XCTAssertFalse(SearchJournalPolicy.shouldAttach(channel: .continuer))
        XCTAssertFalse(SearchJournalPolicy.shouldAttach(channel: .companion))
        XCTAssertFalse(SearchJournalPolicy.shouldAttach(channel: .meta))
        XCTAssertFalse(SearchJournalPolicy.shouldAttach(channel: .redirect))
        XCTAssertFalse(SearchJournalPolicy.shouldAttach(channel: .statistic))
    }

    func test_searchTool_thirdCallReturnsExhausted_withoutRetrieve() {
        let state = SearchJournalTurnState()
        var retrieves = 0
        for _ in 0..<3 {
            let prior = state.beginCall()
            if SearchJournalPolicy.admit(callsSoFar: prior) == nil {
                retrieves += 1
                state.ingest([])
            }
        }
        XCTAssertEqual(retrieves, 2)
        XCTAssertEqual(state.toolsCalled, 3)
        XCTAssertEqual(SearchJournalPolicy.admit(callsSoFar: 2), SearchJournalPolicy.exhaustedMessage)
    }

    func test_phaticPlan_doesNotAttachSearchTool() {
        let plan = AskTranscriptPlan.build(
            instructions: PromptRegistry.instructions(for: .ask, channel: .phatic).text,
            history: [],
            budget: ContextBudget(window: .unavailable),
            attachesSearchTool: SearchJournalPolicy.shouldAttach(channel: .phatic)
        )
        XCTAssertFalse(plan.attachesSearchTool)
        let notebook = AskTranscriptPlan.build(
            instructions: "core",
            history: [],
            budget: ContextBudget(window: .unavailable),
            attachesSearchTool: true
        )
        XCTAssertTrue(notebook.attachesSearchTool)
        XCTAssertNotEqual(plan.fingerprint, notebook.fingerprint)
    }

    func test_askResult_toolsCalledDefaultsToZero() {
        let result = AskResult(
            heading1: nil, heading2: nil, body: "hi", citations: [],
            zoneUsed: .z0Device, wasDegraded: false,
            promptVersion: "ask-core@16", modelIdentifier: "mock"
        )
        XCTAssertEqual(result.toolsCalled, 0)
    }

    // MARK: Session 11

    func test_profileRefresh_isScheduledDeviceOnly() {
        let row = ModelRouter.row(for: .profileRefresh)
        XCTAssertEqual(row?.defaultZone, .z0Device)
        XCTAssertNil(row?.degradedZone)
        XCTAssertEqual(row?.priority, .scheduled)
        let resolved = PromptRegistry.resolve(intent: .profileRefresh, zone: .z0Device, degraded: false)
        XCTAssertEqual(resolved.version, "profile-refresh@1")
    }

    func test_unacceptedProposal_doesNotReachAskLens() {
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: "notice when I overcommit",
            confirmedThemeIds: ["mindfulness"],
            suggestedThemeIds: ["mindfulness"],
            promptLens: "Stay conversational.",
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date(),
            proposedPromptLens: "You should dwell on stress every reply."
        )
        let personalization = PromptPersonalization.fromLocalProfile()
        XCTAssertEqual(personalization.promptLens, "Stay conversational.")
        XCTAssertFalse(personalization.promptLens?.contains("dwell on stress") == true)
    }

    func test_profileRefresh_cadenceRequiresDaysAndNewEntries() {
        let old = Calendar.current.date(byAdding: .day, value: -20, to: Date()) ?? Date()
        var profile = ExperienceProfile.empty
        profile.builtAt = old
        let fresh = (0..<10).map { index in
            Entry(
                title: "E\(index)",
                text: "note",
                createdAt: old.addingTimeInterval(TimeInterval(86_400 * (index + 1)))
            )
        }
        XCTAssertTrue(ProfileRefreshCoordinator.isDue(profile: profile, entries: fresh))
        XCTAssertFalse(ProfileRefreshCoordinator.isDue(profile: profile, entries: Array(fresh.prefix(3))))
        profile.builtAt = Date()
        XCTAssertFalse(ProfileRefreshCoordinator.isDue(profile: profile, entries: fresh))
    }

    func test_acceptProposal_promotesLens() {
        LocalProfileStore.experienceProfile = ExperienceProfile(
            reflection: nil,
            confirmedThemeIds: [],
            suggestedThemeIds: [],
            promptLens: "Keep mine.",
            catalogVersion: ThemeCatalog.catalogVersion,
            builtAt: Date().addingTimeInterval(-86_400 * 20),
            proposedPromptLens: "Stay with what they already named.",
            proposedPromptVersion: "profile-refresh@1"
        )
        ProfileRefreshCoordinator.acceptProposal()
        let stored = LocalProfileStore.ensureMigratedProfile()
        XCTAssertEqual(stored.promptLens, "Stay with what they already named.")
        XCTAssertNil(stored.proposedPromptLens)
        XCTAssertEqual(PromptPersonalization.fromLocalProfile().promptLens, "Stay with what they already named.")
    }

    func test_forbiddenPhrase_discardsProposal() {
        XCTAssertTrue(ProfileRefreshCoordinator.containsForbiddenPhrase("You should try harder."))
        XCTAssertFalse(ProfileRefreshCoordinator.containsForbiddenPhrase("Stay conversational."))
    }

    // MARK: Session 12

    func test_computedBlock_omitsSuppressedFacts() {
        let window = DateInterval(start: Date(), duration: 86_400)
        let low = InsightFact(
            kind: .count, label: "sleep", value: "2", n: 2,
            window: window, supportingEntryIDs: []
        )
        let ok = InsightFact(
            kind: .person, label: "Maya", value: "5", n: 5,
            window: window, supportingEntryIDs: []
        )
        XCTAssertNil(ComputedFactsBlock.render([low]))
        let block = ComputedFactsBlock.render([low, ok])
        XCTAssertTrue(block?.contains("[Computed]") == true)
        XCTAssertTrue(block?.contains("Maya") == true)
        XCTAssertFalse(block?.contains("sleep") == true)
        XCTAssertFalse(block?.contains("5") == true)
        XCTAssertTrue(block?.contains("several") == true)
    }

    func test_valenceTrend_requiresTaggedEntries() {
        let calendar = Calendar(identifier: .iso8601)
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2)) ?? Date()
        let entries = (0..<6).map { index in
            Entry(
                title: "D\(index)",
                text: "day",
                createdAt: start.addingTimeInterval(TimeInterval(86_400 * index))
            )
        }
        XCTAssertNil(InsightEngine.valenceTrend(entries: entries, moodLabels: [:], now: start, calendar: calendar))
        var moods: [UUID: [String]] = [:]
        for (index, entry) in entries.enumerated() {
            moods[entry.id] = [index < 3 ? MoodLabel.anxious.rawValue : MoodLabel.hopeful.rawValue]
        }
        let trend = InsightEngine.valenceTrend(
            entries: entries, moodLabels: moods, now: start.addingTimeInterval(86_400 * 6), calendar: calendar
        )
        XCTAssertEqual(trend?.kind, .valenceTrend)
        XCTAssertEqual(trend?.n, 6)
        XCTAssertEqual(trend?.label, "Valence rose")
    }
}
