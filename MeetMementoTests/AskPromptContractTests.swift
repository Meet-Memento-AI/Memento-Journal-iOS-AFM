import XCTest
@testable import MeetMemento

final class AskPromptContractTests: XCTestCase {

    func test_ask5_versionAndHardBans() {
        let resolved = PromptRegistry.instructions(for: .ask)
        XCTAssertEqual(resolved.version, "ask@12")
        XCTAssertTrue(resolved.text.contains("Hard bans:"))
        XCTAssertTrue(resolved.text.contains("Never open a reply with \"You wrote\""))
        XCTAssertFalse(resolved.text.contains("(\"you wrote…\""))
        XCTAssertFalse(resolved.text.contains("three beats"))
    }

    /// ask@6: ref numbers are internal to `citedRefs`. The model must be told,
    /// in both the full and degraded prompts, never to write them into the
    /// reply — the labels sit in its context as the naming convention for
    /// entries, so without an explicit ban it reproduces them in prose.
    func test_ask5_bansReferenceMarkersInTheReply() {
        for degraded in [false, true] {
            let text = PromptRegistry.instructions(for: .ask, degraded: degraded).text
            XCTAssertTrue(
                text.contains("Never write a reference marker in the reply"),
                "degraded=\(degraded): the marker ban must be explicit"
            )
            XCTAssertTrue(text.contains("[ref 2]"), "degraded=\(degraded): ban should show the form")
        }
    }

    /// The context block still labels entries `[ref N | date]` — that is the
    /// addressing scheme `citedRefs` depends on, and removing it would break
    /// citations entirely. The prompt must keep asking for those numbers in the
    /// field even while banning them from the body.
    func test_ask5_stillCollectsCitedRefs() {
        let text = PromptRegistry.instructions(for: .ask).text
        XCTAssertTrue(text.contains("citedRefs"), "citedRefs must still be requested")
    }

    func test_personalized_usesAsk5PlusP2() {
        let p = PromptPersonalization(
            firstName: "Ada",
            reflection: "I want to understand my stress",
            goals: ["Stress", "Clarity"],
            promptLens: "Lean toward stress patterns."
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@12+p2")
        XCTAssertTrue(resolved.text.contains("Themes they chose: Stress, Clarity"))
        XCTAssertTrue(resolved.text.contains("Personalization lens:"))
        // With themes/lens present, raw reflection must not be quoted into L1.
        XCTAssertFalse(resolved.text.contains("I want to understand my stress"))
    }

    func test_personalized_quotesReflectionOnlyWhenNoThemesOrLens() {
        let p = PromptPersonalization(
            firstName: nil,
            reflection: "I want to understand my stress patterns more deeply",
            goals: [],
            promptLens: nil
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@12+p2")
        XCTAssertTrue(resolved.text.contains("I want to understand my stress patterns more deeply"))
    }

    func test_degraded_skipsReflectionEvenWithoutThemes() {
        let p = PromptPersonalization(
            firstName: nil,
            reflection: "my long reflection text",
            goals: [],
            promptLens: nil
        )
        let resolved = PromptRegistry.instructions(for: .ask, degraded: true, personalization: p)
        XCTAssertEqual(resolved.version, "ask-degraded@12+p2")
        XCTAssertFalse(resolved.text.contains("my long reflection text"))
    }

    func test_ask10_compositionSkeleton_onFullAndDegraded() {
        for degraded in [false, true] {
            let text = PromptRegistry.instructions(for: .ask, degraded: degraded).text
            XCTAssertTrue(text.contains("Meet them"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("Notebook"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("Sit"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("Open"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("must not skip Sit"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("complete spoken reply"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("heading1 and heading2 stay empty"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("Follow it exactly"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("answer and stop"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("three to five"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("Three to ten"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("Three to six"), "degraded=\(degraded)")
        }
    }

    func test_askAnswerGuides_bodyIsCompleteReply_headingsEmpty() {
        XCTAssertTrue(AskAnswerGuides.body.contains("complete spoken reply"))
        XCTAssertTrue(AskAnswerGuides.body.contains("Meet them"))
        XCTAssertTrue(AskAnswerGuides.body.contains("Open only if a [Shape:] line asks"))
        XCTAssertTrue(AskAnswerGuides.body.contains("Never a one-sentence caption"))
        XCTAssertTrue(AskAnswerGuides.body.contains("Markdown subset allowed"))
        XCTAssertTrue(AskAnswerGuides.heading1.hasPrefix("Always empty on conversational Ask"))
        XCTAssertEqual(AskAnswerGuides.heading2, "Always empty on conversational Ask.")
    }

    func test_ask12_openIsShapeGated_casualIsNotMeetThemOnly() {
        for degraded in [false, true] {
            let text = PromptRegistry.instructions(for: .ask, degraded: degraded).text
            XCTAssertTrue(text.contains("Shape gates Open"), "degraded=\(degraded)")
            XCTAssertTrue(
                text.contains("Open only if [Shape:] asks")
                    || text.contains("Open only if a [Shape:] line asks"),
                "degraded=\(degraded)"
            )
            XCTAssertFalse(text.contains("Meet them only"), "degraded=\(degraded)")
            XCTAssertTrue(
                text.contains("do not skip continuers"),
                "degraded=\(degraded)"
            )
            XCTAssertTrue(
                text.contains("how they are") || text.contains("what they just shared"),
                "degraded=\(degraded): notebook-off Open is about them"
            )
            XCTAssertTrue(
                text.contains("no ### unless they asked for the journal"),
                "degraded=\(degraded)"
            )
        }
        let full = PromptRegistry.instructions(for: .ask).text
        XCTAssertTrue(full.contains("When to use lists and headings"))
        XCTAssertTrue(full.contains("Journal question (one moment)"))
        XCTAssertTrue(full.contains("Zero markdown structure"))
    }

    func test_ask11_markdownGrammar_onFullAndDegraded() {
        for degraded in [false, true] {
            let text = PromptRegistry.instructions(for: .ask, degraded: degraded).text
            XCTAssertFalse(
                text.contains("plain spoken prose only"),
                "degraded=\(degraded): the no-markdown ban must be gone"
            )
            XCTAssertTrue(text.contains("###"), "degraded=\(degraded): ### heading grammar")
            XCTAssertTrue(
                text.contains("no headings or lists") || text.contains("Zero markdown structure"),
                "degraded=\(degraded): casual must forbid lists"
            )
            XCTAssertTrue(
                text.contains("italic") || text.contains("*italic*"),
                "degraded=\(degraded): italic quotes"
            )
            XCTAssertTrue(
                text.contains("what you can do together"),
                "degraded=\(degraded): about-the-app capability list"
            )
            XCTAssertTrue(
                text.contains("lists only if they asked what they"),
                "degraded=\(degraded): topic inventory may list"
            )
            XCTAssertTrue(text.contains("heading1 and heading2 stay empty"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("Never write more than one ###"), "degraded=\(degraded)")
        }
        let full = PromptRegistry.instructions(for: .ask).text
        XCTAssertTrue(full.contains("Markdown you may use"))
        XCTAssertTrue(full.contains("exact journal quotes"))
        XCTAssertTrue(full.contains("unordered lists starting with"))
        XCTAssertTrue(full.contains("ordered lists starting with"))
    }

    func test_ask6_safetyHardBans_onFullAndDegraded() {
        for degraded in [false, true] {
            let text = PromptRegistry.instructions(for: .ask, degraded: degraded).text
            XCTAssertTrue(text.contains("Safety hard bans"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("violence"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("terrorism"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("crisis counseling"), "degraded=\(degraded)")
            XCTAssertFalse(
                text.contains("988 Suicide & Crisis Lifeline"),
                "degraded=\(degraded): generative crisis counseling must be gone"
            )
        }
    }
}
