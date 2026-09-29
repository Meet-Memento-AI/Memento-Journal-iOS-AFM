import XCTest
@testable import withMemento

final class ConversationQualityTests: XCTestCase {

    func test_telemetry_questionClosedAndContraction() {
        let turn = ConversationQualityTurn(
            body: "That run sounded rough — what part is still with you?",
            latestUserMessage: "My knee hurt after the run.",
            priorAssistantBodies: [],
            turnType: .share,
            questionShape: .venting,
            responsePolicy: .reflect,
            channel: .companion,
            evidenceState: .none,
            placedEvidence: false,
            exactRung: false,
            isMetaTurn: false,
            isCrisisTurn: false,
            spoken: false
        )
        let telemetry = ConversationQuality.telemetry(for: turn)
        XCTAssertTrue(telemetry.questionClosed)
        XCTAssertTrue(telemetry.contractionPresent)
        XCTAssertFalse(telemetry.repeatedOpening)
    }

    func test_conv_stockEmpathy_and_clinical() {
        let turn = ConversationQualityTurn(
            body: "Thank you for sharing. The entry indicates stress.",
            latestUserMessage: "Work was a lot.",
            priorAssistantBodies: [],
            turnType: .share,
            questionShape: .venting,
            responsePolicy: .reflect,
            channel: .companion,
            evidenceState: .none,
            placedEvidence: false,
            exactRung: false,
            isMetaTurn: false,
            isCrisisTurn: false,
            spoken: false
        )
        let codes = ChatEvalScoring.conversation(turn).map(\.code)
        XCTAssertTrue(codes.contains("conv.stockEmpathy"))
        XCTAssertTrue(codes.contains("conv.clinical"))
    }

    func test_conv_repeatedOpening() {
        let prior = ConversationQualityTurn(
            body: "That sounds heavy. What shifted?",
            latestUserMessage: "Tired.",
            priorAssistantBodies: [],
            turnType: .share,
            questionShape: .venting,
            responsePolicy: .reflect,
            channel: .companion,
            evidenceState: .none,
            placedEvidence: false,
            exactRung: false,
            isMetaTurn: false,
            isCrisisTurn: false,
            spoken: false
        )
        _ = ChatEvalScoring.conversation(prior)
        let repeatTurn = ConversationQualityTurn(
            body: "That sounds heavy again. What now?",
            latestUserMessage: "Still tired.",
            priorAssistantBodies: ["That sounds heavy. What shifted?"],
            turnType: .followup,
            questionShape: .specific,
            responsePolicy: .answer,
            channel: .thread,
            evidenceState: .none,
            placedEvidence: false,
            exactRung: false,
            isMetaTurn: false,
            isCrisisTurn: false,
            spoken: false
        )
        XCTAssertTrue(ChatEvalScoring.conversation(repeatTurn).contains {
            $0.code == "conv.repeatedOpening"
        })
    }

    func test_conv_codes_do_not_gate() {
        let violation = ChatEvalScoring.Violation(code: "conv.clinical", detail: "the user")
        XCTAssertTrue(ChatEvalScoring.gating([violation]).isEmpty)
    }

    func test_renderStats_logLine_includes_cq_counters() {
        var stats = ReplyRenderStats(packState: .none, slotCount: 0)
        stats.questionClosed = true
        stats.hedgeCount = 2
        XCTAssertTrue(stats.logLine.contains("q_closed=1"))
        XCTAssertTrue(stats.logLine.contains("hedges=2"))
    }
}
