import XCTest
@testable import withMemento

/// Proof that the scorers can fire (spec 046 R1 / 048 R1).
///
/// `ChatEvalScoring` had no unit test. That is how `hall.fabricatedQuote` — the
/// check its own comment calls "the single most damaging failure mode for a
/// journal app" — shipped with a pattern ICU cannot parse, threw inside
/// `NSRegularExpression.init`, got swallowed by `spans`'s `try?`, and returned
/// no violations for every input it was ever handed. Across a 200-conversation
/// study (3,119 generated turns, 202 of them carrying a span that matches the
/// intended pattern) it fired zero times, and zero violations reads as a clean
/// run.
///
/// So the rule this file enforces is: **a scorer must prove it can fire.** Every
/// violation code gets a fixture that makes it appear, and every pattern gets
/// compiled. A gating check that cannot fire is worse than no check.
final class ChatEvalScoringTests: XCTestCase {

    // MARK: - Helpers

    private func codes(_ violations: [ChatEvalScoring.Violation]) -> [String] {
        violations.map(\.code)
    }

    private var corpus: [Entry] {
        [Entry(title: "Sleep is falling apart",
               text: "Woke up at 3:40am again. That is five nights running. "
                   + "I checked my phone which I know makes it worse.",
               createdAt: Date())]
    }

    private var index: ChatEvalScoring.QuoteIndex { .init(corpus) }
    private var emptyIndex: ChatEvalScoring.QuoteIndex { .init([]) }

    // MARK: - The regression that started this

    /// Every pattern the file uses must compile. This is the test that would
    /// have caught the original defect on the day it landed.
    func test_everyPattern_compiles() {
        for (code, pattern) in ChatEvalScoring.regexPatterns {
            XCTAssertNoThrow(
                try NSRegularExpression(pattern: pattern),
                "\(code): pattern does not compile, so the scorer silently returns no violations"
            )
        }
    }

    /// The exact spelling that was broken, pinned so nobody "simplifies" it back.
    /// Swift raw strings pass `\u{201C}` through untouched and ICU rejects it.
    func test_fabricatedQuotePattern_usesTheFormICUAccepts() {
        XCTAssertFalse(ChatEvalScoring.fabricatedQuotePattern.contains("\\u{"),
                       "ICU rejects \\u{hhhh}; use \\x{hhhh} or a literal character")
        XCTAssertNoThrow(try NSRegularExpression(pattern: ChatEvalScoring.fabricatedQuotePattern))
    }

    /// Reproduced from the archived run
    /// (`.eval-runs/convo-sim/full-2026-09-20.jsonl`, `full-2026-09-20/empty/…`):
    /// the assistant correctly says it has nothing, then invents an entry anyway.
    func test_fabricatedQuote_firesOnInventedJournalMaterial() {
        let body = "I don\u{2019}t see anything from that stretch \u{2014} no trace of the rent notice. "
            + "What are you holding onto now? *the rent notice showed up with no warning*"
        XCTAssertEqual(codes(ChatEvalScoring.fabricatedQuotes(body, index: index)),
                       ["hall.fabricatedQuote"])
    }

    func test_fabricatedQuote_silentOnAGenuineQuote() {
        let body = "You wrote it plainly: *Woke up at 3:40am again* \u{2014} what changed that week?"
        XCTAssertEqual(ChatEvalScoring.fabricatedQuotes(body, index: index), [])
    }

    func test_fabricatedQuote_ignoresBoldSpans() {
        let body = "That **five nights running** stretch is the part that stays. What shifted?"
        XCTAssertEqual(ChatEvalScoring.fabricatedQuotes(body, index: index), [])
    }

    // MARK: - leak.*

    func test_leak_schemaField() {
        XCTAssertTrue(codes(ChatEvalScoring.leaks("Here you go. citedRefs: 1"))
            .contains("leak.schemaField"))
    }

    func test_leak_ctrlToken() {
        XCTAssertTrue(codes(ChatEvalScoring.leaks("Something <ctrl99> slipped"))
            .contains("leak.ctrlToken"))
    }

    func test_leak_placeholder() {
        XCTAssertTrue(codes(ChatEvalScoring.leaks("Good to see you, [Name]."))
            .contains("leak.placeholder"))
    }

    func test_leak_emptyBracket() {
        XCTAssertTrue(codes(ChatEvalScoring.leaks("The quiet part [] stayed."))
            .contains("leak.emptyBracket"))
    }

    func test_leak_literalMarkup() {
        XCTAssertTrue(codes(ChatEvalScoring.leaks("He said *italic* out loud"))
            .contains("leak.literalMarkup"))
    }

    func test_leak_sectionLabel() {
        XCTAssertTrue(codes(ChatEvalScoring.leaks("Notebook \u{2014} you wrote about sleep"))
            .contains("leak.sectionLabel"))
    }

    func test_leak_promptTag() {
        XCTAssertTrue(codes(ChatEvalScoring.leaks("[Turn: journal question] you asked"))
            .contains("leak.promptTag"))
    }

    func test_leak_evidenceChrome() {
        XCTAssertTrue(codes(ChatEvalScoring.leaks("From [ref 2] you wrote about sleep"))
            .contains("leak.evidenceChrome"))
    }

    // MARK: - rule.*

    func test_rule_bannedOpener() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("You wrote about sleep. What changed?",
                                                       isCasual: false))
            .contains("rule.bannedOpener"))
    }

    func test_rule_noOpen() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("That sounds heavy.", isCasual: false))
            .contains("rule.noOpen"))
    }

    func test_rule_multipleQuestions() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("What changed? And how did it feel?",
                                                       isCasual: false))
            .contains("rule.multipleQuestions"))
    }

    func test_rule_entryCount() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("I see three entries there. What stands out?",
                                                       isCasual: false))
            .contains("rule.entryCount"))
    }

    func test_rule_multipleH3() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("### One\nbody\n### Two\nmore. What now?",
                                                       isCasual: false))
            .contains("rule.multipleH3"))
    }

    func test_rule_badHeading() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("## Heading\nbody. What now?",
                                                       isCasual: false))
            .contains("rule.badHeading"))
    }

    func test_rule_emptyHeading() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("###\nnothing above. What now?",
                                                       isCasual: false))
            .contains("rule.emptyHeading"))
    }

    func test_rule_codeFence() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("```\ncode\n```\nWhat now?",
                                                       isCasual: false))
            .contains("rule.codeFence"))
    }

    func test_rule_table() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("| a | b |\n|---|---|\nWhat now?",
                                                       isCasual: false))
            .contains("rule.table"))
    }

    func test_rule_emoji() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("That sounds hard \u{1F614} what changed?",
                                                       isCasual: false))
            .contains("rule.emoji"))
    }

    func test_rule_thirdPerson() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("The user seems tired. What changed?",
                                                       isCasual: false))
            .contains("rule.thirdPerson"))
    }

    func test_rule_bannedPhrase() {
        XCTAssertTrue(codes(ChatEvalScoring.ruleBreaks("You should rest more. What changed?",
                                                       isCasual: false, index: index))
            .contains("rule.bannedPhrase"))
    }

    /// The carve-out: reflecting the person's own wording back is not a banned
    /// phrase, so the check must consult the corpus before firing.
    func test_rule_bannedPhrase_allowedWhenItIsTheirOwnWording() {
        let theirWords = [Entry(title: "Note",
                                text: "I keep telling myself you should rest more.",
                                createdAt: Date())]
        let codesFound = codes(ChatEvalScoring.ruleBreaks(
            "You should rest more. What changed?",
            isCasual: false,
            index: .init(theirWords)))
        XCTAssertFalse(codesFound.contains("rule.bannedPhrase"))
    }

    func test_rule_casualHeadingBoldAndList() {
        let found = codes(ChatEvalScoring.ruleBreaks("### Hi\n**bold**\n- item\nWhat now?",
                                                     isCasual: true))
        XCTAssertTrue(found.contains("rule.casualHeading"))
        XCTAssertTrue(found.contains("rule.casualBold"))
        XCTAssertTrue(found.contains("rule.casualList"))
    }

    func test_rule_boldNotTheirWords() {
        let body = "That **particular shade of institutional despair** stayed. What changed?"
        XCTAssertEqual(codes(ChatEvalScoring.boldNotTheirWords(body, index: index)),
                       ["rule.boldNotTheirWords"])
    }

    // MARK: - hall.uncitedQuote

    func test_uncitedQuote_firesOnVerbatimSpanWithNoCitations() {
        let body = "Woke up at 3:40am again. That is five nights running. What changed?"
        XCTAssertEqual(codes(ChatEvalScoring.uncitedQuote(body, citations: [], index: index)),
                       ["hall.uncitedQuote"])
    }

    func test_uncitedQuote_silentWhenCited() {
        let body = "Woke up at 3:40am again. That is five nights running. What changed?"
        let citation = AskCitation(entryId: UUID(), entryDate: Date(), excerpt: "…")
        XCTAssertEqual(ChatEvalScoring.uncitedQuote(body, citations: [citation], index: index), [])
    }

    // MARK: - gen.*

    func test_gen_hitTokenCap() {
        let long = String(repeating: "word ", count: 400)
        XCTAssertEqual(codes(ChatEvalScoring.runaway(long, capTokens: 128)), ["gen.hitTokenCap"])
    }

    /// `gen.*` is deliberately report-only — a reply may legitimately run long.
    func test_gating_excludesGenButIncludesTheRest() {
        let all: [ChatEvalScoring.Violation] = [
            .init(code: "gen.hitTokenCap", detail: ""),
            .init(code: "hall.fabricatedQuote", detail: ""),
            .init(code: "leak.promptTag", detail: ""),
            .init(code: "rule.noOpen", detail: "")
        ]
        XCTAssertEqual(codes(ChatEvalScoring.gating(all)),
                       ["hall.fabricatedQuote", "leak.promptTag", "rule.noOpen"])
    }

    // MARK: - Coverage of the codes themselves (048 R1)

    /// Every violation code this file can emit must have a fixture above. When
    /// someone adds a code without one, this fails and names it.
    func test_everyViolationCode_hasAFiringFixture() {
        let covered: Set<String> = [
            "leak.schemaField", "leak.ctrlToken", "leak.placeholder", "leak.emptyBracket",
            "leak.literalMarkup", "leak.sectionLabel", "leak.promptTag", "leak.evidenceChrome",
            "rule.bannedOpener", "rule.noOpen", "rule.multipleQuestions", "rule.entryCount",
            "rule.multipleH3", "rule.badHeading", "rule.emptyHeading", "rule.codeFence",
            "rule.table", "rule.emoji", "rule.thirdPerson", "rule.bannedPhrase",
            "rule.casualHeading", "rule.casualBold", "rule.casualList",
            "rule.boldNotTheirWords", "hall.fabricatedQuote", "hall.uncitedQuote",
            "gen.hitTokenCap",
            // Covered by InsightEngineTests, which predates this file.
            "insight.digitDisagrees", "insight.contradictsSuppressed",
            // Emitted only against a gold set; exercised by ChatEvalGate.
            "gold.overcited", "gold.noCitation", "gold.wrongCitation", "gold.partialCitation"
        ]
        for (code, _) in ChatEvalScoring.regexPatterns {
            XCTAssertTrue(covered.contains(code),
                          "\(code) has a pattern but no fixture proving it fires")
        }
    }
}
