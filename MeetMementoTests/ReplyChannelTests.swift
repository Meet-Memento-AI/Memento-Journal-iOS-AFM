import XCTest
@testable import MeetMemento

/// Spec 039 R1: ReplyChannel is the only TurnType → recipe map.
final class ReplyChannelTests: XCTestCase {

    override func tearDown() {
        PromptExperiments.reset()
        super.tearDown()
    }

    func test_everyTurnType_hasAChannel() {
        let expected: [TurnType: ReplyChannel] = [
            .social: .phatic,
            .acknowledgement: .continuer,
            .meta: .meta,
            .share: .companion,
            .reflectiveQuestion: .companion,
            .followup: .thread,
            .journalQuery: .notebook,
            .quantitative: .statistic,
            .offdomain: .redirect
        ]
        for turn in TurnType.allCases {
            let channel = ReplyChannel.resolve(turn: turn, hasImages: false)
            XCTAssertEqual(channel, expected[turn], "\(turn)")
        }
    }

    func test_photoBump_neverPhaticOrContinuer() {
        XCTAssertEqual(ReplyChannel.resolve(turn: .social, hasImages: true), .companion)
        XCTAssertEqual(ReplyChannel.resolve(turn: .acknowledgement, hasImages: true), .companion)
        XCTAssertEqual(ReplyChannel.resolve(turn: .journalQuery, hasImages: true), .notebook)
        XCTAssertEqual(ReplyChannel.resolve(turn: .meta, hasImages: true), .meta)
        XCTAssertEqual(ReplyChannel.resolve(turn: .share, hasImages: true), .companion)
        XCTAssertEqual(ReplyChannel.resolve(turn: .offdomain, hasImages: true), .redirect)
        XCTAssertEqual(ReplyChannel.resolve(turn: .followup, hasImages: true), .thread)
        XCTAssertEqual(ReplyChannel.resolve(turn: .quantitative, hasImages: true), .statistic)
    }

    func test_lightPrompt_onlyPhaticContinuerAndStatistic() {
        XCTAssertTrue(ReplyChannel.phatic.usesLightPrompt)
        XCTAssertTrue(ReplyChannel.continuer.usesLightPrompt)
        XCTAssertTrue(ReplyChannel.statistic.usesLightPrompt)
        for channel in ReplyChannel.allCases
            where channel != .phatic && channel != .continuer && channel != .statistic {
            XCTAssertFalse(channel.usesLightPrompt, "\(channel)")
        }
    }

    func test_companionPrompt_shareMetaRedirect() {
        XCTAssertTrue(ReplyChannel.companion.usesCompanionPrompt)
        XCTAssertTrue(ReplyChannel.meta.usesCompanionPrompt)
        XCTAssertTrue(ReplyChannel.redirect.usesCompanionPrompt)
        XCTAssertFalse(ReplyChannel.phatic.usesCompanionPrompt)
        XCTAssertFalse(ReplyChannel.notebook.usesCompanionPrompt)
        XCTAssertFalse(ReplyChannel.thread.usesCompanionPrompt)
        XCTAssertFalse(ReplyChannel.statistic.usesCompanionPrompt)
        XCTAssertTrue(ReplyChannel.phatic.usesShortAssembler)
        XCTAssertTrue(ReplyChannel.continuer.usesShortAssembler)
        XCTAssertTrue(ReplyChannel.companion.usesShortAssembler)
        XCTAssertTrue(ReplyChannel.meta.usesShortAssembler)
        XCTAssertTrue(ReplyChannel.redirect.usesShortAssembler)
        XCTAssertFalse(ReplyChannel.notebook.usesShortAssembler)
        XCTAssertFalse(ReplyChannel.thread.usesShortAssembler)
        XCTAssertTrue(ReplyChannel.statistic.usesShortAssembler)
    }

    func test_bodyOnlySchema_companionMetaAndLight() {
        XCTAssertTrue(ReplyChannel.phatic.usesBodyOnlySchema())
        XCTAssertTrue(ReplyChannel.continuer.usesBodyOnlySchema())
        XCTAssertTrue(ReplyChannel.redirect.usesBodyOnlySchema())
        XCTAssertTrue(ReplyChannel.companion.usesBodyOnlySchema())
        XCTAssertTrue(ReplyChannel.meta.usesBodyOnlySchema())
        XCTAssertFalse(ReplyChannel.notebook.usesBodyOnlySchema())
        XCTAssertFalse(ReplyChannel.thread.usesBodyOnlySchema())
        XCTAssertTrue(ReplyChannel.statistic.usesBodyOnlySchema())
    }

    func test_bodyOnlySchema_spokenDoesNotOverrideJournal() {
        XCTAssertTrue(ReplyChannel.companion.usesBodyOnlySchema(spoken: true))
        XCTAssertTrue(ReplyChannel.meta.usesBodyOnlySchema(spoken: true))
        XCTAssertTrue(ReplyChannel.phatic.usesBodyOnlySchema(spoken: true))
        XCTAssertTrue(ReplyChannel.redirect.usesBodyOnlySchema(spoken: true))
        XCTAssertFalse(ReplyChannel.notebook.usesBodyOnlySchema(spoken: true))
        XCTAssertFalse(ReplyChannel.thread.usesBodyOnlySchema(spoken: true))
        XCTAssertFalse(ReplyChannel.notebook.usesBodyOnlySchema(spoken: false))
        XCTAssertFalse(ReplyChannel.thread.usesBodyOnlySchema(spoken: false))
    }

    func test_spokenFollowUp_noJournalAnchor_usesCompanion() {
        let history = [
            ChatTurn(role: .user, text: "I had a rough day at work"),
            ChatTurn(role: .assistant, text: "How did that feel?")
        ]
        let channel = ReplyChannel.resolve(turn: .followup, hasImages: false)
            .applyingSpokenFollowUpRecipe(turn: .followup, history: history, spoken: true)
        XCTAssertEqual(channel, .companion)
        XCTAssertTrue(channel.usesCompanionPrompt)
        XCTAssertTrue(channel.usesBodyOnlySchema(spoken: true))
    }

    func test_spokenFollowUp_journalAnchor_staysThread() {
        let history = [
            ChatTurn(role: .user, text: "What did I write about the hike?"),
            ChatTurn(role: .assistant, text: "You went up Mount Tamalpais with Maya.")
        ]
        let channel = ReplyChannel.resolve(turn: .followup, hasImages: false)
            .applyingSpokenFollowUpRecipe(turn: .followup, history: history, spoken: true)
        XCTAssertEqual(channel, .thread)
        XCTAssertTrue(channel.allowsRetrieval)
        XCTAssertEqual(RetrievalPolicy.mode(for: .followup, history: history), .reusePrevious)
    }

    func test_typedFollowUp_neverDowngradesToCompanion() {
        let history = [
            ChatTurn(role: .user, text: "I had a rough day at work"),
            ChatTurn(role: .assistant, text: "How did that feel?")
        ]
        let channel = ReplyChannel.resolve(turn: .followup, hasImages: false)
            .applyingSpokenFollowUpRecipe(turn: .followup, history: history, spoken: false)
        XCTAssertEqual(channel, .thread)
    }

    func test_omitsLens_phaticContinuerRedirect() {
        XCTAssertTrue(ReplyChannel.phatic.omitsLens)
        XCTAssertTrue(ReplyChannel.continuer.omitsLens)
        XCTAssertTrue(ReplyChannel.redirect.omitsLens)
        XCTAssertFalse(ReplyChannel.companion.omitsLens)
        XCTAssertFalse(ReplyChannel.notebook.omitsLens)
        XCTAssertFalse(ReplyChannel.meta.omitsLens)
        XCTAssertFalse(ReplyChannel.thread.omitsLens)
        XCTAssertTrue(ReplyChannel.statistic.omitsLens)
    }

    func test_statistic_doesNotRequireOnDeviceModel() {
        XCTAssertFalse(ReplyChannel.statistic.requiresOnDeviceModel)
        for channel in ReplyChannel.allCases where channel != .statistic {
            XCTAssertTrue(channel.requiresOnDeviceModel, "\(channel)")
        }
    }

    func test_allowsRetrieval_notebookAndThreadOnly() {
        XCTAssertTrue(ReplyChannel.notebook.allowsRetrieval)
        XCTAssertTrue(ReplyChannel.thread.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.phatic.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.continuer.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.companion.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.meta.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.redirect.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.statistic.allowsRetrieval)
    }

    func test_tokenCaps() {
        XCTAssertEqual(ReplyChannel.phatic.maximumResponseTokens(retrievalRan: false), 80)
        XCTAssertEqual(ReplyChannel.continuer.maximumResponseTokens(retrievalRan: false), 64)
        XCTAssertEqual(ReplyChannel.companion.maximumResponseTokens(retrievalRan: false), 128)
        XCTAssertEqual(ReplyChannel.meta.maximumResponseTokens(retrievalRan: false), 128)
        XCTAssertEqual(ReplyChannel.redirect.maximumResponseTokens(retrievalRan: false), 80)
        // Both, deliberately. A follow-up runs the full ask@14 recipe whether or
        // not retrieval hit, and the old 128 truncated every measured one of
        // them mid-sentence, before the closing question ask@14 requires.
        XCTAssertEqual(ReplyChannel.thread.maximumResponseTokens(retrievalRan: false), 512)
        XCTAssertEqual(ReplyChannel.thread.maximumResponseTokens(retrievalRan: true), 512)
        XCTAssertEqual(ReplyChannel.notebook.maximumResponseTokens(retrievalRan: false), 512)
        XCTAssertEqual(ReplyChannel.notebook.maximumResponseTokens(retrievalRan: true), 512)
        XCTAssertEqual(ReplyChannel.statistic.maximumResponseTokens(retrievalRan: false), 64)
        XCTAssertEqual(ReplyChannel.statistic.maximumResponseTokens(retrievalRan: true), 64)
    }

    func test_typedNotebookCap256_killSwitch_doesNotRaiseSpoken() {
        PromptExperiments.reset()
        XCTAssertEqual(ReplyChannel.notebook.maximumResponseTokens(retrievalRan: true), 512)
        XCTAssertEqual(ReplyChannel.thread.maximumResponseTokens(retrievalRan: false), 512)
        PromptExperiments.typedNotebookCap256 = true
        XCTAssertEqual(ReplyChannel.notebook.maximumResponseTokens(retrievalRan: true), 256)
        XCTAssertEqual(ReplyChannel.thread.maximumResponseTokens(retrievalRan: false), 256)
        XCTAssertEqual(ReplyChannel.notebook.maximumResponseTokens(retrievalRan: true, spoken: true), 256)
        XCTAssertEqual(ReplyChannel.phatic.maximumResponseTokens(retrievalRan: false), 80)
        PromptExperiments.reset()
    }

    func test_spokenCaps_neverRaiseAndShortenNotebookThread() {
        XCTAssertEqual(ReplyChannel.companion.maximumResponseTokens(retrievalRan: false, spoken: true), 80)
        XCTAssertEqual(ReplyChannel.companion.maximumResponseTokens(retrievalRan: false, spoken: false), 128)
        XCTAssertEqual(ReplyChannel.meta.maximumResponseTokens(retrievalRan: false, spoken: true), 128)
        XCTAssertEqual(ReplyChannel.thread.maximumResponseTokens(retrievalRan: false, spoken: true), 256)
        XCTAssertEqual(ReplyChannel.thread.maximumResponseTokens(retrievalRan: true, spoken: true), 256)
        XCTAssertEqual(ReplyChannel.notebook.maximumResponseTokens(retrievalRan: false, spoken: true), 256)
        XCTAssertEqual(ReplyChannel.notebook.maximumResponseTokens(retrievalRan: true, spoken: true), 256)
        XCTAssertEqual(ReplyChannel.phatic.maximumResponseTokens(retrievalRan: false, spoken: true), 80)
    }

    func test_temperature() {
        XCTAssertEqual(ReplyChannel.phatic.temperature, 0.9)
        XCTAssertEqual(ReplyChannel.continuer.temperature, 0.9)
        XCTAssertEqual(ReplyChannel.companion.temperature, 0.9)
        XCTAssertEqual(ReplyChannel.meta.temperature, 0.9)
        XCTAssertEqual(ReplyChannel.redirect.temperature, 0.9)
        XCTAssertEqual(ReplyChannel.notebook.temperature, 0.7)
        XCTAssertEqual(ReplyChannel.thread.temperature(retrievalRan: true), 0.7)
        XCTAssertEqual(ReplyChannel.thread.temperature(retrievalRan: false), 0.9)
        XCTAssertEqual(ReplyChannel.statistic.temperature, 0.9)
    }

    func test_socialRetrieval_isNone() {
        XCTAssertEqual(RetrievalPolicy.mode(for: .social), .none)
        XCTAssertEqual(RetrievalPolicy.mode(for: .acknowledgement), .none)
    }

    // MARK: Chat-speed: speculative pool covers every live recipe

    /// Every channel a live on-device send can resolve to must hash to a plan
    /// the pool warmed — with and without a lens, first turn and follow-up.
    /// A channel missing here is a guaranteed speculative miss (cold prefill
    /// on TTFT) for every turn that lands on it.
    func test_speculativeChannels_coverEveryOnDeviceRecipe() {
        let budget = ContextBudget(window: .unavailable)
        let lensed = PromptPersonalization(
            firstName: "Ada",
            reflection: "I want to notice when I am overcommitting.",
            goals: [],
            promptLens: nil
        )
        let histories: [[ChatTurn]] = [
            [],
            [
                ChatTurn(role: .user, text: "What did I write about the hike?"),
                ChatTurn(role: .assistant, text: "You were up the mountain with Maya.")
            ]
        ]
        for personalization in [PromptPersonalization.none, lensed] {
            for history in histories {
                let warmed = Set(ReplyChannel.speculativeChannels.map {
                    AskTranscriptPlan.forAsk(
                        channel: $0, stored: personalization, history: history, budget: budget
                    ).plan.fingerprint
                })
                for channel in ReplyChannel.allCases where channel.requiresOnDeviceModel {
                    let live = AskTranscriptPlan.forAsk(
                        channel: channel,
                        stored: personalization,
                        history: history,
                        budget: budget,
                        zone: .z0Device,
                        degraded: false
                    ).plan.fingerprint
                    XCTAssertTrue(
                        warmed.contains(live),
                        "\(channel) (lens: \(personalization.hasAskPersonalization), turns: \(history.count)) misses the pool"
                    )
                }
            }
        }
    }

    /// Thread is its own recipe (ask-core@16 + follow-up suffix), so the
    /// follow-up turn needs its own slot — notebook alone never matched it.
    func test_threadRecipe_isDistinctFromNotebook() {
        let budget = ContextBudget(window: .unavailable)
        let history = [ChatTurn(role: .user, text: "Tell me more about that week.")]
        let thread = AskTranscriptPlan.forAsk(
            channel: .thread, stored: .none, history: history, budget: budget
        )
        let notebook = AskTranscriptPlan.forAsk(
            channel: .notebook, stored: .none, history: history, budget: budget
        )
        XCTAssertNotEqual(thread.plan.fingerprint, notebook.plan.fingerprint)
        XCTAssertTrue(ReplyChannel.speculativeChannels.contains(.thread))
        XCTAssertFalse(ReplyChannel.speculativeChannels.contains(.statistic))
    }

    /// `forAsk` applies the lens rule itself, so a caller can never warm a
    /// lensed redirect and serve a lens-free one (or vice versa).
    func test_forAsk_omitsLensOnLensFreeChannels() {
        let budget = ContextBudget(window: .unavailable)
        let lensed = PromptPersonalization(
            firstName: "Ada", reflection: "Noticing overcommitting.", goals: [], promptLens: nil
        )
        for channel in ReplyChannel.allCases where channel.omitsLens {
            let with = AskTranscriptPlan.forAsk(channel: channel, stored: lensed, history: [], budget: budget)
            let without = AskTranscriptPlan.forAsk(channel: channel, stored: .none, history: [], budget: budget)
            XCTAssertEqual(with.plan.fingerprint, without.plan.fingerprint, "\(channel)")
            XCTAssertEqual(with.resolved.version, without.resolved.version, "\(channel)")
        }
        let companion = AskTranscriptPlan.forAsk(channel: .companion, stored: lensed, history: [], budget: budget)
        XCTAssertTrue(companion.resolved.version.hasSuffix("+p4"))
    }
}
