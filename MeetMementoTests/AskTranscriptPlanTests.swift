import XCTest
@testable import MeetMemento

final class AskTranscriptPlanTests: XCTestCase {

    override func tearDown() {
        PromptExperiments.reset()
        super.tearDown()
    }

    func test_lightAndHeavyFingerprintsDiffer_sameHistory() {
        let history = [
            ChatTurn(role: .user, text: "hello"),
            ChatTurn(role: .assistant, text: "Hey. How's the morning?")
        ]
        let budget = ContextBudget(window: .unavailable)
        let light = AskTranscriptPlan.build(
            instructions: PromptRegistry.instructions(for: .ask, channel: .phatic).text,
            history: history,
            budget: budget
        )
        let heavy = AskTranscriptPlan.build(
            instructions: PromptRegistry.instructions(for: .ask, channel: .notebook).text,
            history: history,
            budget: budget
        )
        let companion = AskTranscriptPlan.build(
            instructions: PromptRegistry.instructions(for: .ask, channel: .companion).text,
            history: history,
            budget: budget
        )
        XCTAssertNotEqual(light.fingerprint, heavy.fingerprint)
        XCTAssertNotEqual(light.fingerprint, companion.fingerprint)
        XCTAssertNotEqual(companion.fingerprint, heavy.fingerprint)
    }

    func test_fingerprintPool_adoptIsOneShotAndExact() {
        var pool = FingerprintPool<String>()
        pool.replaceAll([
            (fingerprint: "light", value: "light-session"),
            (fingerprint: "heavy", value: "heavy-session")
        ])
        XCTAssertTrue(pool.has(matching: "light"))
        XCTAssertTrue(pool.has(matching: "heavy"))
        XCTAssertEqual(pool.take(matching: "light"), "light-session")
        XCTAssertFalse(pool.has(matching: "light"))
        XCTAssertTrue(pool.has(matching: "heavy"), "adopting light must not drop heavy")
        XCTAssertNil(pool.take(matching: "light"))
        XCTAssertNil(pool.take(matching: "drift"))
        XCTAssertEqual(pool.take(matching: "heavy"), "heavy-session")
    }

    func test_exemplar_isOffByDefault_andDoesNotChangeFingerprint() {
        PromptExperiments.reset()
        let budget = ContextBudget(window: .unavailable)
        let without = AskTranscriptPlan.build(
            instructions: "core", history: [], budget: budget, includeExemplar: true
        )
        XCTAssertEqual(without.entries.count, 1)
        XCTAssertFalse(without.entries.contains { entry in
            if case .userPrompt(let text) = entry { return text.contains(AskTranscriptPlan.exemplarMarker) }
            return false
        })
    }

    func test_exemplar_appendsOnlyOnEmptyNotebookHistory() {
        PromptExperiments.exemplarTurnEnabled = true
        defer { PromptExperiments.reset() }
        let budget = ContextBudget(window: .unavailable)
        let empty = AskTranscriptPlan.build(
            instructions: "core", history: [], budget: budget, includeExemplar: true
        )
        XCTAssertEqual(empty.entries.count, 3)
        XCTAssertTrue(AskTranscriptPlan.exemplarUser.contains(AskTranscriptPlan.exemplarMarker))
        if case .userPrompt(let text) = empty.entries[1] {
            XCTAssertTrue(text.contains(AskTranscriptPlan.exemplarMarker))
        } else {
            XCTFail("expected exemplar user turn")
        }

        let withHistory = AskTranscriptPlan.build(
            instructions: "core",
            history: [ChatTurn(role: .user, text: "hello")],
            budget: budget,
            includeExemplar: true
        )
        XCTAssertFalse(withHistory.entries.contains { entry in
            if case .userPrompt(let text) = entry { return text.contains(AskTranscriptPlan.exemplarMarker) }
            return false
        })
    }

    func test_exemplar_neverPersistedToAssistantJSON() {
        PromptExperiments.exemplarTurnEnabled = true
        defer { PromptExperiments.reset() }
        let json = ChatService.assistantContentJSON(
            body: "You were on the hike.",
            heading1: nil,
            heading2: nil,
            sources: []
        )
        XCTAssertFalse(json.contains(AskTranscriptPlan.exemplarMarker))
        XCTAssertFalse(json.contains(AskTranscriptPlan.exemplarAssistant))
    }

    func test_fingerprintPool_replaceAllDropsStaleHistory() {
        var pool = FingerprintPool<Int>()
        pool.store(1, fingerprint: "old-light")
        pool.replaceAll([(fingerprint: "new-light", value: 2), (fingerprint: "new-heavy", value: 3)])
        XCTAssertFalse(pool.has(matching: "old-light"))
        XCTAssertEqual(pool.count, 2)
        XCTAssertEqual(Set(pool.fingerprints), ["new-light", "new-heavy"])
    }
}
