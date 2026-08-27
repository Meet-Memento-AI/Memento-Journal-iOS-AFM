import XCTest
@testable import MeetMemento

/// Table-driven coverage of the deterministic turn classifier. The classifier
/// is precision-biased: ambiguous messages must land in a retrieving bucket
/// (share/journalQuery), never silently in a no-retrieval one.
final class TurnClassifierTests: XCTestCase {

    private func classify(
        _ message: String,
        hasHistory: Bool = true,
        lastAssistantAskedQuestion: Bool = false
    ) -> TurnType {
        TurnClassifier.classify(
            message,
            hasHistory: hasHistory,
            lastAssistantAskedQuestion: lastAssistantAskedQuestion
        )
    }

    // MARK: - Social

    func test_greetings_areSocial() {
        for message in ["hey", "Hi!", "hello", "Good morning", "how are you?", "what's up", "Thanks!", "thank you so much"] {
            XCTAssertEqual(classify(message), .social, "\(message)")
        }
    }

    func test_greetingWithName_isSocial() {
        XCTAssertEqual(classify("hey memento"), .social)
        XCTAssertEqual(classify("hello Memento"), .social)
        XCTAssertEqual(classify("hey there"), .social)
    }

    func test_compoundGreeting_isSocial() {
        XCTAssertEqual(classify("Hello, how are you"), .social)
        XCTAssertEqual(classify("hello, how are you"), .social)
        XCTAssertEqual(classify("how are you"), .social)
    }

    func test_greetingPlusJournalAsk_staysJournalQuery() {
        XCTAssertEqual(classify("hello, what did I write about work?"), .journalQuery)
    }

    // MARK: - Acknowledgement

    func test_continuers_areAcknowledgement() {
        for message in ["yeah", "ok", "haha", "ok cool", "makes sense", "i guess", "lol", "wow", "ok thanks"] {
            XCTAssertEqual(classify(message), .acknowledgement, "\(message)")
        }
    }

    func test_emptyMessage_isAcknowledgement() {
        XCTAssertEqual(classify("   "), .acknowledgement)
    }

    // MARK: - Meta

    func test_capabilityQuestions_areMeta() {
        for message in ["what can you do?", "who are you", "are you an AI?", "help"] {
            XCTAssertEqual(classify(message), .meta, "\(message)")
        }
    }

    // MARK: - Followup

    func test_followupPhrases_needHistory() {
        XCTAssertEqual(classify("tell me more", hasHistory: true), .followup)
        XCTAssertEqual(classify("what do you mean?", hasHistory: true), .followup)
        XCTAssertEqual(classify("like what?", hasHistory: true), .followup)
        XCTAssertEqual(classify("why?", hasHistory: true), .followup)
    }

    func test_followupWithoutHistory_fallsThrough() {
        XCTAssertNotEqual(classify("tell me more", hasHistory: false), .followup)
        XCTAssertNotEqual(classify("why?", hasHistory: false), .followup)
    }

    func test_deicticShortQuestion_isFollowup() {
        XCTAssertEqual(classify("what about that?", hasHistory: true), .followup)
    }

    /// A follow-up phrase is matched by prefix/suffix, so a real journal ask
    /// that merely opens politely used to be swallowed as a continuer. That
    /// misroute is not cosmetic: `.followup` re-runs retrieval against the
    /// *previous* question's text, so the reply answers the wrong question.
    ///
    /// The rule: a continuer has no content of its own. Once the message names
    /// the journal or a span, it is a new ask.
    func test_followupPhrase_doesNotSwallowAJournalAsk() {
        let cases = [
            "what else did I write that week?",
            "tell me more about what I wrote in March",
            "anything else in my journal about work?",
            "say more — did I log anything about sleep?"
        ]
        for message in cases {
            XCTAssertEqual(classify(message, hasHistory: true), .journalQuery,
                           "\"\(message)\" carries its own journal ask")
        }
    }

    /// The other half of the same boundary: a bare continuer stays a continuer
    /// even when the conversation it follows was about the journal.
    func test_bareContinuer_staysFollowup_evenAfterAJournalTurn() {
        for message in ["tell me more", "what else?", "say more", "go on"] {
            XCTAssertEqual(classify(message, hasHistory: true), .followup, "\(message)")
        }
    }

    // MARK: - Journal query

    func test_journalLexicon_isJournalQuery() {
        for message in ["what did I write about work?", "summarize my journal entries", "show me my entries about mom", "have I logged anything about sleep"] {
            XCTAssertEqual(classify(message), .journalQuery, "\(message)")
        }
    }

    func test_retrospectiveShapes_areJournalQuery() {
        for message in ["have I been stressed lately?", "how often do I mention running?", "when did I last feel this way"] {
            XCTAssertEqual(classify(message), .journalQuery, "\(message)")
        }
    }

    // MARK: - Reflective

    func test_reflectivePatterns() {
        XCTAssertEqual(classify("why do I keep procrastinating?"), .reflectiveQuestion)
        XCTAssertEqual(classify("why am I always so anxious on Sundays?"), .reflectiveQuestion)
        XCTAssertEqual(classify("how can I stop overthinking everything?"), .reflectiveQuestion)
    }

    // MARK: - Offdomain

    func test_worldFactQuestions_areOffdomain() {
        XCTAssertEqual(classify("what is the capital of France?"), .offdomain)
        XCTAssertEqual(classify("who won the game last night?"), .offdomain)
    }

    func test_selfReferencingQuestion_isNeverOffdomain() {
        XCTAssertNotEqual(classify("what should I do about my job?"), .offdomain)
    }

    // MARK: - Defaults (ambiguity retrieves)

    func test_statements_defaultToShare() {
        XCTAssertEqual(classify("today was exhausting, back to back meetings all day"), .share)
        XCTAssertEqual(classify("I finally talked to my sister"), .share)
    }

    func test_answerWithoutDeixis_afterOpenQuestion_isFollowup() {
        XCTAssertEqual(
            classify("it was actually pretty heavy", lastAssistantAskedQuestion: true),
            .followup
        )
        XCTAssertEqual(
            classify("pretty good honestly", lastAssistantAskedQuestion: true),
            .followup
        )
    }

    func test_answerWithoutLastQuestion_staysShare() {
        XCTAssertEqual(classify("it was actually pretty heavy"), .share)
    }

    func test_journalAsk_afterOpenQuestion_staysJournalQuery() {
        XCTAssertEqual(
            classify("what did I write last week?", lastAssistantAskedQuestion: true),
            .journalQuery
        )
    }

    func test_offdomain_afterOpenQuestion_staysOffdomain() {
        XCTAssertEqual(
            classify("who won the game last night?", lastAssistantAskedQuestion: true),
            .offdomain
        )
    }

    func test_social_afterOpenQuestion_staysSocial() {
        XCTAssertEqual(classify("hey", lastAssistantAskedQuestion: true), .social)
    }

    func test_ambiguousQuestions_defaultToJournalQuery() {
        XCTAssertEqual(classify("hmm what about work stuff?"), .journalQuery)
    }
}
