import XCTest
@testable import MeetMemento

/// Spec 049 S1: the pipeline shell returns today's channel. No prompt change.
final class AskPipelineTests: XCTestCase {

    func test_plan_matchesReplyChannel_forEveryTurn() {
        let expected: [TurnType: ReplyChannel] = [
            .social: .phatic,
            .acknowledgement: .continuer,
            .meta: .meta,
            .share: .companion,
            .reflectiveQuestion: .companion,
            .followup: .thread,
            .journalQuery: .notebook,
            .quantitative: .statistic,
            .offdomain: .redirect,
            .correction: .thread
        ]
        for turn in TurnType.allCases {
            let plan = AskPipeline.plan(turn: turn, hasImages: false)
            XCTAssertEqual(plan.channel, ReplyChannel.resolve(turn: turn, hasImages: false), "\(turn)")
            XCTAssertEqual(plan.channel, expected[turn], "\(turn)")
            XCTAssertEqual(plan.turn, turn)
            XCTAssertEqual(
                plan.usesBodyOnlySchema,
                plan.channel.usesBodyOnlySchema(spoken: false)
            )
        }
    }

    func test_photoBump_matchesReplyChannel() {
        let bumped: [TurnType] = [.social, .acknowledgement]
        for turn in bumped {
            let plan = AskPipeline.plan(turn: turn, hasImages: true)
            XCTAssertEqual(plan.channel, .companion)
            XCTAssertEqual(plan.channel, ReplyChannel.resolve(turn: turn, hasImages: true))
        }
        let held: [TurnType: ReplyChannel] = [
            .journalQuery: .notebook,
            .meta: .meta,
            .share: .companion,
            .offdomain: .redirect,
            .followup: .thread,
            .quantitative: .statistic,
            .reflectiveQuestion: .companion,
            .correction: .thread
        ]
        for (turn, channel) in held {
            let plan = AskPipeline.plan(turn: turn, hasImages: true)
            XCTAssertEqual(plan.channel, channel)
            XCTAssertEqual(plan.channel, ReplyChannel.resolve(turn: turn, hasImages: true))
        }
    }

    func test_emptyArchive_journalQuestion_isNotNotebook() {
        let plan = AskPipeline.plan(turn: .journalQuery, hasImages: false, evidence: .none)
        print("evidence=\(plan.evidence.rawValue) channel=\(plan.channel.rawValue)")
        XCTAssertEqual(plan.evidence, .none)
        XCTAssertNotEqual(plan.channel, .notebook)
        XCTAssertNotEqual(plan.channel, .thread)
        XCTAssertTrue(plan.usesBodyOnlySchema)
    }
}
