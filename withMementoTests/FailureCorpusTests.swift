import XCTest
@testable import MeetMemento

/// Deterministic checks for the September failure corpus. Generation stays
/// serial and off this suite; the route, the ladder, and the scorers are
/// what these fixtures pin.
final class FailureCorpusTests: XCTestCase {

    func test_rat_mustNotClaimFirstPersonPerception() {
        let question = "Saw a rat in the lab fridge"
        let turn = TurnClassifier.classify(question, hasHistory: false)
        XCTAssertEqual(turn, .share)
        let shape = QuestionShapeResolver.shape(of: question, turn: turn)
        XCTAssertEqual(ResponsePolicyResolver.policy(shape: shape), .reflect)
        let claimed = ChatEvalScoring.firstPersonPerception("I saw that rat too.")
        XCTAssertFalse(claimed.isEmpty)
        let allowed = ChatEvalScoring.firstPersonPerception("I hear you. I'm here.")
        XCTAssertTrue(allowed.isEmpty)
    }

    func test_interpretationCut_retractsInsteadOfAnotherMetaphor() {
        let question = "You're reading too much into the silence"
        let turn = TurnClassifier.classify(question, hasHistory: true)
        XCTAssertEqual(turn, .correction)
        let shape = QuestionShapeResolver.shape(of: question, turn: turn)
        XCTAssertEqual(shape, .interpretationCut)
        XCTAssertEqual(ResponsePolicyResolver.policy(shape: shape), .retract)
        let suffix = PromptRegistry.policySuffix(.reflect, interpretationCut: true)
        XCTAssertTrue(suffix.contains("Stay on their words"))
        let metaphor = ChatEvalScoring.narrativeJoin(
            "You're holding the weight of that silence.",
            userTurn: question
        )
        XCTAssertFalse(metaphor.isEmpty)
    }

    func test_nextStepList_isAListPolicy() {
        let question = "Give me a next-step list"
        let turn = TurnClassifier.classify(question, hasHistory: false)
        let shape = QuestionShapeResolver.shape(of: question, turn: turn)
        XCTAssertEqual(shape, .list)
        XCTAssertEqual(ResponsePolicyResolver.policy(shape: shape), .list)
        XCTAssertTrue(PromptRegistry.policySuffix(.list).contains("two or three options"))
    }

    func test_workSituation_isListNotDistress() {
        let question = "What should I do about the work situation"
        let shape = QuestionShapeResolver.shape(
            of: question,
            turn: TurnClassifier.classify(question, hasHistory: false)
        )
        XCTAssertEqual(ResponsePolicyResolver.policy(shape: shape), .list)
    }

    func test_correction_retractsAndIsNotAGuardrail() {
        let question = "You got that wrong"
        let turn = TurnClassifier.classify(question, hasHistory: true)
        XCTAssertEqual(turn, .correction)
        XCTAssertNotEqual(turn, .share)
        let decision = SafetyRouter.decide(question)
        XCTAssertNotEqual(decision.action, .hardRefuse)
        XCTAssertNotEqual(decision.action, .showCrisisCard)
        let shape = QuestionShapeResolver.shape(of: question, turn: turn)
        XCTAssertEqual(ResponsePolicyResolver.policy(shape: shape), .retract)
        let channel = ReplyChannel.resolve(turn: turn, hasImages: false, evidence: .matched)
        XCTAssertEqual(channel, .thread)
    }

    func test_whoIsDario_emptyIsNone_coldCitesWithoutDenying() throws {
        let question = "Who is Dario"
        let emptyChannel = ReplyChannel.resolve(turn: .journalQuery, hasImages: false, evidence: .none)
        XCTAssertNotEqual(emptyChannel, .notebook)
        XCTAssertNotEqual(emptyChannel, .thread)
        let emptyStance = RetrievalPolicy.stance(
            turn: .journalQuery, retrieval: .empty, question: question
        )
        XCTAssertEqual(
            EvidenceLadder.rung(stance: emptyStance, retrieval: .empty, question: question),
            .none
        )
        XCTAssertEqual(
            EvidenceLadder.promptLine(.none, retrieval: .empty),
            "I can't find an entry that supports that."
        )

        let (entries, ids) = try ChatEvalCorpus.coldStartCorpus()
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: question),
            entries: entries
        )
        let cited = result.entries.compactMap { ids[$0.id] }
        XCTAssertTrue(cited.contains("cs-02"), "cited \(cited)")
        let stance = RetrievalPolicy.stance(turn: .journalQuery, retrieval: result, question: question)
        let rung = EvidenceLadder.rung(stance: stance, retrieval: result, question: question)
        XCTAssertNotEqual(rung, .none)
        let line = EvidenceLadder.promptLine(rung, retrieval: result).lowercased()
        XCTAssertFalse(line.contains("closest"))
        XCTAssertFalse(line.contains("can't find"))
    }

    func test_beforePottery_doesNotOpenOnThePotteryEntry() throws {
        let (entries, ids) = try ChatEvalCorpus.coldStartCorpus()
        let question = "What was bothering me before the pottery class"
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: question),
            entries: entries
        )
        XCTAssertFalse(result.entries.contains { ids[$0.id] == "cs-01" })
    }

    func test_goodbye_doesNotAskWhatTheyAreHolding() {
        let shape = QuestionShapeResolver.shape(of: "goodbye", turn: .social)
        XCTAssertEqual(ResponsePolicyResolver.policy(shape: shape), .acknowledge)
        let breaks = ChatEvalScoring.ruleBreaks(
            "Goodnight.",
            isCasual: true,
            openRequired: ResponsePolicyResolver.openRequired(policy: .acknowledge, bodyIsEmpty: false)
        )
        XCTAssertFalse(breaks.contains { $0.code == "rule.noOpen" })
        XCTAssertFalse(PromptRegistry.policySuffix(.acknowledge).lowercased().contains("holding onto"))
    }

    func test_counterfactualPairs_differByLadder() {
        XCTAssertEqual(ChatEvalCorpus.counterfactualPairs.count, 2)
        for pair in ChatEvalCorpus.counterfactualPairs {
            let present = RetrievalResult(
                entries: [
                    RetrievedEntry(
                        ref: 1,
                        id: pair.present.id,
                        date: pair.present.createdAt,
                        text: pair.present.text
                    )
                ],
                contextBlock: pair.present.text,
                isAmbient: false
            )
            let presentRung = EvidenceLadder.rung(
                stance: .journalGrounded, retrieval: present, question: pair.question
            )
            let absentRung = EvidenceLadder.rung(
                stance: .noMatch, retrieval: .empty, question: pair.question
            )
            XCTAssertNotEqual(presentRung, absentRung, pair.id)
            XCTAssertEqual(absentRung, .none, pair.absentNote)
            XCTAssertNotEqual(
                EvidenceLadder.promptLine(presentRung, retrieval: present),
                EvidenceLadder.promptLine(absentRung, retrieval: .empty)
            )
        }
    }
}
