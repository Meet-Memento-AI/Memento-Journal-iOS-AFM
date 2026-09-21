import XCTest
@testable import MeetMemento

/// Spec 046 R1 / 049 S2–S3: every scorer regex compiles, and every `hall.*`
/// and `rule.*` code has a fixture that emits it.
final class ChatEvalScoringTests: XCTestCase {

    func test_everyRegexCompiles() {
        for pattern in ChatEvalScoring.compiledPatterns {
            XCTAssertNoThrow(
                try NSRegularExpression(pattern: pattern),
                "did not compile: \(pattern)"
            )
        }
    }

    func test_eachRuleAndHallCode_hasAFixture() {
        let journal = Entry(
            title: "Harbor",
            text: "The harbor was quiet before the first train left the station today."
        )
        let index = ChatEvalScoring.QuoteIndex([journal])
        let empty = ChatEvalScoring.QuoteIndex([])

        var emitted = Set<String>()
        func collect(_ violations: [ChatEvalScoring.Violation]) {
            for violation in violations { emitted.insert(violation.code) }
        }

        collect(ChatEvalScoring.ruleBreaks("You wrote about the harbor. What next?", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("Just sitting with that.", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("How are you? And what next?", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("There are three entries here. What next?", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("### One\nA line.\n### Two\nWhat next?", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("# Title\nWhat next?", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("###\nWhat next?", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("```\nnote\n```\nWhat next?", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("| a | b |\n|---|---|\nWhat next?", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("Hello there. What next? \u{1F31F}", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("The user said this. What next?", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("You should rest. What next?", isCasual: false))
        collect(ChatEvalScoring.ruleBreaks("### Day\nWhat next?", isCasual: true))
        collect(ChatEvalScoring.ruleBreaks("This is **bold words** here. What next?", isCasual: true))
        collect(ChatEvalScoring.ruleBreaks("- one item\nWhat next?", isCasual: true))
        collect(ChatEvalScoring.boldNotTheirWords(
            "They said **invented phrasing** today. What next?",
            index: index
        ))
        collect(ChatEvalScoring.fabricatedQuotes(
            "You wrote *the invented pottery night* in the margin.",
            index: index
        ))
        collect(ChatEvalScoring.uncitedQuote(
            "The harbor was quiet before the first train left the station today.",
            citations: [],
            index: index
        ))
        collect(ChatEvalScoring.firstPersonPerception("I saw that rat in the lab fridge too."))
        collect(ChatEvalScoring.narrativeJoin(
            "You keep tracing this back to the silence.",
            userTurn: "I was tired after the lab."
        ))

        let expected: Set<String> = [
            "rule.bannedOpener", "rule.noOpen", "rule.multipleQuestions", "rule.entryCount",
            "rule.multipleH3", "rule.badHeading", "rule.emptyHeading", "rule.codeFence",
            "rule.table", "rule.emoji", "rule.thirdPerson", "rule.bannedPhrase",
            "rule.casualHeading", "rule.casualBold", "rule.casualList", "rule.boldNotTheirWords",
            "hall.fabricatedQuote", "hall.uncitedQuote", "hall.firstPersonPerception",
            "hall.narrativeJoin"
        ]
        XCTAssertEqual(emitted.intersection(expected), expected, "missing \(expected.subtracting(emitted))")
        XCTAssertTrue(empty.isEmpty)
    }

    func test_perception_allowsHearYouAndImHere() {
        XCTAssertTrue(ChatEvalScoring.firstPersonPerception("I hear you, and I'm here.").isEmpty)
        XCTAssertFalse(ChatEvalScoring.firstPersonPerception("I heard the fridge door.").isEmpty)
    }

    func test_narrativeJoin_silentWhenUserAlreadySaidIt() {
        let hits = ChatEvalScoring.narrativeJoin(
            "You're holding the pattern you named.",
            userTurn: "You're holding the pattern of this week."
        )
        XCTAssertTrue(hits.isEmpty)
    }

    func test_reportOnlyHallucinationCodes_doNotGate() {
        let violations = [
            ChatEvalScoring.Violation(code: "hall.fabricatedQuote", detail: ""),
            ChatEvalScoring.Violation(code: "hall.firstPersonPerception", detail: ""),
            ChatEvalScoring.Violation(code: "hall.narrativeJoin", detail: ""),
            ChatEvalScoring.Violation(code: "hall.uncitedQuote", detail: "")
        ]
        let gated = ChatEvalScoring.gating(violations).map(\.code)
        XCTAssertEqual(gated, ["hall.uncitedQuote"])
    }

    // MARK: - Empty corpus (S3)

    func test_emptyCorpus_pinsQuoteSemantics() {
        let index = ChatEvalScoring.QuoteIndex([])
        XCTAssertTrue(index.isEmpty)
        XCTAssertFalse(index.contains("the harbor was quiet before the train"))
        XCTAssertNil(index.quotesCorpus(
            "The harbor was quiet before the first train left the station today."
        ))

        let italic = ChatEvalScoring.fabricatedQuotes(
            "Nothing here, but *the invented pottery night* showed up anyway.",
            index: index
        )
        XCTAssertTrue(italic.contains { $0.code == "hall.fabricatedQuote" })

        let heading = ChatEvalScoring.fabricatedQuotes(
            "### First pottery class\nI don't see anything.",
            index: index
        )
        XCTAssertTrue(heading.contains { $0.detail.contains("###") })

        XCTAssertTrue(ChatEvalScoring.uncitedQuote(
            "The harbor was quiet before the first train left the station today.",
            citations: [],
            index: index
        ).isEmpty)

        let bold = ChatEvalScoring.boldNotTheirWords(
            "They called it **invented phrasing** today.",
            index: index
        )
        XCTAssertEqual(bold.map(\.code), ["rule.boldNotTheirWords"])

        let plain = "I don't see anything from that stretch. What are you holding onto?"
        XCTAssertTrue(ChatEvalScoring.fabricatedQuotes(plain, index: index).isEmpty)
        XCTAssertTrue(ChatEvalScoring.uncitedQuote(plain, citations: [], index: index).isEmpty)
        XCTAssertTrue(ChatEvalScoring.boldNotTheirWords(plain, index: index).isEmpty)
    }
}
