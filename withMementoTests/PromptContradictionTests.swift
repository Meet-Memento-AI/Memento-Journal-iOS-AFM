import XCTest
@testable import MeetMemento

/// The prompt may never carry journal evidence and an instruction to deny it.
///
/// This is the invariant the cold-start "I don't see anything" reports broke. A
/// journal question whose retrieval found no topical hit still gets the recent
/// entries as ambient background — the prompt carried their full text under the
/// heading "NOTHING HERE MATCHES WHAT THEY ASKED ABOUT … say plainly you don't
/// see anything on that topic", and the model resolved the contradiction by
/// doing both: denying the topic and then paraphrasing the entries anyway.
///
/// Nothing in the suite could see it, because every existing test checks one
/// side — the stance line, or the evidence block — and the defect is only
/// visible in their conjunction.
///
/// Deterministic and model-free, so it runs on every merge.
final class PromptContradictionTests: XCTestCase {

    /// Phrases that tell the model it has nothing. Add to this whenever the
    /// denial copy changes; the test is only as good as this list.
    private static let denials = [
        "you don't see anything",
        "don't see anything on that topic",
        "Say plainly you don't see",
        "NOTHING HERE MATCHES",
        "No journal entries matched",
        "No journal entries in the archive"
        // Not "see nothing": the nearby stance forbids it in those words
        // ("never say you see nothing at all"), and a substring test cannot
        // tell a prohibition from an instruction. `test_nearbyOnlyCopy_neverDenies`
        // pins that line directly instead.
    ]

    private func entry(_ ref: Int) -> RetrievedEntry {
        RetrievedEntry(
            ref: ref, id: UUID(), date: Date(),
            text: "Slept badly three nights running now, wired at two in the morning."
        )
    }

    private func retrieval(ambient: Bool) -> RetrievalResult {
        let entries = [entry(1)]
        return RetrievalResult(
            entries: entries,
            contextBlock: EntryRetriever.contextBlock(for: entries, ambient: ambient),
            isAmbient: ambient
        )
    }

    private func prompt(stance: TurnStance, retrieval: RetrievalResult, channel: ReplyChannel) -> String {
        FoundationModelsIntelligenceService.buildAskPrompt(
            question: "how have I been sleeping?",
            history: [],
            retrieval: retrieval,
            stance: stance,
            shape: .answerOpen,
            archiveEmpty: retrieval.isEmpty,
            budget: ContextBudget(window: .unavailable),
            channel: channel,
            move: nil,
            personalization: .none
        )
    }

    func test_noPrompt_carriesEvidenceAndADenial() {
        let cases: [(String, RetrievalResult)] = [
            ("empty", .empty),
            ("ambient", retrieval(ambient: true)),
            ("grounded", retrieval(ambient: false))
        ]
        for stance in TurnStance.allCases {
            for channel in ReplyChannel.allCases {
                for (label, result) in cases {
                    let text = prompt(stance: stance, retrieval: result, channel: channel)
                    let carriesEvidence = text.contains("[ref 1 |")
                    guard carriesEvidence else { continue }
                    for denial in Self.denials {
                        XCTAssertFalse(
                            text.contains(denial),
                            "\(stance)/\(channel)/\(label): prompt carries evidence and \"\(denial)\""
                        )
                    }
                }
            }
        }
    }

    /// A miss does not quote the nearest entry and then deny it.
    func test_miss_doesNotQuoteNearestEntry() {
        let ambient = prompt(stance: .nearbyOnly, retrieval: retrieval(ambient: true), channel: .notebook)
        XCTAssertFalse(ambient.contains("[ref 1 |"))
        XCTAssertTrue(ambient.contains("I can't find an entry that supports that."))
        XCTAssertFalse(ambient.contains("not an answer"))

        let withNone = prompt(stance: .noMatch, retrieval: .empty, channel: .notebook)
        XCTAssertFalse(withNone.contains("[ref 1 |"))
        XCTAssertTrue(withNone.contains(TurnStance.noMatch.tagPrefix))
    }

    func test_nearbyOnlyCopy_doesNotCiteThenDeny() {
        let line = TurnStance.nearbyOnly.promptLine
        XCTAssertFalse(line.contains("not an answer"))
        XCTAssertFalse(line.contains("closest thing"))
        XCTAssertFalse(line.contains("you don't see anything"))
        let shape = TurnShapeCadence.overlayLine(shape: .answerOpen, stance: .nearbyOnly)
        XCTAssertNotNil(shape)
        XCTAssertFalse(shape?.contains("not-an-answer") ?? true)
        XCTAssertFalse(ConversationalMove.nearestThenAsk.cueLine.contains("don't see"))
    }
}
