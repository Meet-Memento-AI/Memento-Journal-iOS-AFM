import XCTest
@testable import withMemento

/// The model has no clock, so the prompt has to carry one.
///
/// Without a date anchor, "what did I write last Tuesday?" is unanswerable:
/// the context block holds absolute dates (`[ref 1 | March 12, 2026]`) and the
/// question holds a relative one, and nothing in the prompt connects them. The
/// model fills the gap by inventing.
///
/// Measured over the 2026-09-20 study (3,119 generated replies): 90 asserted a
/// specific date, and 14 of those were on the arm with **no journal at all** —
/// including "I don't see anything from that stretch — the entry from March 12
/// shows a spike in missed classes", which invents a dated entry in the same
/// sentence that admits there are none.
///
/// Retrieval was already date-aware (`QueryDateWindowParser.parse(_, now:)`);
/// only the model was left guessing.
final class PromptDateAnchorTests: XCTestCase {

    private func assembled(
        question: String,
        channel: ReplyChannel,
        stance: TurnStance,
        archiveEmpty: Bool = false
    ) -> String {
        let retrieval = RetrievalResult(
            entries: [RetrievedEntry(ref: 1, id: UUID(), date: Date(), text: "work was hard")],
            contextBlock: "[ref 1 | March 12, 2026] work was hard",
            isAmbient: false
        )
        return FoundationModelsIntelligenceService.buildAskPrompt(
            question: question,
            history: [],
            retrieval: retrieval,
            stance: stance,
            shape: .answerOpen,
            archiveEmpty: archiveEmpty,
            budget: ContextBudget(window: .unavailable),
            channel: channel,
            move: .reflectAndAsk
        )
    }

    func test_todayLine_carriesWeekdayAndMatchesEntryDateFormat() {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 12
        let date = Calendar(identifier: .gregorian).date(from: components)!

        XCTAssertEqual(
            FoundationModelsIntelligenceService.todayLine(now: date),
            "[Today: Thursday, March 12, 2026]"
        )
    }

    /// The weekday is the part that makes "last Tuesday" resolvable at all.
    func test_todayLine_includesTheWeekday() {
        let line = FoundationModelsIntelligenceService.todayLine()
        let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday",
                        "Friday", "Saturday", "Sunday"]
        XCTAssertTrue(weekdays.contains { line.contains($0) },
                      "no weekday in \(line) — a relative weekday stays uncomputable")
    }

    /// The date in the anchor must be formatted the same way as the dates on
    /// the entries, or the model is comparing two different notations.
    func test_todayLine_usesTheSameDateFormatAsEntries() {
        let date = Date()
        let line = FoundationModelsIntelligenceService.todayLine(now: date)
        XCTAssertTrue(line.contains(EntryRetriever.formattedDate(date)),
                      "\(line) does not contain \(EntryRetriever.formattedDate(date))")
    }

    func test_notebookPrompt_carriesTheDateAnchor() {
        let prompt = assembled(
            question: "what did I write last Tuesday?",
            channel: .notebook,
            stance: .journalGrounded
        )
        XCTAssertTrue(prompt.contains("[Today: "), "notebook prompt has no clock")
    }

    /// The short assembler talks about "today" and "yesterday" constantly, so it
    /// needs the anchor too.
    func test_companionPrompt_carriesTheDateAnchor() {
        let prompt = assembled(
            question: "rough day",
            channel: .companion,
            stance: .sharing
        )
        XCTAssertTrue(prompt.contains("[Today: "), "companion prompt has no clock")
    }

    /// An empty archive is where the invented dates were worst — the anchor has
    /// to be there even when there is nothing to cite.
    func test_emptyArchivePrompt_stillCarriesTheDateAnchor() {
        let prompt = assembled(
            question: "what did I write last Tuesday?",
            channel: .notebook,
            stance: .noMatch,
            archiveEmpty: true
        )
        XCTAssertTrue(prompt.contains("[Today: "), "empty-archive prompt has no clock")
    }
}
