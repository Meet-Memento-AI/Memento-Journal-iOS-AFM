import XCTest
@testable import withMemento

/// The chat empty state is a fixed three-tile layout, so the card list has to
/// be exactly three, always, with three different faces.
///
/// Two ways it used to come up short, both silent:
///
/// 1. `DeepPromptBuilder.interleave` stops as soon as no fact kind has another
///    entry left. An archive with one qualifying cluster and nothing else
///    yields one card — and `rotateSuggestions` installed that single card over
///    the three openers already on screen, so two tiles disappeared once the
///    archive finished loading.
/// 2. `ChatMessagesView` fell back to openers only when the list was *empty*,
///    so one or two cards rendered as one or two tiles.
///
/// Neither shows up as a crash or a failing assertion anywhere else: the count
/// is only ever read by a `ForEach`. Hence this file.
final class SuggestionCardCountTests: XCTestCase {

    private func faces(_ cards: [ChatSuggestion]) -> [String] {
        cards.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }

    private func assertThreeUnique(
        _ cards: [ChatSuggestion], _ what: String, line: UInt = #line
    ) {
        XCTAssertEqual(cards.count, 3, "\(what) produced \(cards.count) cards, not 3", line: line)
        XCTAssertEqual(Set(faces(cards)).count, cards.count,
                       "\(what) repeated a card face: \(faces(cards))", line: line)
    }

    private func card(_ label: String) -> ChatSuggestion {
        ChatSuggestion(label: label, seed: "seed for \(label)", themeName: nil)
    }

    // MARK: - The fillers themselves

    /// `filled` can only top up to three if its default fillers are three
    /// distinct cards. Everything below rests on this.
    func test_fallbackStartersAreThreeUniqueCards() {
        assertThreeUnique(ChatSuggestion.fallbackStarters, "fallbackStarters")
    }

    // MARK: - filled()

    func test_emptyInput_stillYieldsThree() {
        assertThreeUnique(ThemeAwareChatStarters.filled([]), "filled([])")
    }

    /// The regression: one deep card must not become one tile.
    func test_oneDeepCard_isToppedUpToThree() {
        let deep = [card("The thread through work")]
        let result = ThemeAwareChatStarters.filled(deep)
        assertThreeUnique(result, "filled(one deep card)")
        XCTAssertEqual(result.first?.label, "The thread through work",
                       "the archive-derived card must stay first")
    }

    func test_twoDeepCards_areToppedUpToThree() {
        let deep = [card("The thread through work"), card("How Maya shows up in what you write")]
        let result = ThemeAwareChatStarters.filled(deep)
        assertThreeUnique(result, "filled(two deep cards)")
        XCTAssertEqual(Array(result.prefix(2)).map(\.label), deep.map(\.label))
    }

    func test_moreThanThree_isTruncatedToThree() {
        let many = (1...6).map { card("Card \($0)") }
        let result = ThemeAwareChatStarters.filled(many)
        assertThreeUnique(result, "filled(six cards)")
        XCTAssertEqual(result.map(\.label), ["Card 1", "Card 2", "Card 3"])
    }

    // MARK: - Uniqueness

    /// `id` is a fresh UUID per rotation, so duplicate faces can never be
    /// caught by identity. Dedup is on the visible label.
    func test_duplicateFacesAreCollapsedThenRefilled() {
        let dupes = [card("Same face"), card("same  FACE "), card("Same face")]
        assertThreeUnique(ThemeAwareChatStarters.filled(dupes), "filled(three duplicates)")
    }

    func test_aDeepCardColldingWithAFillerStillYieldsThree() {
        guard let opener = ChatSuggestion.fallbackStarters.first else { return XCTFail("no openers") }
        let result = ThemeAwareChatStarters.filled([card(opener.label.uppercased())])
        assertThreeUnique(result, "filled(card colliding with a filler)")
    }

    func test_blankFacesAreNeverShown() {
        let result = ThemeAwareChatStarters.filled([card(""), card("   ")])
        assertThreeUnique(result, "filled(blank faces)")
        XCTAssertFalse(result.contains { $0.label.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    // MARK: - The live rotation

    /// `rotate` shuffles, so one pass proves little. Repeat it.
    func test_rotateAlwaysYieldsThreeUnique() {
        for iteration in 1...50 {
            let cards = ThemeAwareChatStarters.rotate(
                genericPool: ThemeAwareChatStarters.genericPool, limit: 3
            )
            assertThreeUnique(cards, "rotate() iteration \(iteration)")
        }
    }

    /// A pool too small to fill three on its own must still fill three.
    func test_rotateWithAThinPool_stillYieldsThree() {
        assertThreeUnique(ThemeAwareChatStarters.rotate(genericPool: ["Only one"], limit: 3),
                          "rotate(one-entry pool)")
        assertThreeUnique(ThemeAwareChatStarters.rotate(genericPool: [], limit: 3),
                          "rotate(empty pool)")
    }

    // MARK: - End to end with the real builder

    /// The archive path, at the sizes it actually returns. A thin archive
    /// yields nothing and a middling one yields one or two; both must still
    /// reach the view as three tiles.
    func test_deepCardsOfAnyCountReachThreeTiles() {
        let window = DateInterval(start: Date().addingTimeInterval(-86400 * 30), duration: 86400 * 30)
        let facts: [InsightFact] = [
            .init(kind: .cluster, label: "work · deadline", value: "6", n: 6,
                  window: window, supportingEntryIDs: []),
            .init(kind: .person, label: "Maya", value: "5", n: 5,
                  window: window, supportingEntryIDs: [])
        ]
        for count in 0...facts.count {
            let deep = DeepPromptBuilder.prompts(from: Array(facts.prefix(count)), limit: 3)
            XCTAssertLessThanOrEqual(deep.count, 3)
            assertThreeUnique(ThemeAwareChatStarters.filled(deep),
                              "\(deep.count) archive card(s)")
        }
    }
}
