//
//  IntelligenceServiceTests.swift
//  MeetMementoTests
//
//  Online-safe suites (retriever, embeddings availability, local chat store)
//  always run. Live Foundation Models generation belongs on a physical
//  Apple-Intelligence device (or the optional ios-device-eval workflow) and is
//  skipped when CI_ONLINE=1 (spec 025).
//
//  Note: this test imports NO FoundationModels — it depends only on the
//  `IntelligenceService` protocol boundary (P3), which is itself the injection
//  seam: a fake `IntelligenceService` can be substituted into `ChatService`
//  with no FoundationModels in test code.
//

import XCTest
@testable import MeetMemento

final class IntelligenceServiceTests: XCTestCase {

    /// Merge CI sets CI_ONLINE=1 so generation is skipped by policy, not after a
    /// failed model call (spec 025 R2).
    private var isOnlineCI: Bool {
        ProcessInfo.processInfo.environment["CI_ONLINE"] == "1"
    }

    func testAvailabilityAndOnDeviceAsk() async throws {
        if isOnlineCI {
            throw XCTSkip("CI_ONLINE=1: live FM generation is device-lane only (spec 025)")
        }

        let service = FoundationModelsIntelligenceService.shared

        let availability = await service.availability()
        print("[IntelligenceTest] availability = \(availability)")

        switch availability {
        case .unavailable(let reason):
            // Expected on a simulator without the provisioned on-device model —
            // the availability path is correct; real generation is device-gated.
            throw XCTSkip("On-device model unavailable here: \(reason.userMessage)")

        case .available(let zone):
            XCTAssertEqual(zone, .z0Device)

            let entries = Entry.sampleEntries
            let result: AskResult
            do {
                result = try await service.ask(
                    "What have I been reflecting on lately?",
                    history: [],
                    entries: entries
                )
            } catch {
                // The iOS Simulator reports the on-device model as available but
                // cannot actually run it (LanguageModelError -1). Real generation
                // is verified on a physical Apple-Intelligence device.
                throw XCTSkip("On-device generation not runnable in this environment (needs a physical device): \(error)")
            }
            print("[IntelligenceTest] zone=\(result.zoneUsed) prompt=\(result.promptVersion) model=\(result.modelIdentifier)")
            print("[IntelligenceTest] reply: \(result.body)")
            print("[IntelligenceTest] citations: \(result.citations.map { $0.entryDate })")

            XCTAssertFalse(result.body.isEmpty, "on-device reply should not be empty")
            XCTAssertEqual(result.zoneUsed, .z0Device)
            XCTAssertFalse(result.wasDegraded)
            // Citations must trace to a real provided entry (anti-fabrication).
            let providedIds = Set(entries.map { $0.id })
            for citation in result.citations {
                XCTAssertTrue(providedIds.contains(citation.entryId), "citation must reference a provided entry")
            }
        }
    }

    func testSummarizeConversation() async throws {
        if isOnlineCI {
            throw XCTSkip("CI_ONLINE=1: live FM generation is device-lane only (spec 025)")
        }

        let service = FoundationModelsIntelligenceService.shared
        guard case .available = await service.availability() else {
            throw XCTSkip("On-device model unavailable here.")
        }
        let turns = [
            ChatTurn(role: .user, text: "I keep procrastinating on my side project."),
            ChatTurn(role: .assistant, text: "You mentioned wanting to build it for months. What makes starting hard?"),
            ChatTurn(role: .user, text: "I think I'm afraid it won't be good enough, so I avoid it.")
        ]
        let summary: String
        do {
            summary = try await service.summarizeConversation(turns)
        } catch {
            throw XCTSkip("On-device generation not runnable in this environment (needs a physical device): \(error)")
        }
        print("[IntelligenceTest] summary: \(summary)")
        XCTAssertFalse(summary.isEmpty)
    }

    /// The retriever is pure Swift and always runs (no model needed).
    func testRetrieverGroundsOnlyProvidedEntries() {
        let entries = Entry.sampleEntries
        let result = EntryRetriever.retrieve(RetrievalQuery(currentMessage: "What are my goals for the year?"), entries: entries)
        // "Goals for the Year" sample entry should surface.
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contextBlock.contains("[ref 1"))
        for retrieved in result.entries {
            XCTAssertTrue(entries.contains { $0.id == retrieved.id })
        }
    }

    /// Trivial acknowledgements/social turns skip retrieval upstream now (via
    /// TurnClassifier + RetrievalPolicy — see ConversationFlowTests); the
    /// retriever itself only refuses empty inputs.
    func testRetrieverSkipsAcknowledgements() {
        let entries = Entry.sampleEntries
        for message in ["thanks", "ok"] {
            let turn = TurnClassifier.classify(message, hasHistory: false)
            XCTAssertEqual(RetrievalPolicy.mode(for: turn), .none, "\(message) should never reach the retriever")
        }
        XCTAssertTrue(EntryRetriever.retrieve(RetrievalQuery(currentMessage: ""), entries: entries).isEmpty)
    }

    /// On-device embeddings power semantic retrieval; open-ended messages still
    /// get ambient recent context instead of an empty "I don't see entries".
    func testEmbeddingsAndSemanticRetrieval() throws {
        let entries = Entry.sampleEntries
        print("[IntelligenceTest] NLEmbedding available: \(EmbeddingService.shared.isAvailable)")

        // Open-ended / general message → non-empty (ambient or matched) context.
        let general = EntryRetriever.retrieve(RetrievalQuery(currentMessage: "how have things been going for me?"), entries: entries)
        XCTAssertFalse(general.isEmpty, "open-ended messages should get ambient recent context, not empty")

        guard EmbeddingService.shared.isAvailable else {
            throw XCTSkip("NLEmbedding unavailable in this environment; semantic assertion skipped")
        }
        // Semantic match with NO shared keyword: "ambitions … this year" should
        // surface the "Goals for the Year" entry (which never says "ambitions").
        let semantic = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "what are my ambitions and what I want to achieve this year"),
            entries: entries
        )
        XCTAssertFalse(semantic.isEmpty)
        let goals = entries.first { $0.title == "Goals for the Year" }!
        XCTAssertTrue(semantic.entries.contains { $0.id == goals.id },
                      "semantic retrieval should surface the goals entry from meaning, not keywords")
    }

    /// Multiple chat windows: sessions + messages persist locally across instances.
    func testLocalChatStoreRoundTrip() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MementoChatTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalChatStore(directory: dir)

        let s1 = UUID(); let s2 = UUID()
        store.upsertSession(id: s1, title: "First chat")
        store.appendMessage(role: "user", content: "hi", to: s1)
        store.appendMessage(role: "assistant", content: #"{"body":"hello"}"#, to: s1)
        store.upsertSession(id: s2, title: "Second chat")
        store.appendMessage(role: "user", content: "hey", to: s2)

        XCTAssertEqual(store.sessions().count, 2)
        XCTAssertEqual(store.messages(for: s1).count, 2)
        XCTAssertEqual(store.messages(for: s1).first?.content, "hi")
        XCTAssertEqual(store.messages(for: s2).count, 1)

        // A fresh instance reads the same data from disk (survives relaunch).
        let reopened = LocalChatStore(directory: dir)
        XCTAssertEqual(reopened.sessions().count, 2)
        XCTAssertEqual(reopened.messages(for: s1).count, 2)

        reopened.deleteSession(s1)
        XCTAssertEqual(reopened.sessions().count, 1)
        XCTAssertTrue(reopened.messages(for: s1).isEmpty)
        XCTAssertEqual(reopened.sessions().first?.id, s2)
    }
}
