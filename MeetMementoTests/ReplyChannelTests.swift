import XCTest
@testable import MeetMemento

/// Spec 039 R1: ReplyChannel is the only TurnType → recipe map.
final class ReplyChannelTests: XCTestCase {

    func test_everyTurnType_hasAChannel() {
        let expected: [TurnType: ReplyChannel] = [
            .social: .phatic,
            .acknowledgement: .continuer,
            .meta: .meta,
            .share: .companion,
            .reflectiveQuestion: .companion,
            .followup: .thread,
            .journalQuery: .notebook,
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
    }

    func test_lightPrompt_onlyPhaticAndContinuer() {
        XCTAssertTrue(ReplyChannel.phatic.usesLightPrompt)
        XCTAssertTrue(ReplyChannel.continuer.usesLightPrompt)
        for channel in ReplyChannel.allCases where channel != .phatic && channel != .continuer {
            XCTAssertFalse(channel.usesLightPrompt, "\(channel)")
        }
    }

    func test_omitsLens_phaticContinuerRedirect() {
        XCTAssertTrue(ReplyChannel.phatic.omitsLens)
        XCTAssertTrue(ReplyChannel.continuer.omitsLens)
        XCTAssertTrue(ReplyChannel.redirect.omitsLens)
        XCTAssertFalse(ReplyChannel.companion.omitsLens)
        XCTAssertFalse(ReplyChannel.notebook.omitsLens)
        XCTAssertFalse(ReplyChannel.meta.omitsLens)
        XCTAssertFalse(ReplyChannel.thread.omitsLens)
    }

    func test_allowsRetrieval_notebookAndThreadOnly() {
        XCTAssertTrue(ReplyChannel.notebook.allowsRetrieval)
        XCTAssertTrue(ReplyChannel.thread.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.phatic.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.continuer.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.companion.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.meta.allowsRetrieval)
        XCTAssertFalse(ReplyChannel.redirect.allowsRetrieval)
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
    }

    func test_socialRetrieval_isNone() {
        XCTAssertEqual(RetrievalPolicy.mode(for: .social), .none)
        XCTAssertEqual(RetrievalPolicy.mode(for: .acknowledgement), .none)
    }
}
