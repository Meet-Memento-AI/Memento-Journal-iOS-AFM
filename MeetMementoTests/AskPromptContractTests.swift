import XCTest
@testable import MeetMemento

final class AskPromptContractTests: XCTestCase {

    func test_ask5_versionAndHardBans() {
        let resolved = PromptRegistry.instructions(for: .ask)
        XCTAssertEqual(resolved.version, "ask@14")
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

    func test_personalized_usesAsk13PlusP3() {
        let p = PromptPersonalization(
            firstName: "Ada",
            reflection: "I want to understand my stress",
            goals: ["Stress", "Clarity"],
            promptLens: "Lean toward stress patterns."
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@14+p4")
        XCTAssertFalse(resolved.text.contains("Themes they chose:"))
        XCTAssertTrue(resolved.text.contains("Faint lens (not an agenda):"))
        XCTAssertTrue(resolved.text.contains("Conversation first"))
        XCTAssertTrue(resolved.text.contains("do not steer"))
        XCTAssertFalse(resolved.text.contains("I want to understand my stress"))
    }

    func test_personalized_neverQuotesReflection() {
        let p = PromptPersonalization(
            firstName: nil,
            reflection: "I want to understand my stress patterns more deeply",
            goals: [],
            promptLens: nil
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p)
        XCTAssertEqual(resolved.version, "ask@14")
        XCTAssertFalse(resolved.text.contains("I want to understand my stress patterns more deeply"))
        XCTAssertFalse(resolved.text.contains("About this person (quiet background"))
    }

    func test_degraded_skipsReflectionEvenWithoutThemes() {
        let p = PromptPersonalization(
            firstName: nil,
            reflection: "my long reflection text",
            goals: [],
            promptLens: nil
        )
        let resolved = PromptRegistry.instructions(for: .ask, degraded: true, personalization: p)
        XCTAssertEqual(resolved.version, "ask-degraded@14")
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
        XCTAssertTrue(AskAnswerGuides.body.contains("Sound like a person talking"))
        XCTAssertTrue(AskAnswerGuides.body.contains("End with one specific question"))
        XCTAssertTrue(AskAnswerGuides.body.contains("skip the question only on goodbye"))
        XCTAssertTrue(AskAnswerGuides.body.contains("only if this turn uses the journal"))
        XCTAssertFalse(AskAnswerGuides.body.contains("Open only if a [Shape:] line asks"))
        XCTAssertFalse(AskAnswerGuides.body.contains("Meet them, Notebook, and Sit"))
        XCTAssertTrue(AskAnswerGuides.heading1.hasPrefix("Always empty on conversational Ask"))
        XCTAssertEqual(AskAnswerGuides.heading2, "Always empty on conversational Ask.")
    }

    func test_ask14_openIsRequired() {
        for degraded in [false, true] {
            let text = PromptRegistry.instructions(for: .ask, degraded: degraded).text
            XCTAssertTrue(
                text.contains("Open is required") || text.contains("then one question"),
                "degraded=\(degraded)"
            )
            XCTAssertFalse(text.contains("Open only if [Shape:] asks"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("Open only if a [Shape:] line asks"), "degraded=\(degraded)")
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
            XCTAssertTrue(
                text.contains("onboarding journal goals are not the subject"),
                "degraded=\(degraded)"
            )
            XCTAssertTrue(
                text.contains("pattern from the evidence") || text.contains("names a pattern"),
                "degraded=\(degraded): Sit names a pattern"
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

    func test_chatLight_versionAndBans() {
        let resolved = PromptRegistry.instructions(for: .ask, channel: .phatic)
        XCTAssertEqual(resolved.version, "chat-light@4")
        XCTAssertTrue(resolved.text.contains("Safety hard bans"))
        XCTAssertTrue(resolved.text.contains("plain spoken prose only"))
        XCTAssertTrue(resolved.text.contains("one genuine question")
                      || resolved.text.contains("then one genuine question"))
        XCTAssertTrue(resolved.text.contains("Quiet friend") || resolved.text.contains("quiet friend"))
        XCTAssertFalse(resolved.text.contains("never a question unless"))
        XCTAssertFalse(resolved.text.contains("How a reply is built"))
        XCTAssertFalse(resolved.text.contains("Notebook —"))
        XCTAssertFalse(resolved.text.contains("Sit —"))
        XCTAssertFalse(resolved.text.contains("About this person (quiet background"))
        XCTAssertTrue(resolved.text.contains("If a [Name:] line is present"))
        XCTAssertTrue(resolved.text.contains("never both in one reply"))
        XCTAssertTrue(resolved.text.contains("never Mr/Ms"))
    }

    func test_chatLightDegraded_versionAndBans() {
        let resolved = PromptRegistry.instructions(for: .ask, degraded: true, channel: .continuer)
        XCTAssertEqual(resolved.version, "chat-light-degraded@4")
        XCTAssertTrue(resolved.text.contains("Safety hard bans"))
        XCTAssertTrue(resolved.text.contains("one genuine question")
                      || resolved.text.contains("One or two spoken beats"))
        XCTAssertFalse(resolved.text.contains("never a question unless")
                       || resolved.text.contains("question unless they asked a yes-or-no"))
        XCTAssertFalse(resolved.text.contains("How a reply is built"))
        XCTAssertFalse(resolved.text.contains("Notebook —"))
    }

    func test_chatLight_neverAppendsPersonalization() {
        let p = PromptPersonalization(
            firstName: "Ada",
            reflection: "I want to understand my stress",
            goals: ["Stress"],
            promptLens: "Lean toward stress patterns."
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p, channel: .phatic)
        XCTAssertEqual(resolved.version, "chat-light@4")
        XCTAssertFalse(resolved.text.contains("About this person (quiet background"))
        XCTAssertFalse(resolved.text.contains("Ada"))
        XCTAssertFalse(resolved.version.contains("+p4"))
        XCTAssertFalse(resolved.version.contains("+p3"))
    }

    func test_phaticAssembledPrompt_hasNoEvidenceOrLens() {
        let stuffed = RetrievalResult(
            entries: [RetrievedEntry(ref: 1, id: UUID(), date: Date(), text: "work was hard")],
            contextBlock: "[ref 1 | today] work was hard",
            isAmbient: false
        )
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "hello",
            history: [ChatTurn(role: .user, text: "earlier")],
            retrieval: stuffed,
            stance: .casual,
            shape: .answerOpen,
            archiveEmpty: false,
            budget: ContextBudget(window: .unavailable),
            channel: .phatic,
            move: .greetAndAsk
        )
        XCTAssertFalse(prompt.contains("Journal evidence"))
        XCTAssertFalse(prompt.contains("[ref 1 | today]"))
        XCTAssertFalse(prompt.contains("About this person"))
        XCTAssertFalse(prompt.contains("\n\n[Shape:"), "phatic must not carry a Shape overlay")
        XCTAssertFalse(prompt.contains("[Turn:"), "phatic must not stack a Turn tag")
        XCTAssertFalse(prompt.contains("Do not reopen an entry"))
        XCTAssertTrue(prompt.contains("[Move:"))
        XCTAssertTrue(prompt.contains("The person's latest message: hello"))
        XCTAssertFalse(prompt.contains("[Name:"))
    }

    func test_phaticAssembledPrompt_nameCueWithoutL1() {
        let p = PromptPersonalization(
            firstName: "Sebastian",
            lastName: "Mendoza",
            reflection: "I want to understand my stress",
            goals: ["Stress"],
            promptLens: "Lean toward stress patterns."
        )
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "hello",
            history: [],
            retrieval: .empty,
            stance: .casual,
            shape: .answerOpen,
            archiveEmpty: true,
            budget: ContextBudget(window: .unavailable),
            channel: .phatic,
            move: .greetAndAsk,
            personalization: p
        )
        XCTAssertTrue(prompt.contains("[Name: Sebastian Mendoza"))
        XCTAssertTrue(prompt.contains("use first or last"))
        XCTAssertTrue(prompt.contains("[Move:"))
        XCTAssertFalse(prompt.contains("About this person"))
        XCTAssertFalse(prompt.contains("Faint lens"))
        XCTAssertFalse(prompt.contains("Lean toward stress patterns."))
        XCTAssertFalse(prompt.contains("[Turn:"))
    }

    func test_continuerAssembledPrompt_skipsNameWhenLastReplyUsedIt() {
        let p = PromptPersonalization(
            firstName: "Sebastian",
            lastName: "Mendoza",
            reflection: nil,
            goals: [],
            promptLens: nil
        )
        let history = [
            ChatTurn(role: .user, text: "hi"),
            ChatTurn(role: .assistant, text: "Hey Sebastian. What's been on your mind?")
        ]
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "yeah",
            history: history,
            retrieval: .empty,
            stance: .casual,
            shape: .answerOpen,
            archiveEmpty: true,
            budget: ContextBudget(window: .unavailable),
            channel: .continuer,
            move: .continuer,
            personalization: p
        )
        XCTAssertTrue(prompt.contains("[Don't use their name this turn.]"))
        XCTAssertTrue(prompt.contains("[Don't ask that again:"))
        XCTAssertFalse(prompt.contains("[Name:"))
        XCTAssertTrue(prompt.contains("Do not use their name"))
        XCTAssertFalse(prompt.contains("About this person"))
    }

    func test_continuerAssembledPrompt_omitsNameCueEvenWithoutPriorUse() {
        let p = PromptPersonalization(
            firstName: "Sebastian",
            lastName: "Mendoza",
            reflection: nil,
            goals: [],
            promptLens: nil
        )
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "yeah",
            history: [],
            retrieval: .empty,
            stance: .casual,
            shape: .answerOpen,
            archiveEmpty: true,
            budget: ContextBudget(window: .unavailable),
            channel: .continuer,
            move: .continuer,
            personalization: p
        )
        XCTAssertFalse(prompt.contains("[Name:"))
        XCTAssertTrue(prompt.contains("[Don't use their name this turn.]"))
    }

    func test_phaticAssembledPrompt_dropsNameCueWhenLastReplyUsedIt() {
        let p = PromptPersonalization(
            firstName: "Sebastian",
            lastName: "Mendoza",
            reflection: nil,
            goals: [],
            promptLens: nil
        )
        let history = [
            ChatTurn(role: .user, text: "hello"),
            ChatTurn(role: .assistant, text: "Hey Sebastian. How's the morning treating you?")
        ]
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "hello again",
            history: history,
            retrieval: .empty,
            stance: .casual,
            shape: .answerOpen,
            archiveEmpty: true,
            budget: ContextBudget(window: .unavailable),
            channel: .phatic,
            move: .greetAndAsk,
            personalization: p
        )
        XCTAssertFalse(prompt.contains("[Name:"))
        XCTAssertTrue(prompt.contains("[Don't use their name this turn.]"))
        XCTAssertTrue(prompt.contains("[Move:"))
    }

    func test_redirectAssembledPrompt_hasNameCueWithoutL1() {
        let p = PromptPersonalization(
            firstName: "Sebastian",
            lastName: "Mendoza",
            reflection: nil,
            goals: [],
            promptLens: "Lean toward stress patterns."
        )
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "what's the capital of France",
            history: [],
            retrieval: .empty,
            stance: .outsideScope,
            shape: .answerOpen,
            archiveEmpty: true,
            budget: ContextBudget(window: .unavailable),
            channel: .redirect,
            move: .redirectThenAsk,
            personalization: p
        )
        XCTAssertTrue(prompt.contains("[Name: Sebastian Mendoza"))
        XCTAssertFalse(prompt.contains("About this person"))
        XCTAssertFalse(prompt.contains("Faint lens"))
        XCTAssertTrue(prompt.contains("[Turn:") || prompt.contains("The person's latest message:"))
    }

    func test_notebookAssembledPrompt_doesNotStackNameCue() {
        let p = PromptPersonalization(
            firstName: "Sebastian",
            lastName: "Mendoza",
            reflection: nil,
            goals: [],
            promptLens: nil
        )
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "what did I write about work?",
            history: [],
            retrieval: .empty,
            stance: .noMatch,
            shape: .answerOpen,
            archiveEmpty: true,
            budget: ContextBudget(window: .unavailable),
            channel: .notebook,
            move: .patternThenAsk,
            personalization: p
        )
        XCTAssertFalse(prompt.contains("[Name:"))
        XCTAssertTrue(prompt.contains("[Don't use their name this turn.]"))
        XCTAssertFalse(prompt.contains("[Move:"), "notebook must not stack a Move cue")
    }

    func test_phaticAssembledPrompt_antiRepeatsLastQuestion() {
        let history = [
            ChatTurn(role: .user, text: "hi"),
            ChatTurn(role: .assistant, text: "Hey. What's been on your mind?")
        ]
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "yeah",
            history: history,
            retrieval: .empty,
            stance: .casual,
            shape: .answerOpen,
            archiveEmpty: true,
            budget: ContextBudget(window: .unavailable),
            channel: .continuer,
            move: .continuer
        )
        XCTAssertTrue(prompt.contains("[Don't ask that again:"))
        XCTAssertTrue(prompt.contains("What's been on your mind?"))
        XCTAssertTrue(prompt.contains("[Move:"))
        XCTAssertFalse(prompt.contains("[Turn:"))
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
