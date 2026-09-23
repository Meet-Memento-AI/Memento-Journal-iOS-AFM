import XCTest
@testable import withMemento

/// Spec 050 R1: the pack mirrors what the prompt carries, and every quote in
/// it is a span Swift already had.
final class EvidencePackBuilderTests: XCTestCase {

    private func day(_ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private func entry(_ ref: Int, _ text: String, quotedSpan: String? = nil,
                       date: Date? = nil) -> RetrievedEntry {
        RetrievedEntry(ref: ref, id: UUID(), date: date ?? day(3, ref), text: text, quotedSpan: quotedSpan)
    }

    private func retrieval(_ entries: [RetrievedEntry], ambient: Bool = false) -> RetrievalResult {
        RetrievalResult(
            entries: entries,
            contextBlock: EntryRetriever.contextBlock(for: entries, ambient: ambient),
            isAmbient: ambient
        )
    }

    private let sleep = "Slept through the night for the first time in weeks. The house was quiet."
    private let work = "Work was loud again today and I left with my jaw still tight."

    // MARK: - State

    func test_emptyRetrieval_isNone() {
        let pack = EvidencePackBuilder.build(retrieval: .empty, stance: .journalGrounded, channel: .notebook)
        XCTAssertEqual(pack.state, .none)
        XCTAssertTrue(pack.slots.isEmpty)
        XCTAssertTrue(pack.contextDates.isEmpty)
        XCTAssertTrue(pack.retrievalWasEmpty)
        XCTAssertFalse(pack.carriesEvidence)
    }

    func test_channelThatDoesNotRetrieve_isNone_evenWithRows() {
        let rows = retrieval([entry(1, sleep)])
        for channel in [ReplyChannel.companion, .phatic, .continuer, .meta, .redirect, .statistic] {
            let pack = EvidencePackBuilder.build(retrieval: rows, stance: .sharing, channel: channel)
            XCTAssertEqual(pack.state, .none, "\(channel)")
            XCTAssertTrue(pack.slots.isEmpty, "\(channel)")
        }
    }

    /// A miss never exposes a slot, even when defensive paths still attach rows.
    func test_missStances_forceNone_evenWithRows() {
        let rows = retrieval([entry(1, sleep), entry(2, work)])
        for stance in [TurnStance.noMatch, .nearbyOnly] {
            let pack = EvidencePackBuilder.build(retrieval: rows, stance: stance, channel: .notebook)
            XCTAssertEqual(pack.state, .none, "\(stance)")
            XCTAssertTrue(pack.slots.isEmpty, "\(stance)")
            XCTAssertFalse(pack.retrievalWasEmpty)
        }
        let emptyArchive = EvidencePackBuilder.build(
            retrieval: rows, stance: .journalGrounded, channel: .notebook, archiveEmpty: true
        )
        XCTAssertEqual(emptyArchive.state, .none)
    }

    func test_ambient_hasNoSlots_butKeepsTheShippedDates() {
        let rows = retrieval([entry(1, sleep), entry(2, work)], ambient: true)
        for stance in [TurnStance.journalGrounded, .followupThread] {
            let pack = EvidencePackBuilder.build(retrieval: rows, stance: stance, channel: .thread)
            XCTAssertEqual(pack.state, .ambient, "\(stance)")
            XCTAssertTrue(pack.slots.isEmpty, "ambient rows are background, never citations")
            XCTAssertEqual(pack.contextDates, rows.entries.map(\.date))
            XCTAssertTrue(pack.retrievalWasAmbient)
            XCTAssertTrue(pack.carriesEvidence)
        }
    }

    // MARK: - Slots

    func test_matched_slotsMirrorRefs_andEveryQuoteIsVerbatim() {
        let rows = retrieval([entry(1, sleep), entry(2, work)])
        let pack = EvidencePackBuilder.build(retrieval: rows, stance: .journalGrounded, channel: .notebook)
        XCTAssertEqual(pack.state, .matched)
        XCTAssertEqual(pack.slots.map(\.index), [1, 2])
        XCTAssertEqual(pack.slots.map(\.entryId), rows.entries.map(\.id))
        for slot in pack.slots {
            let quote = try? XCTUnwrap(slot.quoteText)
            XCTAssertNotNil(quote)
            XCTAssertTrue(slot.passageText.contains(quote ?? "<nil>"), "slot \(slot.index)")
            XCTAssertEqual(slot.displayDate, EntryRetriever.formattedDate(slot.date))
        }
        XCTAssertEqual(pack.slot(1)?.quoteText, "Slept through the night for the first time in weeks.")
        XCTAssertNil(pack.slot(3))
    }

    func test_threadWithGroundedRetrieval_isMatched() {
        let rows = retrieval([entry(1, sleep)])
        let pack = EvidencePackBuilder.build(retrieval: rows, stance: .followupThread, channel: .thread)
        XCTAssertEqual(pack.state, .matched)
        XCTAssertEqual(pack.slots.count, 1)
    }

    func test_quotedSpanThatIsNotInTheText_isRejected_andTheNextCandidateUsed() {
        let bad = entry(1, sleep, quotedSpan: "I felt light for the first time in months.")
        let slot = EvidencePackBuilder.slot(for: bad)
        XCTAssertEqual(slot.quoteText, "Slept through the night for the first time in weeks.")
        XCTAssertTrue(sleep.contains(slot.quoteText ?? "<nil>"))
    }

    func test_spanWithMarkdownOrMarkerCharacters_isNeverAQuote() {
        let text = "I wrote {{quote:2}} in the margin as a joke today. The *rest* was ordinary."
        let slot = EvidencePackBuilder.slot(for: entry(1, text))
        XCTAssertNil(slot.quoteText, "a span that could break the wrapper or the grammar is not quotable")
        XCTAssertEqual(slot.displayDate, EntryRetriever.formattedDate(slot.date), "still dateable")

        let mixed = "Some *days* are loud. The walk home along the river was quiet and slow."
        XCTAssertEqual(EvidencePackBuilder.slot(for: entry(2, mixed)).quoteText,
                       "The walk home along the river was quiet and slow.")
    }

    func test_clippedSpan_endsOnAWordBoundary_andIsFlagged() {
        let runOn = String(repeating: "and then we walked along the water ", count: 8)
            .trimmingCharacters(in: .whitespaces)
        let slot = EvidencePackBuilder.slot(for: entry(1, runOn))
        let quote = try? XCTUnwrap(slot.quoteText)
        XCTAssertTrue(slot.quoteIsClipped)
        XCTAssertTrue(runOn.contains(quote ?? "<nil>"))
        XCTAssertLessThanOrEqual(quote?.count ?? .max, QuotedSpanExtractor.maxChars)
        XCTAssertFalse(quote?.hasSuffix(" ") ?? true)
        let nextIndex = runOn.range(of: quote ?? "")?.upperBound
        XCTAssertEqual(nextIndex.map { runOn[$0] }, " ", "the span ends on a whole word")
    }

    func test_wholeSentenceQuote_isNotClipped() {
        let slot = EvidencePackBuilder.slot(for: entry(1, work))
        XCTAssertEqual(slot.quoteText, work)
        XCTAssertFalse(slot.quoteIsClipped)
    }

    // MARK: - Legend (R2)

    func test_matchedLegend_listsEachSlotsExactWordsBesideItsMarkers() {
        let date = day(3, 3)
        let rows = retrieval([entry(1, sleep, date: date), entry(2, "{{quote:9}} broke the grammar today.")])
        let pack = EvidencePackBuilder.build(retrieval: rows, stance: .journalGrounded, channel: .notebook)
        let legend = pack.promptLegend(channel: .notebook) ?? ""
        XCTAssertTrue(legend.hasPrefix("[Evidence]\n"))
        XCTAssertTrue(legend.contains(
            "1. {{date:1}} = \(EntryRetriever.formattedDate(date)) · {{quote:1}} = \"Slept through the night for the first time in weeks.\""
        ))
        XCTAssertTrue(legend.contains("2. {{date:2}} = "))
        XCTAssertTrue(legend.contains("· no quote"), "an unquotable slot offers its date only")
        XCTAssertFalse(legend.contains("{{quote:2}}"))
        XCTAssertTrue(legend.hasSuffix(EvidencePack.legendFooter))
    }

    func test_legendNotes_forAmbientAndNone_andNothingOnLightChannels() {
        let ambient = EvidencePackBuilder.build(
            retrieval: retrieval([entry(1, sleep)], ambient: true), stance: .journalGrounded, channel: .notebook
        )
        XCTAssertEqual(ambient.promptLegend(channel: .notebook), EvidencePack.ambientNote)
        XCTAssertFalse(EvidencePack.ambientNote.contains("{{quote:"))
        XCTAssertEqual(EvidencePack.empty.promptLegend(channel: .thread), EvidencePack.noneNote)
        for channel in [ReplyChannel.phatic, .continuer, .companion, .meta, .redirect, .statistic] {
            XCTAssertNil(EvidencePack.empty.promptLegend(channel: channel), "\(channel)")
        }
    }

    func test_promptContextBlock_dropsQuotedLines_keepsRefLines() {
        let rows = retrieval([entry(1, sleep), entry(2, work)])
        XCTAssertTrue(rows.contextBlock.contains("quoted: \""), "fixture sanity")
        let block = EvidencePack.promptContextBlock(rows.contextBlock)
        XCTAssertFalse(block.contains("quoted: \""))
        XCTAssertTrue(block.contains("[ref 1 | \(EntryRetriever.formattedDate(rows.entries[0].date))] \(sleep)"))
        XCTAssertTrue(block.contains("[ref 2 |"))
        XCTAssertTrue(block.contains("[End of journal context]"))
    }

    func test_exactLadderLine_pointsAtTheFirstSlot_andNeverPastesText() {
        let rows = retrieval([entry(1, sleep)])
        let pack = EvidencePackBuilder.build(retrieval: rows, stance: .journalGrounded, channel: .notebook)
        XCTAssertEqual(EvidenceLadder.promptLine(.exact, retrieval: rows, pack: pack),
                       "One entry answers this: {{date:1}} {{quote:1}}.")
        XCTAssertEqual(EvidenceLadder.promptLine(.exact, retrieval: rows), "One entry is about this.")
        XCTAssertEqual(EvidenceLadder.promptLine(.exact, retrieval: .empty), "One entry may be what you mean.")
        XCTAssertFalse(EvidenceLadder.promptLine(.exact, retrieval: rows).contains("Slept"))
        XCTAssertEqual(EvidenceLadder.promptLine(.none, retrieval: .empty), "I can't find an entry that supports that.")
    }

    // MARK: - Extractor reuse

    func test_extractorCandidates_areContiguousAndInOrder_andExtractIsUnchanged() {
        let text = "Short. Slept through the night for the first time in weeks. Work was loud again today."
        let candidates = QuotedSpanExtractor.candidates(from: text)
        XCTAssertEqual(candidates, [
            "Slept through the night for the first time in weeks.",
            "Work was loud again today."
        ])
        XCTAssertTrue(candidates.allSatisfy { text.contains($0) })
        XCTAssertEqual(QuotedSpanExtractor.extract(from: text), candidates.first)
        XCTAssertEqual(QuotedSpanExtractor.extract(from: "tiny"), "tiny", "short text falls back to itself")
    }
}
