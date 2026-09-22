import XCTest
@testable import MeetMemento

/// Spec 050 R4: the model points, the renderer quotes. Every quote on screen
/// is text the pack already held; nothing marker-shaped ever reaches the body.
final class ReplyRendererTests: XCTestCase {

    // MARK: - Fixtures

    private func day(_ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
    }

    private let sleep = "Slept through the night for the first time in weeks. The house was quiet."
    private let work = "Work was loud again today and I left with my jaw still tight."

    private lazy var sleepEntry = RetrievedEntry(ref: 1, id: UUID(), date: day(3, 3), text: sleep)
    private lazy var workEntry = RetrievedEntry(ref: 2, id: UUID(), date: day(3, 9), text: work)

    private func retrieval(_ entries: [RetrievedEntry], ambient: Bool = false) -> RetrievalResult {
        RetrievalResult(
            entries: entries,
            contextBlock: EntryRetriever.contextBlock(for: entries, ambient: ambient),
            isAmbient: ambient
        )
    }

    private func matchedPack() -> EvidencePack {
        EvidencePackBuilder.build(
            retrieval: retrieval([sleepEntry, workEntry]), stance: .journalGrounded, channel: .notebook
        )
    }

    private func ambientPack() -> EvidencePack {
        EvidencePackBuilder.build(
            retrieval: retrieval([sleepEntry, workEntry], ambient: true), stance: .followupThread, channel: .thread
        )
    }

    private var sleepQuote: String { "Slept through the night for the first time in weeks." }
    private var march3: String { EntryRetriever.formattedDate(day(3, 3)) }

    private func render(_ raw: String, _ pack: EvidencePack, context: RenderContext = .empty) -> RenderedReply {
        ReplyRenderer.render(raw, pack: pack, context: context)
    }

    private func italicSpans(_ body: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)([^*\n]+?)(?<!\*)\*(?!\*)"#)
        let ns = body as NSString
        return regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    // MARK: - Expansion

    func test_expandsQuoteAndDate_fromThePack() {
        let pack = matchedPack()
        let raw = "You finally got some rest.\n\n### {{date:1}}\n{{quote:1}}\n\nThe quiet came back. What changed that week?"
        let rendered = render(raw, pack)

        XCTAssertTrue(rendered.body.contains("### \(march3)"))
        XCTAssertTrue(rendered.body.contains("*\(sleepQuote)*"))
        XCTAssertFalse(rendered.body.contains("{{"))
        XCTAssertEqual(rendered.chips.map(\.quoteText), [sleepQuote])
        XCTAssertEqual(rendered.chips.first?.entryId, sleepEntry.id)
        XCTAssertEqual(rendered.citations, [sleepEntry.id])
        XCTAssertEqual(rendered.expandedSlotIndexes, [1])
        XCTAssertEqual(rendered.stats.expandedQuoteSlots, [1])
        XCTAssertEqual(rendered.stats.expandedDateSlots, [1])
        XCTAssertEqual(rendered.droppedUnknownMarkerCount, 0)
    }

    /// I4: an expansion is the pack's text byte for byte.
    func test_everyItalicSpan_isAnExpansionOfItsSlot() {
        let pack = matchedPack()
        let rendered = render("On {{date:2}} it was {{quote:2}} Then {{quote:1}} What now?", pack)
        let spans = italicSpans(rendered.body)
        XCTAssertEqual(spans, [work, sleepQuote])
        XCTAssertEqual(rendered.citations, [workEntry.id, sleepEntry.id])
    }

    func test_outOfRangeUnknownAndUnfilledMarkers_areDropped() {
        let pack = matchedPack()
        let rendered = render("Here {{quote:9}} and {{entry:1}} and {{quote:N}} and {{date:0}}. What next?", pack)
        XCTAssertFalse(rendered.body.contains("{"))
        XCTAssertFalse(rendered.body.contains("}"))
        XCTAssertEqual(rendered.droppedUnknownMarkerCount, 4)
        XCTAssertTrue(rendered.chips.isEmpty)
        XCTAssertEqual(rendered.body, "Here and and and. What next?")
    }

    func test_lenientMarkerSpelling_stillResolves() {
        let pack = matchedPack()
        let rendered = render("{{ Quote : 1 }} and {date:2}. What next?", pack)
        XCTAssertTrue(rendered.body.contains("*\(sleepQuote)*"))
        XCTAssertTrue(rendered.body.contains(EntryRetriever.formattedDate(day(3, 9))))
        XCTAssertEqual(rendered.droppedUnknownMarkerCount, 0)
    }

    func test_markerWrappedInItalicsOrQuotes_isWrappedOnce() {
        let pack = matchedPack()
        for raw in ["*{{quote:1}}*", "“{{quote:1}}”", "\"{{quote:1}}\"", "_{{quote:1}}_", "**{{quote:1}}**"] {
            let body = render(raw + " What changed?", pack).body
            XCTAssertEqual(body, "*\(sleepQuote)* What changed?", raw)
        }
        let dated = render("### **{{date:1}}**\n{{quote:1}}", pack).body
        XCTAssertTrue(dated.hasPrefix("### \(march3)\n"), dated)
    }

    func test_sameQuoteTwice_isShownOnce() {
        let pack = matchedPack()
        let rendered = render("{{quote:1}} Again: {{quote:1}} What now?", pack)
        XCTAssertEqual(italicSpans(rendered.body), [sleepQuote])
        XCTAssertEqual(rendered.stats.droppedDuplicateQuoteCount, 1)
        XCTAssertEqual(rendered.chips.count, 1)
    }

    func test_clippedQuote_showsAnEllipsis_andTheChipMirrorsIt() {
        let runOn = String(repeating: "and then we walked along the water ", count: 8)
            .trimmingCharacters(in: .whitespaces)
        let entry = RetrievedEntry(ref: 1, id: UUID(), date: day(4, 1), text: runOn)
        let pack = EvidencePackBuilder.build(retrieval: retrieval([entry]), stance: .journalGrounded, channel: .notebook)
        let rendered = render("{{quote:1}} What stayed with you?", pack)
        let quote = pack.slot(1)?.quoteText ?? "<nil>"
        XCTAssertTrue(rendered.body.hasPrefix("*\(quote)…*"))
        XCTAssertEqual(rendered.chips.first?.quoteText, quote + "…")
    }

    // MARK: - Pack states

    func test_markersOnANonePack_areAllDropped() {
        let raw = "I can't find an entry that supports that. {{quote:1}} {{date:1}} What's on your mind?"
        let rendered = render(raw, .empty)
        XCTAssertEqual(rendered.body, "I can't find an entry that supports that. What's on your mind?")
        XCTAssertTrue(rendered.chips.isEmpty)
        XCTAssertTrue(rendered.citations.isEmpty)
        XCTAssertEqual(rendered.droppedUnknownMarkerCount, 2)
    }

    func test_ambientPack_hasNoChips_andDropsQuoteMarkers() {
        let rendered = render("Lately it has been work. {{quote:1}} On {{date:1}}, too. What stands out?", ambientPack())
        XCTAssertTrue(rendered.chips.isEmpty)
        XCTAssertTrue(rendered.citations.isEmpty)
        XCTAssertFalse(rendered.body.contains("{"))
        XCTAssertTrue(italicSpans(rendered.body).isEmpty)
    }

    func test_statMarker_expandsOnlyFromStats() {
        let base = matchedPack()
        let withStats = EvidencePack(
            state: base.state,
            slots: base.slots,
            contextDates: base.contextDates,
            stats: [StatSlot(id: "weekday", kind: "weekday", label: "Mondays", spokenMagnitude: "several")],
            retrievalWasEmpty: false,
            retrievalWasAmbient: false
        )
        XCTAssertEqual(render("It came up {{stat:weekday}} times. Why Mondays?", withStats).body,
                       "It came up several times. Why Mondays?")
        XCTAssertEqual(render("It came up {{stat:weekday}} times. Why?", base).body, "It came up times. Why?")
    }

    // MARK: - Unmarked emphasis and leaks

    func test_unmarkedItalics_areUnwrapped() {
        let rendered = render("That *really stayed with you* this week. _Quietly_, too. What now?", matchedPack())
        XCTAssertEqual(rendered.body, "That really stayed with you this week. Quietly, too. What now?")
        XCTAssertEqual(rendered.strippedItalicCount, 2)
    }

    func test_boldIsNotItalic_andSurvivesTheItalicPass() {
        let rendered = render("It was **the house was quiet** that week. What now?", matchedPack())
        XCTAssertTrue(rendered.body.contains("**the house was quiet**"))
        XCTAssertEqual(rendered.strippedItalicCount, 0)
    }

    func test_referenceMarkersAndBraceJunk_neverReachTheBody() {
        let rendered = render("You slept better [ref 1]. {{ }} Then } { it rained. citedRefs: [1]", matchedPack())
        XCTAssertFalse(rendered.body.contains("ref 1"))
        XCTAssertFalse(rendered.body.contains("{"))
        XCTAssertFalse(rendered.body.contains("}"))
        XCTAssertFalse(rendered.body.contains("citedRefs"))
    }

    /// I1: no marker and no placeholder character survives, whatever the model wrote.
    func test_bodyNeverCarriesMarkersOrPlaceholders() {
        let pack = matchedPack()
        let inputs = [
            "{{quote:1", "{{quote:1}}}", "{{{{date:2}}}}", "**{{quote:2}}", "{{quote:1}}{{quote:1}}",
            "\u{E002}\u{E100}\u{E001} leaked", "### {{date:9}}", "{{stat:}}", "{quote}", "}}{{"
        ]
        for raw in inputs {
            let body = render(raw + " What now?", pack).body
            XCTAssertFalse(body.contains("{{") || body.contains("}}"), raw)
            XCTAssertFalse(body.unicodeScalars.contains { (0xE000...0xE7FF).contains($0.value) }, raw)
        }
    }

    func test_headingEmptiedByADroppedMarker_isRemoved() {
        let rendered = render("Here is the moment.\n### {{date:9}}\n\nWhat now?", matchedPack())
        XCTAssertFalse(rendered.body.contains("###"))
        XCTAssertEqual(rendered.stats.droppedHeadingCount, 1)
    }

    // MARK: - Streaming (R5)

    func test_sentencePrefix_holdsTheSentenceStillGrowing() {
        let prefix = { ReplyRenderer.stablePrefix(of: $0, granularity: .sentence) }
        XCTAssertEqual(prefix("You finally slept. The quiet came"), "You finally slept.")
        XCTAssertEqual(prefix("You finally slept."), "", "a terminator with nothing after it may still grow")
        XCTAssertEqual(prefix("You finally slept. "), "You finally slept.")
        XCTAssertEqual(prefix("### {{date:1}}\n{{quote:1}}\n\nThe climb"), "### {{date:1}}\n{{quote:1}}\n\n")
        XCTAssertEqual(prefix("It was *quiet.* Then"), "It was *quiet.*")
    }

    /// Sentence granularity holds the whole sentence an open construct sits
    /// in; word granularity holds from the construct itself.
    func test_stablePrefix_neverCutsInsideAMarkerItalicOrQuotation() {
        let expected: [ReplyRenderer.StreamGranularity: String] = [.sentence: "You slept.", .word: "You slept. Then"]
        for (granularity, settled) in expected {
            let prefix = { ReplyRenderer.stablePrefix(of: $0, granularity: granularity) }
            XCTAssertEqual(prefix("You slept. Then {{quo"), settled, "\(granularity)")
            XCTAssertEqual(prefix("You slept. Then *I finally felt"), settled, "\(granularity)")
            XCTAssertEqual(prefix("You slept. Then “I finally felt"), settled, "\(granularity)")
            XCTAssertEqual(prefix("You slept. Then **the quiet"), settled, "\(granularity)")
        }
    }

    func test_wordPrefix_holdsAPartialWordAndADateStillArriving() {
        let prefix = { ReplyRenderer.stablePrefix(of: $0, granularity: .word) }
        XCTAssertEqual(prefix("Hey there, how are y"), "Hey there, how are")
        XCTAssertEqual(prefix("Hey there, how are you "), "Hey there, how are you ")
        XCTAssertEqual(prefix("That was back in March"), "That was back in", "a word still growing")
        XCTAssertEqual(prefix("That was back in March 3, "), "That was back in ", "a date still growing")
        XCTAssertEqual(prefix("That was back in March 3, 2026, and then the rest "),
                       "That was back in March 3, 2026, and then the rest ")
    }

    /// I1 on the stream: every delta a person could see or hear is rendered
    /// text, and each one is where the final reply begins.
    func test_streamingBodies_neverShowMarkersOrUnverifiedItalics_andGrowIntoTheFinal() {
        let pack = matchedPack()
        let raw = "You finally got some rest. *I felt light for once.* \n\n### {{date:1}}\n{{quote:1}}\n\n"
            + "The quiet came back on {{date:1}}. What changed that week?"
        let final = ReplyRenderer.render(raw, pack: pack).body
        var previous = ""
        for end in raw.indices {
            let partial = String(raw[..<end])
            let body = ReplyRenderer.streamingBody(partial, pack: pack, context: .empty, granularity: .sentence)
            XCTAssertFalse(body.contains("{") || body.contains("}"), partial)
            XCTAssertFalse(body.unicodeScalars.contains { (0xE000...0xE7FF).contains($0.value) }, partial)
            for span in italicSpans(body) {
                XCTAssertEqual(span, sleepQuote, "only the pack's quote is ever italic: \(partial)")
            }
            XCTAssertTrue(final.hasPrefix(body), "delta is not a prefix of the final: \(body)")
            XCTAssertGreaterThanOrEqual(body.count, previous.count, "sentence deltas never retract")
            previous = body
        }
    }

    // MARK: - Citations (R5)

    func test_citations_leadWithWhatTheBodyShows_andOnlyOnAMatchedPack() {
        let rows = retrieval([sleepEntry, workEntry])
        let pack = matchedPack()
        let rendered = render("On {{date:2}} it was loud. {{quote:1}} What now?", pack)
        let citations = CitationReconciliation.citations(
            for: rendered, pack: pack, citedRefs: [1], retrieval: rows, question: "how was work"
        )
        XCTAssertEqual(citations.map(\.entryId), [workEntry.id, sleepEntry.id])

        for other in [ambientPack(), EvidencePack.empty] {
            let shown = render("Lately work. What now?", other)
            XCTAssertTrue(CitationReconciliation.citations(
                for: shown, pack: other, citedRefs: [1, 2], retrieval: rows, question: "work"
            ).isEmpty, "\(other.state) must not cite")
        }
    }

    // MARK: - Empty results

    func test_replyThatRendersToNothing_usesTheFallback_onlyWhenFinal() {
        let final = ReplyRenderer.render("{{quote:9}}", pack: matchedPack())
        XCTAssertEqual(final.body, ReplyRenderer.emptyFallback)
        XCTAssertTrue(final.stats.usedFallback)
        XCTAssertTrue(final.chips.isEmpty)

        let partial = ReplyRenderer.render("{{quote:9}}", pack: matchedPack(), isFinal: false)
        XCTAssertEqual(partial.body, "")

        XCTAssertEqual(ReplyRenderer.render("   ", pack: matchedPack()).body, "", "an empty reply stays empty")
    }
}
