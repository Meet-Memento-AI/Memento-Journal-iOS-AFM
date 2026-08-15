//
//  ChatContinuityTests.swift
//  MeetMementoTests
//
//  Covers the AI-chat performance/continuity fixes: derived-key caching,
//  history rehydration from the local store, and the typewriter "seen" flag
//  that stops a reply from replaying (the "repeat" bug). Pure — no model needed.
//

import XCTest
@testable import MeetMemento

final class ChatContinuityTests: XCTestCase {

    // MARK: Performance — the PBKDF2 key is derived once, then cached

    func testDerivedKeyIsCachedPerPin() {
        let service = EncryptionService(keychain: InMemoryKeychainStore())

        let k1 = service.deriveKey(from: "1234")
        let k2 = service.deriveKey(from: "1234")
        XCTAssertNotNil(k1)
        XCTAssertEqual(service.pbkdf2DerivationCount, 1, "same PIN must not re-run PBKDF2")
        XCTAssertEqual(k1, k2, "cached key must equal the first-derived key")

        _ = service.deriveKey(from: "9999")
        XCTAssertEqual(service.pbkdf2DerivationCount, 2, "a different PIN derives once more")

        service.clearDerivedKeyCache()
        _ = service.deriveKey(from: "1234")
        XCTAssertEqual(service.pbkdf2DerivationCount, 3, "after clearing, it re-derives")
    }

    // MARK: Continuity — history rehydrates from the on-device store

    func testHistoryRehydratesFromLocalStore() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ChatContTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalChatStore(directory: dir)
        let sid = UUID()

        store.appendMessage(role: "user", content: "how have I been?", to: sid)
        let assistantJSON = ChatService.assistantContentJSON(body: "You've been reflective this week.", heading1: nil, heading2: nil, sources: [])
        store.appendMessage(role: "assistant", content: assistantJSON, to: sid)

        let turns = ChatService.historyTurns(from: store.messages(for: sid))
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].role, .user)
        XCTAssertEqual(turns[0].text, "how have I been?")
        XCTAssertEqual(turns[1].role, .assistant)
        // Assistant turn must be the unwrapped body, NOT the raw JSON.
        XCTAssertEqual(turns[1].text, "You've been reflective this week.")
        XCTAssertFalse(turns[1].text.contains("{"), "assistant history must not carry raw JSON")
    }

    // MARK: Repeat bug — a message stops animating once seen

    @MainActor
    func testMarkMessageSeenStopsReplay() {
        let vm = ChatViewModel()
        let ai = ChatMessage(content: "hello there", isFromUser: false, isNew: true)
        vm.messages = [ai]
        XCTAssertTrue(vm.messages[0].isNew, "starts as new (animates once)")

        vm.markMessageSeen(ai.id)
        XCTAssertFalse(vm.messages[0].isNew, "after typing finishes it's seen → won't replay on recycle")
    }

    /// REQ-PRM-004: a stored reply carries the prompt and model that produced
    /// it. The reader must ignore the new keys (it looks up `body` explicitly),
    /// so old clients reading new JSON and new clients reading old JSON both
    /// keep working.
    func testStoredAssistantJSONCarriesProvenanceAndStillParses() throws {
        let json = ChatService.assistantContentJSON(
            body: "You wrote about the move twice this week.",
            heading1: nil,
            heading2: nil,
            sources: [],
            promptVersion: "ask@6+p2",
            modelIdentifier: "apple.system.on-device",
            zone: "z0.device",
            wasDegraded: false
        )

        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["prompt_version"] as? String, "ask@6+p2")
        XCTAssertEqual(object["model_identifier"] as? String, "apple.system.on-device")
        XCTAssertEqual(object["zone"] as? String, "z0.device")
        XCTAssertEqual(object["was_degraded"] as? Bool, false)

        // The turn still unwraps to plain prose for model context — provenance
        // keys must not leak into what the model reads back.
        let turns = ChatService.historyTurns(from: [
            ChatMessageDTO(id: UUID(), role: "assistant", content: json, createdAt: "2026-08-01T00:00:00Z")
        ])
        XCTAssertEqual(turns.first?.text, "You wrote about the move twice this week.")
    }

    /// Replies stored before provenance existed must still parse unchanged.
    func testLegacyStoredAssistantJSONWithoutProvenanceStillParses() throws {
        let legacy = ChatService.assistantContentJSON(
            body: "An older reply.", heading1: nil, heading2: nil, sources: []
        )
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(legacy.utf8)) as? [String: Any]
        )
        XCTAssertNil(object["prompt_version"])

        let turns = ChatService.historyTurns(from: [
            ChatMessageDTO(id: UUID(), role: "assistant", content: legacy, createdAt: "2026-08-01T00:00:00Z")
        ])
        XCTAssertEqual(turns.first?.text, "An older reply.")
    }
}
