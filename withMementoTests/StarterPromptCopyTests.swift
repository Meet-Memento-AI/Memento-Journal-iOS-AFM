import XCTest
@testable import withMemento

/// Every suggestion card now puts a line in the transcript as the person's
/// opening turn, so that line is shipped copy and gets shipped-copy guards.
///
/// `card` and `opens` are both authored by hand. Deriving one from the other
/// was tried and abandoned: a second-to-first-person transform cannot tell the
/// noun "something" from a verb, so "Something you noticed about yourself"
/// became "Something me noticed about myself", and "What your body has been
/// telling you" became "...telling I". Five of forty-four were wrong, and
/// nothing would have said so on the forty-fifth.
final class StarterPromptCopyTests: XCTestCase {

    private var entries: [ThemeAwareChatStarters.StarterPrompt] {
        ThemeAwareChatStarters.genericEntries
    }

    private func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { " \t\n.,;:?!\"".contains($0) })
            .map(String.init)
    }

    // MARK: - The file itself

    func test_theFileLoaded() {
        XCTAssertGreaterThanOrEqual(entries.count, 20,
                                    "the prompt file did not load; the bundled fallback is in use")
    }

    func test_everyEntryHasBothStrings() {
        for entry in entries {
            XCTAssertFalse(entry.card.trimmingCharacters(in: .whitespaces).isEmpty,
                           "an entry has no card face")
            XCTAssertFalse(entry.opens.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(entry.card) has no bubble line")
        }
    }

    func test_cardsAndOpeningLinesAreUnique() {
        XCTAssertEqual(Set(entries.map(\.card)).count, entries.count, "a card face is duplicated")
        XCTAssertEqual(Set(entries.map(\.opens)).count, entries.count, "a bubble line is duplicated")
    }

    // MARK: - Voice

    /// The bubble is the person speaking, so it cannot address them.
    func test_openingLinesAreNeverSecondPerson() {
        let secondPerson: Set<String> = ["you", "your", "you've", "you're", "you'd", "yourself"]
        for entry in entries {
            let hits = words(entry.opens).filter { secondPerson.contains($0) }
            XCTAssertTrue(hits.isEmpty,
                          "\(entry.card): bubble line still addresses the person — \(hits)")
        }
    }

    /// And the card face is the app speaking, so it cannot be written as them.
    func test_cardFacesAreNotFirstPerson() {
        for entry in entries {
            let lower = entry.card.lowercased()
            for opening in ["i ", "i'", "my ", "me "] {
                XCTAssertFalse(lower.hasPrefix(opening),
                               "card face is written as the person speaking: \(entry.card)")
            }
        }
    }

    // MARK: - Routing

    /// An opener runs on a thin archive — that is the whole reason it exists.
    /// Its seed must reach a channel that answers without retrieval.
    ///
    /// This is not hypothetical. Converting the bubble to first person put
    /// "what got away from me this week" in the seed, and `this week` plus a
    /// self-reference matches `retrospectivePatterns`: that one card routed to
    /// `.journalQuery` → `.notebook`, which retrieves, against an archive with
    /// nothing in it. The second-person original never matched.
    func test_noOpenerSeedRoutesIntoRetrieval() {
        for entry in entries {
            let card = ChatSuggestion.opener(
                card: entry.card, opens: entry.opens, theme: nil
            )
            let turn = TurnClassifier.classify(card.seed, hasHistory: false)
            let channel = ReplyChannel.resolve(turn: turn, hasImages: false)
            XCTAssertFalse(
                channel.allowsRetrieval,
                "\(entry.card): opener seed routed to \(channel), which retrieves — "
                    + "on the thin archive openers exist for, that answers with nothing"
            )
            XCTAssertNotEqual(turn, .quantitative, "\(entry.card): opener seed is counting-shaped")
            XCTAssertTrue(channel.requiresOnDeviceModel,
                          "\(entry.card): opener seed reached a channel that never runs the model")
        }
    }

    /// The seed instructs the model and is never what the person reads.
    func test_seedAndBubbleAreDifferentStrings() {
        for entry in entries {
            let card = ChatSuggestion.opener(
                card: entry.card, opens: entry.opens, theme: nil
            )
            XCTAssertNotEqual(card.seed, card.promptText)
            XCTAssertEqual(card.promptText, entry.opens)
        }
    }

    // MARK: - The hardcoded fallbacks

    /// `fallbackStarters` render when rotation has not landed, so they need the
    /// same bubble line every other card has.
    func test_fallbackStartersAllCarryABubbleLine() {
        for card in ChatSuggestion.fallbackStarters {
            XCTAssertFalse((card.promptText ?? "").isEmpty,
                           "\(card.label) would tap through to no bubble")
        }
    }
}
