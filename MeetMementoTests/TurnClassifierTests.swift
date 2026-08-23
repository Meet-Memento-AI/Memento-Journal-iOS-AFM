import XCTest
@testable import MeetMemento

/// Table-driven coverage of the deterministic turn classifier. The classifier
/// is precision-biased: ambiguous messages must land in a retrieving bucket
/// (share/journalQuery), never silently in a no-retrieval one.
final class TurnClassifierTests: XCTestCase {

    private func classify(_ message: String, hasHistory: Bool = true) -> TurnType {
        TurnClassifier.classify(message, hasHistory: hasHistory)
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

    func test_ambiguousQuestions_defaultToJournalQuery() {
        XCTAssertEqual(classify("hmm what about work stuff?"), .journalQuery)
    }
}
