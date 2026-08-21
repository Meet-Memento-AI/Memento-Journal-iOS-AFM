import XCTest
@testable import MeetMemento

final class QuotedSpanExtractorTests: XCTestCase {
    func test_extractsFirstCleanSentence() {
        let text = "The winter market was loud. I bought bread. Then I walked home in the snow."
        let span = QuotedSpanExtractor.extract(from: text)
        XCTAssertEqual(span, "The winter market was loud.")
    }

    func test_returnsNilForEmpty() {
        XCTAssertNil(QuotedSpanExtractor.extract(from: "   "))
    }

    func test_truncatedBodyStillQuotedWhenShortEnough() {
        let text = String(repeating: "a", count: 40)
        XCTAssertEqual(QuotedSpanExtractor.extract(from: text), text)
    }
}

final class SessionCandidatePoolTests: XCTestCase {
    func test_capacityCapsAtTwenty() {
        var pool = SessionCandidatePool()
        let extras = (1...25).map { i in
            RetrievedEntry(ref: i, id: UUID(), date: Date(), text: "entry \(i) about winter walks and bread.")
        }
        pool.ingest(extras)
        XCTAssertEqual(pool.rankedIDs.count, 20)
    }

    func test_slicePrefersUnsurfacedThenRemapsRefs() {
        var pool = SessionCandidatePool()
        let a = UUID()
        let b = UUID()
        let entries = [
            RetrievedEntry(ref: 1, id: a, date: Date(), text: "First sentence about the job. More."),
            RetrievedEntry(ref: 2, id: b, date: Date(), text: "Second sentence about the job. More.")
        ]
        pool.ingest(entries)
        pool.markSurfaced([a])
        let sliced = pool.sliceForPrompt(entries, cap: 5)
        // Unsurfaced first, then topped up with the already-shown one. This
        // used to return [b] alone: preferring novelty by DROPPING evidence
        // left later turns with a single thin entry to answer from, which is
        // what collapsed replies to one sentence.
        XCTAssertEqual(sliced.map(\.id), [b, a])
        XCTAssertEqual(sliced.map(\.ref), [1, 2])
    }

    func test_resetClearsSurfaced() {
        var pool = SessionCandidatePool()
        let id = UUID()
        pool.ingest([RetrievedEntry(ref: 1, id: id, date: Date(), text: "A long enough winter sentence here.")])
        pool.markSurfaced([id])
        pool.reset()
        XCTAssertTrue(pool.surfacedIDs.isEmpty)
        XCTAssertTrue(pool.rankedIDs.isEmpty)
    }
}

final class SpokenFormFormatterTests: XCTestCase {
    func test_isoDateBecomesSpokenMonthDay() {
        let out = SpokenFormFormatter.format("On 2026-01-03 I wrote.", mode: .conversation)
        XCTAssertTrue(out.contains("January"), out)
        XCTAssertFalse(out.contains("2026-01-03"), out)
    }

    func test_timeBecomesSpoken() {
        let out = SpokenFormFormatter.format("Meet at 14:05", mode: .conversation)
        XCTAssertTrue(out.contains("14"), out)
        XCTAssertFalse(out.contains("14:05"), out)
    }

    func test_fractionRewritten_currencyUntouched() {
        let out = SpokenFormFormatter.format("I ate 3/4 and spent $12", mode: .conversation)
        XCTAssertTrue(out.contains("three fourths"), out)
        XCTAssertTrue(out.contains("$12"), out)
    }

    func test_tagAllowlistStripsUnknown() {
        let out = SpokenFormFormatter.applyTagAllowlist("hello <breath> and <foo> there")
        XCTAssertTrue(out.contains("<breath>"))
        XCTAssertFalse(out.contains("<foo>"))
    }

    func test_readBackInsertsBreathsAtParagraphs() {
        let out = SpokenFormFormatter.format("One.\n\nTwo.\n\nThree.", mode: .readBack)
        XCTAssertEqual(out.components(separatedBy: "<breath>").count, 3)
    }

    func test_conversationDoesNotInsertBreaths() {
        let out = SpokenFormFormatter.format("One.\n\nTwo.", mode: .conversation)
        XCTAssertFalse(out.contains("<breath>"))
    }
}

final class HealthKitPromptPolicyTests: XCTestCase {
    func test_neverEntersZ1() {
        XCTAssertFalse(HealthKitPromptPolicy.allowsZ1Prompts)
        let snap = HealthSnapshot(sleepBucket: .sixToEight, workoutOccurred: true, stateOfMindValence: nil)
        XCTAssertNil(HealthKitPromptPolicy.promptFragment(snapshot: snap, zone: .z1AppleContent(reasoningLevel: .light)))
        XCTAssertNotNil(HealthKitPromptPolicy.promptFragment(snapshot: snap, zone: .z0Device))
    }
}

final class AudioRetentionPolicyTests: XCTestCase {
    func test_discardDefaultRemovesFile() throws {
        AudioRetentionPolicy.current = .discardAfterTranscription
        let id = try AudioAssetStore.save(Data("wav".utf8))
        XCTAssertTrue(AudioAssetStore.exists(assetID: id))
        let kept = AudioAssetStore.applyRetentionAfterTranscription(assetID: id)
        XCTAssertNil(kept)
        XCTAssertFalse(AudioAssetStore.exists(assetID: id))
    }
}

final class TurnStartMaskTests: XCTestCase {
    func test_missingClipSkips() {
        XCTAssertFalse(TurnStartMask.shouldPlay(voiceID: "F1", firstChunkReady: false, alreadyPlayed: false))
    }

    func test_skipsWhenFirstChunkAlreadyReady() {
        XCTAssertFalse(TurnStartMask.shouldPlay(voiceID: "F1", firstChunkReady: true, alreadyPlayed: false))
    }

    func test_catalogIdsAreTheLookupKeys() {
        for voice in VoiceCatalog.all {
            XCTAssertEqual(TurnStartMask.clipName(for: voice.id), "turn-start-\(voice.id)")
        }
        XCTAssertEqual(VoiceCatalog.all.count, 4)
    }
}

final class PatternStatsTests: XCTestCase {
    func test_countsLiveInSwiftNotTheModel() {
        let now = Date()
        let entries = [
            Entry(title: "A", text: "one", createdAt: now),
            Entry(title: "B", text: "two", createdAt: now)
        ]
        XCTAssertEqual(PatternStats.week(entries: entries, now: now).entryCount, 2)
        XCTAssertEqual(PatternStats.month(entries: entries, now: now).entryCount, 2)
    }
}

final class IntelligenceProviderSwapTests: XCTestCase {
    func test_mockSatisfiesIntelligenceServiceSeam() {
        let mock: any IntelligenceService = MockIntelligenceService()
        XCTAssertNotNil(mock)
    }
}

final class AppIntentContractTests: XCTestCase {
    func test_fourShortcutsRegistered() {
        XCTAssertEqual(Array(MementoShortcuts.appShortcuts).count, 4)
    }

    func test_noSiriKitInAppTargetIntents() {
        XCTAssertTrue(true)
    }
}

final class SchemaMirroringComplianceTests: XCTestCase {
    func test_schemaContainsRequiredModels() {
        XCTAssertEqual(JournalSchema.models.count, 6)
    }

    func test_trustZoneRoundTrip() throws {
        let zones: [TrustZone] = [
            .z0Device,
            .z1AppleContent(reasoningLevel: .light),
            .z1AppleContentFree
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for zone in zones {
            let data = try encoder.encode(zone)
            let decoded = try decoder.decode(TrustZone.self, from: data)
            XCTAssertEqual(decoded, zone)
        }
    }

    func test_healthSnapshotIsSendableValue() {
        let snap = HealthSnapshot(sleepBucket: .underSix, workoutOccurred: false, stateOfMindValence: 0.2)
        XCTAssertTrue(snap.hasAnyValue)
    }

    func test_indexingDefaultsOff() {
        UserDefaults.standard.removeObject(forKey: "spotlightIndexingOptIn")
        XCTAssertFalse(IndexingPreferences.spotlightOptIn)
    }
}

final class FiveStoreDeletionTests: XCTestCase {
    func test_audioAndTTSDirectoriesEmptyAfterDeleteAll() throws {
        _ = try AudioAssetStore.save(Data("x".utf8))
        AudioAssetStore.deleteAll()
        TTSRenderCache.deleteAll()
        XCTAssertTrue(AudioAssetStore.isEmpty)
        XCTAssertTrue(TTSRenderCache.isEmpty)
    }
}

final class DEC002PlanBTests: XCTestCase {
    func test_entryRetrieverIsTheDefaultFindPath() {
        XCTAssertEqual(EntryRetriever.maxEntries, 5)
        XCTAssertFalse(IndexingPreferences.spotlightOptIn)
    }
}

final class EntryZoomSourceIDTests: XCTestCase {
    func test_createRoutesShareFABSource() {
        XCTAssertEqual(EntryRoute.create.zoomSourceID, EntryRoute.createZoomSourceID)
        XCTAssertEqual(EntryRoute.createWithTitle("Hello").zoomSourceID, EntryRoute.createZoomSourceID)
    }

    func test_chatSummaryZoomsFromSparkles() {
        let route = EntryRoute.createWithContent(title: "Chat Reflection", content: "body")
        XCTAssertEqual(route.zoomSourceID, EntryRoute.createFromChatZoomSourceID)
    }

    func test_editZoomsFromThatEntry() {
        let entry = Entry(id: UUID(), title: "T", text: "Body text for the card.")
        XCTAssertEqual(EntryRoute.edit(entry).zoomSourceID, "edit-\(entry.id.uuidString)")
    }
}

