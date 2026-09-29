import XCTest
@testable import withMemento

final class AskPromptContractTests: XCTestCase {

    func test_ask5_versionAndHardBans() {
        let resolved = PromptRegistry.instructions(for: .ask)
        XCTAssertEqual(resolved.version, "ask-core@20")
        XCTAssertTrue(resolved.text.hasPrefix("You are Memento, a journaling companion."))
        XCTAssertTrue(resolved.text.contains("Never open with \"You wrote\""))
        XCTAssertTrue(resolved.text.contains("never open two replies in a row the same way"))
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
                text.contains("Never write a ref number in the reply"),
                "degraded=\(degraded): the [ref] ban must be explicit"
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
        XCTAssertEqual(resolved.version, "ask-core@20+p4")
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
        XCTAssertEqual(resolved.version, "ask-core@20")
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
        XCTAssertEqual(resolved.version, "ask-degraded@20")
        XCTAssertFalse(resolved.text.contains("my long reflection text"))
    }

    func test_ask10_compositionSkeleton_onFullAndDegraded() {
        for degraded in [false, true] {
            let text = PromptRegistry.instructions(for: .ask, degraded: degraded).text
            XCTAssertTrue(text.contains("stay with"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("one specific question"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("whole spoken reply"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("Follow it exactly"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("answer and stop"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("three to five"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("Three to ten"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("Three to six"), "degraded=\(degraded)")
        }
        let full = PromptRegistry.instructions(for: .ask).text
        for part in ["Meet them:", "Notebook:", "Sit:", "Open:"] {
            XCTAssertTrue(full.contains(part), part)
        }
    }

    func test_askAnswerGuides_bodyIsCompleteReply_headingsEmpty() {
        XCTAssertTrue(AskAnswerGuides.body.contains("complete spoken reply"))
        XCTAssertTrue(AskAnswerGuides.body.contains("Sound like a person talking"))
        XCTAssertTrue(AskAnswerGuides.body.contains("End with one specific question"))
        XCTAssertTrue(AskAnswerGuides.body.contains("skip the question only on goodbye"))
        XCTAssertFalse(AskAnswerGuides.body.contains("only if this turn uses the journal"))
        XCTAssertTrue(AskAnswerGuides.body.contains("one ### heading"))
        XCTAssertFalse(AskAnswerGuides.body.contains("Open only if a [Shape:] line asks"))
        XCTAssertFalse(AskAnswerGuides.body.contains("Meet them, Notebook, and Sit"))
        XCTAssertTrue(LightAskAnswerGuides.body.contains("One or two spoken sentences"))
        XCTAssertTrue(LightAskAnswerGuides.body.contains("then one question"))
        XCTAssertTrue(LightAskAnswerGuides.body.contains("what the app can do"))
        XCTAssertTrue(LightAskAnswerGuides.body.contains("otherwise no lists"))
        XCTAssertTrue(LightAskAnswerGuides.body.contains("No citations"))
        XCTAssertTrue(LightAskAnswerGuides.body.contains("no ###"))
        XCTAssertFalse(LightAskAnswerGuides.body.contains("citedRefs"))
        XCTAssertFalse(LightAskAnswerGuides.body.contains("No markdown, no lists"))
    }

    func test_spokenNotebook_usesBodyOnlySchema() {
        XCTAssertTrue(ReplyChannel.notebook.usesBodyOnlySchema(spoken: true))
        XCTAssertFalse(ReplyChannel.notebook.usesBodyOnlySchema(spoken: false))
        XCTAssertTrue(ReplyChannel.thread.usesBodyOnlySchema(spoken: true))
        XCTAssertFalse(ReplyChannel.thread.usesBodyOnlySchema(spoken: false))
        XCTAssertTrue(ReplyChannel.companion.usesBodyOnlySchema(spoken: true))
        XCTAssertTrue(ReplyChannel.meta.usesBodyOnlySchema(spoken: true))
    }

    func test_ask14_openIsRequired() {
        for degraded in [false, true] {
            let text = PromptRegistry.instructions(for: .ask, degraded: degraded).text
            XCTAssertTrue(
                text.contains("one specific question"),
                "degraded=\(degraded)"
            )
            XCTAssertFalse(text.contains("Open only if [Shape:] asks"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("Open only if a [Shape:] line asks"), "degraded=\(degraded)")
            XCTAssertFalse(text.contains("Meet them only"), "degraded=\(degraded)")
            // Shipped sentence-initial in askCore ("Do not skip continuers."),
            // lower-case mid-sentence in askCoreDegraded. The contract is that
            // the rule is stated; its capitalisation is prose, so match either.
            XCTAssertTrue(
                text.localizedCaseInsensitiveContains("do not skip continuers"),
                "degraded=\(degraded)"
            )
            XCTAssertTrue(
                text.contains("what they just said") || text.contains("answer their latest message"),
                "degraded=\(degraded): Meet answers the latest turn"
            )
            XCTAssertTrue(
                text.contains("onboarding goals are not the subject"),
                "degraded=\(degraded)"
            )
            XCTAssertTrue(text.contains("stay with"), "degraded=\(degraded): Sit stays with one moment")
            XCTAssertFalse(text.contains("names a pattern"), "degraded=\(degraded)")
        }
        XCTAssertTrue(TurnStance.sharing.promptLine.contains("No ### unless they asked for the journal"))
        let light = PromptRegistry.instructions(for: .ask, channel: .phatic).text
        XCTAssertTrue(light.contains("plain spoken prose only"))
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
                text.localizedCaseInsensitiveContains("never italics"),
                "degraded=\(degraded): italics are the app's typography, never the model's"
            )
            XCTAssertFalse(text.contains("{{quote:"), "degraded=\(degraded): markers are taught by the legend only")
            XCTAssertTrue(text.contains("lists only when"), "degraded=\(degraded): lists only on request")
            XCTAssertTrue(text.localizedCaseInsensitiveContains("at most one ###"), "degraded=\(degraded)")
            XCTAssertTrue(text.contains("never # or ##"), "degraded=\(degraded)")
        }
        let full = PromptRegistry.instructions(for: .ask).text
        XCTAssertTrue(full.contains("Format:"))
        XCTAssertFalse(full.contains("exact journal quotes"))
        XCTAssertTrue(full.contains("\"- \" or \"1. \" lists"))
        XCTAssertTrue(EvidencePack.legendFooter.contains("{{quote:N}}"))
        XCTAssertTrue(TurnStance.aboutApp.promptLine.contains("what you can do together"))
        XCTAssertTrue(TurnStance.casual.promptLine.contains("No headings or lists"))
    }

    func test_chatLight_versionAndBans() {
        let resolved = PromptRegistry.instructions(for: .ask, channel: .phatic)
        XCTAssertEqual(resolved.version, "chat-light@5")
        assertSafetyLine(resolved.text)
        XCTAssertTrue(resolved.text.contains("plain spoken prose only"))
        XCTAssertTrue(resolved.text.contains("one genuine question")
                      || resolved.text.contains("then one genuine question"))
        XCTAssertTrue(resolved.text.contains("Quiet friend") || resolved.text.contains("quiet friend"))
        XCTAssertFalse(resolved.text.contains("never a question unless"))
        XCTAssertFalse(resolved.text.contains("How a reply is built"))
        XCTAssertFalse(resolved.text.contains("Notebook —"))
        XCTAssertFalse(resolved.text.contains("Sit —"))
        XCTAssertFalse(resolved.text.contains("About this person (quiet background"))
        XCTAssertTrue(resolved.text.contains("When their name is given"))
        XCTAssertTrue(resolved.text.contains("never both in one reply"))
        XCTAssertTrue(resolved.text.contains("never Mr/Ms"))
    }

    func test_chatLightDegraded_versionAndBans() {
        let resolved = PromptRegistry.instructions(for: .ask, degraded: true, channel: .continuer)
        XCTAssertEqual(resolved.version, "chat-light-degraded@5")
        assertSafetyLine(resolved.text)
        XCTAssertTrue(resolved.text.contains("one genuine question")
                      || resolved.text.contains("One or two spoken beats"))
        XCTAssertFalse(resolved.text.contains("never a question unless")
                       || resolved.text.contains("question unless they asked a yes-or-no"))
        XCTAssertFalse(resolved.text.contains("How a reply is built"))
        XCTAssertFalse(resolved.text.contains("Notebook —"))
    }

    func test_chatCompanion_versionAndBans() {
        let resolved = PromptRegistry.instructions(for: .ask, channel: .companion)
        XCTAssertEqual(resolved.version, "chat-companion@2")
        assertSafetyLine(resolved.text)
        XCTAssertTrue(resolved.text.contains("one genuine question")
                      || resolved.text.contains("then one genuine question"))
        XCTAssertFalse(resolved.text.contains("How a reply is built"))
        XCTAssertFalse(resolved.text.contains("Sit —"))
        XCTAssertTrue(resolved.text.contains("When their name is given"))
        XCTAssertTrue(resolved.text.hasPrefix("You are Memento"))
    }

    func test_chatCompanionDegraded_versionAndBans() {
        let resolved = PromptRegistry.instructions(for: .ask, degraded: true, channel: .meta)
        XCTAssertEqual(resolved.version, "chat-companion-degraded@2")
        assertSafetyLine(resolved.text)
        XCTAssertFalse(resolved.text.contains("How a reply is built"))
    }

    func test_chatCompanion_personalizationSuffix_notOnRedirect() {
        let p = PromptPersonalization(
            firstName: "Ada",
            reflection: "I want to understand my stress",
            goals: ["Stress"],
            promptLens: "Lean toward stress patterns."
        )
        let companion = PromptRegistry.instructions(for: .ask, personalization: p, channel: .companion)
        XCTAssertEqual(companion.version, "chat-companion@2+p4")
        let redirect = PromptRegistry.instructions(for: .ask, personalization: p, channel: .redirect)
        XCTAssertEqual(redirect.version, "chat-companion@2")
        XCTAssertFalse(redirect.text.contains("Ada"))
        XCTAssertFalse(redirect.version.contains("+p4"))
    }

    func test_chatLight_neverAppendsPersonalization() {
        let p = PromptPersonalization(
            firstName: "Ada",
            reflection: "I want to understand my stress",
            goals: ["Stress"],
            promptLens: "Lean toward stress patterns."
        )
        let resolved = PromptRegistry.instructions(for: .ask, personalization: p, channel: .phatic)
        XCTAssertEqual(resolved.version, "chat-light@5")
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
        assertNoStanceOrShapeLine(prompt)
        XCTAssertFalse(prompt.contains("Do not reopen an entry"))
        XCTAssertTrue(prompt.contains("How to reply:"))
        XCTAssertTrue(prompt.contains("The person's latest message: hello"))
        XCTAssertFalse(prompt.contains("Their name is"))
    }

    func test_companionAssembledPrompt_hasNoEvidence() {
        let stuffed = RetrievalResult(
            entries: [RetrievedEntry(ref: 1, id: UUID(), date: Date(), text: "work was hard")],
            contextBlock: "[ref 1 | today] work was hard",
            isAmbient: false
        )
        let personalization = PromptPersonalization(
            firstName: "Ada",
            reflection: nil,
            goals: [],
            promptLens: "Lean toward stress patterns."
        )
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "I had a rough day at work today",
            history: [],
            retrieval: stuffed,
            stance: .sharing,
            shape: .answerOpen,
            archiveEmpty: false,
            budget: ContextBudget(window: .unavailable),
            channel: .companion,
            move: .reflectAndAsk,
            personalization: personalization
        )
        assertShortAssembler(prompt, latest: "I had a rough day at work today")
        XCTAssertTrue(prompt.contains("Show you heard the specific thing"))
        XCTAssertFalse(prompt.contains("Their name is"), "companion keeps names in L1, not a stacked cue")
        XCTAssertEqual(
            PromptRegistry.instructions(for: .ask, channel: .companion).version,
            "chat-companion@2"
        )
    }

    func test_metaAssembledPrompt_usesShortAssembler() {
        let stuffed = RetrievalResult(
            entries: [RetrievedEntry(ref: 1, id: UUID(), date: Date(), text: "work was hard")],
            contextBlock: "[ref 1 | today] work was hard",
            isAmbient: false
        )
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "what can you do",
            history: [],
            retrieval: stuffed,
            stance: .casual,
            shape: .answerOpen,
            archiveEmpty: false,
            budget: ContextBudget(window: .unavailable),
            channel: .meta,
            move: .answerThenAsk
        )
        assertShortAssembler(prompt, latest: "what can you do")
        XCTAssertTrue(prompt.contains("How to reply: Answer first"))
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
        XCTAssertTrue(prompt.contains("Their name is Sebastian Mendoza"))
        XCTAssertTrue(prompt.contains("first or last name"))
        XCTAssertTrue(prompt.contains("How to reply:"))
        XCTAssertFalse(prompt.contains("About this person"))
        XCTAssertFalse(prompt.contains("Faint lens"))
        XCTAssertFalse(prompt.contains("Lean toward stress patterns."))
        assertNoStanceOrShapeLine(prompt)
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
        XCTAssertTrue(prompt.contains(PromptPersonalization.nameSkipLine))
        XCTAssertTrue(prompt.contains("You already asked this, so don't ask it again:"))
        XCTAssertFalse(prompt.contains("Their name is"))
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
        XCTAssertFalse(prompt.contains("Their name is"))
        XCTAssertTrue(prompt.contains(PromptPersonalization.nameSkipLine))
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
        XCTAssertFalse(prompt.contains("Their name is"))
        XCTAssertTrue(prompt.contains(PromptPersonalization.nameSkipLine))
        XCTAssertTrue(prompt.contains("How to reply:"))
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
        XCTAssertTrue(prompt.contains("Their name is Sebastian Mendoza"))
        XCTAssertFalse(prompt.contains("About this person"))
        XCTAssertFalse(prompt.contains("Faint lens"))
        assertShortAssembler(prompt, latest: "what's the capital of France")
        XCTAssertTrue(prompt.contains("How to reply: That's outside what you can see"))
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
        XCTAssertFalse(prompt.contains("Their name is"))
        XCTAssertTrue(prompt.contains(PromptPersonalization.nameSkipLine))
        XCTAssertFalse(prompt.contains("How to reply:"), "notebook must not stack a Move cue")
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
        XCTAssertTrue(prompt.contains("You already asked this, so don't ask it again:"))
        XCTAssertTrue(prompt.contains("What's been on your mind?"))
        XCTAssertTrue(prompt.contains("How to reply:"))
        assertNoStanceOrShapeLine(prompt)
    }

    func test_spokenFollowupPrompt_answersLastQuestionAndShapesShort() {
        let history = [
            ChatTurn(role: .user, text: "work was a lot"),
            ChatTurn(role: .assistant, text: "That sounds like a full day. How did work feel?")
        ]
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "it was actually pretty heavy",
            history: history,
            retrieval: .empty,
            stance: .followupThread,
            shape: .answerOpen,
            archiveEmpty: true,
            budget: ContextBudget(window: .unavailable),
            channel: .companion,
            move: .answerThenAsk,
            spoken: true
        )
        XCTAssertTrue(prompt.contains("They are answering your last question:"))
        XCTAssertTrue(prompt.contains("How did work feel?"))
        XCTAssertTrue(prompt.contains("You already asked this, so don't ask it again:"))
        XCTAssertTrue(prompt.contains("How to reply: Answer first"))
        XCTAssertTrue(prompt.contains("The person's latest message: it was actually pretty heavy"))
        assertNoStanceOrShapeLine(prompt)
        XCTAssertFalse(prompt.contains(PromptRegistry.spokenTurnShapeLine))
        XCTAssertFalse(prompt.contains("citedRefs"))
    }

    func test_spokenJournalFollowupPrompt_stillAnswersLastQuestionOnThread() {
        let history = [
            ChatTurn(role: .user, text: "What did I write about the hike?"),
            ChatTurn(role: .assistant, text: "You went up Mount Tamalpais with Maya. Want the next beat?")
        ]
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "tell me more",
            history: history,
            retrieval: .empty,
            stance: .followupThread,
            shape: .answerOpen,
            archiveEmpty: true,
            budget: ContextBudget(window: .unavailable),
            channel: .thread,
            move: .answerThenAsk,
            spoken: true
        )
        XCTAssertTrue(prompt.contains("They are answering your last question:"))
        XCTAssertTrue(prompt.contains(PromptRegistry.spokenTurnShapeLine))
    }

    func test_typedFollowupPrompt_doesNotInjectSpokenCues() {
        let history = [
            ChatTurn(role: .user, text: "work was a lot"),
            ChatTurn(role: .assistant, text: "That sounds like a full day. How did work feel?")
        ]
        let prompt = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "it was actually pretty heavy",
            history: history,
            retrieval: .empty,
            stance: .followupThread,
            shape: .answerOpen,
            archiveEmpty: true,
            budget: ContextBudget(window: .unavailable),
            channel: .thread,
            move: .answerThenAsk
        )
        XCTAssertFalse(prompt.contains("They are answering your last question:"))
        XCTAssertFalse(prompt.contains(PromptRegistry.spokenTurnShapeLine))
    }

    func test_ask6_safetyHardBans_onFullAndDegraded() {
        for degraded in [false, true] {
            let text = PromptRegistry.instructions(for: .ask, degraded: degraded).text
            assertSafetyLine(text, "degraded=\(degraded)")
            XCTAssertFalse(
                text.contains("988 Suicide & Crisis Lifeline"),
                "degraded=\(degraded): generative crisis counseling must be gone"
            )
        }
    }

    // MARK: - Spec 050: markers, not italics

    private func groundedRetrieval(ambient: Bool = false) -> RetrievalResult {
        let entries = [
            RetrievedEntry(ref: 1, id: UUID(), date: Date(timeIntervalSince1970: 1_772_539_200),
                           text: "Slept through the night for the first time in weeks. The house was quiet."),
            RetrievedEntry(ref: 2, id: UUID(), date: Date(timeIntervalSince1970: 1_773_057_600),
                           text: "Work was loud again today and I left with my jaw still tight.")
        ]
        return RetrievalResult(
            entries: entries,
            contextBlock: EntryRetriever.contextBlock(for: entries, ambient: ambient),
            isAmbient: ambient
        )
    }

    private func journalPrompt(
        _ question: String, stance: TurnStance, channel: ReplyChannel, retrieval: RetrievalResult,
        archiveEmpty: Bool = false
    ) -> String {
        FoundationModelsIntelligenceService.buildAskPrompt(
            question: question,
            history: [],
            retrieval: retrieval,
            stance: stance,
            shape: .answerOpen,
            archiveEmpty: archiveEmpty,
            budget: ContextBudget(window: .unavailable),
            channel: channel,
            move: .patternThenAsk
        )
    }

    func test_groundedNotebookPrompt_carriesTheEvidenceLegend_notTheItalicContract() {
        let retrieval = groundedRetrieval()
        let prompt = journalPrompt("How have I been sleeping?", stance: .journalGrounded,
                                   channel: .notebook, retrieval: retrieval)
        XCTAssertTrue(prompt.contains(EvidencePack.legendHeader))
        XCTAssertTrue(prompt.contains("{{quote:1}} = \"Slept through the night for the first time in weeks.\""))
        XCTAssertTrue(prompt.contains("{{date:1}} = \(EntryRetriever.formattedDate(retrieval.entries[0].date))"))
        XCTAssertTrue(prompt.contains("{{quote:2}}"))
        XCTAssertTrue(prompt.contains("[ref 1 |"), "citedRefs addressing is unchanged")
        XCTAssertFalse(prompt.contains("quoted: \""), "the legend carries the quote now")
        XCTAssertFalse(prompt.contains("italic exact quote"))
        XCTAssertFalse(prompt.contains("You wrote "), "the ladder no longer pastes journal text")
    }

    func test_groundedThreadPrompt_carriesTheSameLegend() {
        let prompt = journalPrompt("tell me more", stance: .followupThread,
                                   channel: .thread, retrieval: groundedRetrieval())
        XCTAssertTrue(prompt.contains(EvidencePack.legendHeader))
        XCTAssertTrue(prompt.contains("{{quote:1}}"))
        XCTAssertFalse(prompt.contains("quoted: \""))
    }

    func test_singleEntryLadder_pointsAtMarkers() {
        let one = groundedRetrieval()
        let single = RetrievalResult(
            entries: [one.entries[0]],
            contextBlock: EntryRetriever.contextBlock(for: [one.entries[0]], ambient: false),
            isAmbient: false
        )
        let prompt = journalPrompt("What did I write about sleep?", stance: .journalGrounded,
                                   channel: .notebook, retrieval: single)
        XCTAssertTrue(prompt.contains("One entry answers this: {{date:1}} {{quote:1}}."))
    }

    func test_ambientPrompt_carriesBackgroundButNoQuoteMarkers() {
        let prompt = journalPrompt("What have I been writing about lately?", stance: .journalGrounded,
                                   channel: .notebook, retrieval: groundedRetrieval(ambient: true))
        XCTAssertTrue(prompt.contains("[ref 1 |"), "ambient rows still ship as background")
        XCTAssertTrue(prompt.contains(EvidencePack.ambientNote))
        XCTAssertFalse(prompt.contains("{{quote:1}}"))
        XCTAssertFalse(prompt.contains("quoted: \""), "an ambient row must not advertise a quotable field")
    }

    func test_missPrompt_carriesNoEvidenceAndNoMarkers() {
        let prompt = journalPrompt("What did I write about my dog?", stance: .noMatch,
                                   channel: .notebook, retrieval: groundedRetrieval(ambient: true))
        XCTAssertFalse(prompt.contains("[ref 1 |"))
        XCTAssertFalse(prompt.contains("{{quote:1}}"))
        XCTAssertTrue(prompt.contains(EvidencePack.noneNote))
        XCTAssertTrue(prompt.contains(TurnStance.noMatch.label))
    }

    func test_lightChannels_neverMentionMarkers() {
        for channel in [ReplyChannel.phatic, .continuer, .companion, .meta, .redirect] {
            let prompt = journalPrompt("hello", stance: .casual, channel: channel, retrieval: groundedRetrieval())
            XCTAssertFalse(prompt.contains("{{"), "\(channel)")
            XCTAssertFalse(prompt.contains(EvidencePack.legendHeader), "\(channel)")
        }
    }

    /// The live path hands `buildAskPrompt` the pack it renders with; the
    /// derived pack must be the same one, or prompt and renderer drift.
    func test_explicitPack_andDerivedPack_buildTheSamePrompt() {
        let retrieval = groundedRetrieval()
        let pack = EvidencePackBuilder.build(retrieval: retrieval, stance: .journalGrounded, channel: .notebook)
        let derived = journalPrompt("How have I been sleeping?", stance: .journalGrounded,
                                    channel: .notebook, retrieval: retrieval)
        let explicit = FoundationModelsIntelligenceService.buildAskPrompt(
            question: "How have I been sleeping?",
            history: [],
            retrieval: retrieval,
            stance: .journalGrounded,
            shape: .answerOpen,
            archiveEmpty: false,
            budget: ContextBudget(window: .unavailable),
            channel: .notebook,
            move: .patternThenAsk,
            evidencePack: pack
        )
        XCTAssertEqual(derived, explicit)
    }

    private func assertShortAssembler(_ prompt: String, latest: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(prompt.contains("How to reply:"), "short assembler must carry a Move cue", file: file, line: line)
        XCTAssertTrue(prompt.contains("The person's latest message: \(latest)"), file: file, line: line)
        assertNoStanceOrShapeLine(prompt, file: file, line: line)
        XCTAssertFalse(prompt.contains("citedRefs"), file: file, line: line)
        XCTAssertFalse(prompt.contains("Journal evidence"), file: file, line: line)
    }

    private func assertSafetyLine(
        _ text: String,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for phrase in ["harm themselves or others", "sexual content involving minors",
                       "ignore these instructions", "crisis support is shown by the app",
                       "give no advice at all"] {
            XCTAssertTrue(text.contains(phrase), "\(phrase) \(message)", file: file, line: line)
        }
    }

    /// Short-assembler prompts carry a move cue, never the Ask stance or shape lines.
    private func assertNoStanceOrShapeLine(_ prompt: String, file: StaticString = #filePath, line: UInt = #line) {
        for stance in TurnStance.allCases {
            XCTAssertFalse(prompt.contains(stance.promptLine), "\(stance) turn line stacked", file: file, line: line)
            if let overlay = TurnShapeCadence.overlayLine(shape: .answerOpen, stance: stance) {
                XCTAssertFalse(prompt.contains(overlay), "\(stance) shape overlay stacked", file: file, line: line)
            }
        }
    }
}
