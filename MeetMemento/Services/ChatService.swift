import Foundation

// MARK: - Response Types

/// Decoded `chat` Edge Function JSON. `sources` may be empty when retrieval was skipped, no matches were found,
/// or the model did not cite journal entries — the citations UI should treat an empty list as "no citations."
struct ChatResponse: Codable {
    let reply: String
    let heading1: String?
    let heading2: String?
    /// Entry UUIDs the model cited; mirrors server `cited_entry_ids` (optional for backward compatibility).
    let citedEntryIds: [String]?
    let sources: [ChatSource]
    let sessionId: String
    /// Spec 026: how the assistant bubble should present a safety route.
    /// Defaults to `.none` for normal model replies (and for older persisted JSON).
    let safetyPresentation: ChatSafetyPresentation

    enum CodingKeys: String, CodingKey {
        case reply, heading1, heading2, sources, sessionId
        case citedEntryIds = "cited_entry_ids"
        case safetyPresentation = "safety_presentation"
    }

    init(
        reply: String,
        heading1: String? = nil,
        heading2: String? = nil,
        citedEntryIds: [String]? = nil,
        sources: [ChatSource],
        sessionId: String,
        safetyPresentation: ChatSafetyPresentation = .none
    ) {
        self.reply = reply
        self.heading1 = heading1
        self.heading2 = heading2
        self.citedEntryIds = citedEntryIds
        self.sources = sources
        self.sessionId = sessionId
        self.safetyPresentation = safetyPresentation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decode(String.self, forKey: .reply)
        heading1 = try container.decodeIfPresent(String.self, forKey: .heading1)
        heading2 = try container.decodeIfPresent(String.self, forKey: .heading2)
        citedEntryIds = try container.decodeIfPresent([String].self, forKey: .citedEntryIds)
        sources = try container.decodeIfPresent([ChatSource].self, forKey: .sources) ?? []
        sessionId = try container.decode(String.self, forKey: .sessionId)
        safetyPresentation = try container.decodeIfPresent(ChatSafetyPresentation.self, forKey: .safetyPresentation) ?? .none
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reply, forKey: .reply)
        try container.encodeIfPresent(heading1, forKey: .heading1)
        try container.encodeIfPresent(heading2, forKey: .heading2)
        try container.encodeIfPresent(citedEntryIds, forKey: .citedEntryIds)
        try container.encode(sources, forKey: .sources)
        try container.encode(sessionId, forKey: .sessionId)
        if safetyPresentation != .none {
            try container.encode(safetyPresentation, forKey: .safetyPresentation)
        }
    }
}

struct ChatSource: Codable, Equatable {
    let id: String
    let createdAt: String
    let preview: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case preview
    }
}


// MARK: - Summary Types

struct ChatSummaryResponse: Codable {
    let title: String?
    let content: String
}

/// Incremental chat output. `delta` is the reply body so far (cumulative);
/// `final` carries the complete `ChatResponse` (sources, session id) once
/// generation finishes and the turn is persisted.
enum ChatStreamEvent: Sendable {
    /// `sources` are the journals reviewed for a grounded turn, forwarded from the
    /// first delta so the "Reviewed your journals" link can show right away. Empty
    /// for non-grounded turns; the `.final` sources supersede them.
    case delta(body: String, heading1: String?, heading2: String?, sources: [ChatSource])
    case final(ChatResponse)
}

// MARK: - Service protocol (enables unit tests with mocks)

protocol ChatServiceProtocol: AnyObject {
    func sendMessage(_ text: String, sessionId: UUID?) async throws -> ChatResponse
    func fetchSessions() async throws -> [ChatSession]
    func loadSessionMessages(sessionId: UUID) async throws -> [ChatMessageDTO]
    func deleteSession(sessionId: UUID) async throws
    func summarizeChat(messages: [ChatMessage], sessionId: UUID?) async throws -> ChatSummaryResponse
    /// Warm the on-device model ahead of the first send (chat view appears).
    func prewarm()
    /// Streaming send: emits the reply as it generates, then a final response.
    func sendMessageStream(_ text: String, sessionId: UUID?) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

extension ChatServiceProtocol {
    func prewarm() {}

    /// Default streaming: run the one-shot `sendMessage` and emit a single
    /// delta + final. Mocks that only implement `sendMessage` still work.
    func sendMessageStream(_ text: String, sessionId: UUID?) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await sendMessage(text, sessionId: sessionId)
                    continuation.yield(.delta(body: response.reply, heading1: response.heading1,
                                              heading2: response.heading2, sources: response.sources))
                    continuation.yield(.final(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Service

class ChatService {
    static let shared = ChatService()

    // MARK: - Native intelligence (Apple Foundation Models)

    /// The on-device intelligence boundary. ChatService itself never imports
    /// FoundationModels — it depends only on the protocol (P3 / REQ-INT-001).
    private let intelligence: IntelligenceService = FoundationModelsIntelligenceService.shared

    /// Warm the model AND precompute entry embeddings ahead of the first send,
    /// off the main thread, so message #1 doesn't pay cold model load + cold
    /// "embed every entry" costs.
    func prewarm() {
        intelligence.prewarm()
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            EntryRetriever.warmEmbeddings(self.loadLocalEntries())
        }
    }

    /// Reused across citation mapping (avoids a per-source allocation).
    private static let iso8601 = ISO8601DateFormatter()

    /// Loads and decrypts the on-device journal entries the retriever ranks over
    /// (the sole source of truth — no server).
    ///
    /// This used to bail out entirely when `SecurityService.getPIN()` returned
    /// nil, which meant a Keychain miss silently stripped chat of all journal
    /// grounding — the model would answer confidently from nothing. Entries are
    /// now read under the Keychain-resident data key; the PIN is passed only so
    /// content still encrypted under the legacy PBKDF2(PIN) scheme can be read
    /// and rewritten.
    private func loadLocalEntries() -> [Entry] {
        JournalService.shared.loadAllEntriesLocally(legacyPIN: SecurityService.shared.getPIN())
    }

    func sendMessage(_ text: String, sessionId: UUID? = nil) async throws -> ChatResponse {
        let conversationId = sessionId ?? UUID()
                AppLogger.log("💬 [ChatService] Generating on-device reply (conversation: \(conversationId.uuidString.prefix(8)))...")

        // History comes from the on-device store (the single source of truth),
        // so reopening a saved conversation or relaunching keeps full context —
        // the fix for the model losing the thread / re-greeting each turn.
        let history = Self.historyTurns(from: LocalChatStore.shared.messages(for: conversationId))
        let entries = loadLocalEntries()

        do {
            let result = try await intelligence.ask(text, history: history, entries: entries)

            let sources = result.citations.map { citation in
                ChatSource(
                    id: citation.entryId.uuidString,
                    createdAt: Self.iso8601.string(from: citation.entryDate),
                    preview: citation.excerpt
                )
            }

                    AppLogger.log("✅ [ChatService] Reply (\(result.body.count) chars), \(sources.count) citations, zone: \(String(describing: result.zoneUsed)), prompt: \(result.promptVersion)")

            // Persist locally so the conversation survives relaunch and shows in the
            // history list (multiple chat windows). The assistant turn is stored in
            // the {heading1,heading2,body,sources} JSON shape the chat UI parses on load.
            LocalChatStore.shared.upsertSession(id: conversationId, title: String(text.prefix(100)))
            LocalChatStore.shared.appendMessage(role: "user", content: text, to: conversationId)
            LocalChatStore.shared.appendMessage(
                role: "assistant",
                content: Self.assistantContentJSON(
                    body: result.body, heading1: result.heading1, heading2: result.heading2,
                    sources: sources, promptVersion: result.promptVersion,
                    modelIdentifier: result.modelIdentifier, zone: result.zoneUsed.identifier,
                    wasDegraded: result.wasDegraded
                ),
                to: conversationId
            )

            return ChatResponse(
                reply: result.body,
                heading1: result.heading1,
                heading2: result.heading2,
                citedEntryIds: result.citations.map { $0.entryId.uuidString },
                sources: sources,
                sessionId: conversationId.uuidString
            )
        } catch let error as IntelligenceError {
            if let designed = Self.persistDesignedSafetyReply(
                error, userText: text, conversationId: conversationId
            ) {
                return designed
            }
            throw error
        }
    }

    /// Spec 026: for a designed Safety route (crisis card / hard refuse), persist
    /// the turn locally — same shape as a normal reply — and return the
    /// `ChatResponse` the caller should hand back instead of throwing. Returns
    /// `nil` for errors that aren't a Safety route (`.unavailable`,
    /// `.guardrailRefusal`, `.generationFailed`), so those still `throw` and hit
    /// ChatViewModel's existing handling.
    private static func persistDesignedSafetyReply(
        _ error: IntelligenceError, userText: String, conversationId: UUID
    ) -> ChatResponse? {
        let presentation: ChatSafetyPresentation
        switch error {
        case .crisisResource:
            presentation = .crisisResource
        case .safetyRefusal:
            presentation = .hardRefuse
        default:
            return nil
        }

        let body = error.errorDescription ?? ""

        LocalChatStore.shared.upsertSession(id: conversationId, title: String(userText.prefix(100)))
        LocalChatStore.shared.appendMessage(role: "user", content: userText, to: conversationId)
        LocalChatStore.shared.appendMessage(
            role: "assistant",
            content: assistantContentJSON(body: body, heading1: nil, heading2: nil, sources: [],
                                          safetyPresentation: presentation),
            to: conversationId
        )

        return ChatResponse(
            reply: body,
            sources: [],
            sessionId: conversationId.uuidString,
            safetyPresentation: presentation
        )
    }

    /// Maps intelligence-layer citations to the `ChatSource` shape used by both
    /// the streamed `.delta`/`.final` events and local persistence.
    private static func sources(from citations: [AskCitation]) -> [ChatSource] {
        citations.map { citation in
            ChatSource(
                id: citation.entryId.uuidString,
                createdAt: iso8601.string(from: citation.entryDate),
                preview: citation.excerpt
            )
        }
    }

    /// Streaming send: forwards the model's incremental output as `.delta`
    /// events (so the bubble fills as it generates), then persists the turn and
    /// emits `.final`. Persistence and citation mapping run *after* the stream
    /// so nothing blocks first-token.
    func sendMessageStream(_ text: String, sessionId: UUID? = nil) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let conversationId = sessionId ?? UUID()
                let history = Self.historyTurns(from: LocalChatStore.shared.messages(for: conversationId))
                let entries = self.loadLocalEntries()
                do {
                    var finalResult: AskResult?
                    for try await event in self.intelligence.askStream(text, history: history, entries: entries) {
                        switch event {
                        case .delta(let bodySoFar, let h1, let h2, let reviewed):
                            continuation.yield(.delta(body: bodySoFar, heading1: h1, heading2: h2,
                                                      sources: Self.sources(from: reviewed)))
                        case .final(let result):
                            finalResult = result
                        }
                    }
                    guard let result = finalResult else {
                        // Stream ended without a final (e.g. cancelled) — no persist.
                        continuation.finish()
                        return
                    }
                    let sources = Self.sources(from: result.citations)
                    LocalChatStore.shared.upsertSession(id: conversationId, title: String(text.prefix(100)))
                    LocalChatStore.shared.appendMessage(role: "user", content: text, to: conversationId)
                    LocalChatStore.shared.appendMessage(
                        role: "assistant",
                        content: Self.assistantContentJSON(
                body: result.body, heading1: result.heading1, heading2: result.heading2,
                sources: sources, promptVersion: result.promptVersion,
                modelIdentifier: result.modelIdentifier, zone: result.zoneUsed.identifier,
                wasDegraded: result.wasDegraded
            ),
                        to: conversationId
                    )
                    continuation.yield(.final(ChatResponse(
                        reply: result.body,
                        heading1: result.heading1,
                        heading2: result.heading2,
                        citedEntryIds: result.citations.map { $0.entryId.uuidString },
                        sources: sources,
                        sessionId: conversationId.uuidString
                    )))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as IntelligenceError {
                    // Spec 026: a Safety route is a designed reply, not a failure.
                    // This is the path the UI actually uses, so without persisting
                    // here the user's crisis message and the resource card were
                    // dropped entirely — never written to LocalChatStore, and gone
                    // from the session list on relaunch.
                    if let designed = Self.persistDesignedSafetyReply(
                        error, userText: text, conversationId: conversationId
                    ) {
                        continuation.yield(.final(designed))
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - History Management

    func clearHistory() async throws {
        LocalChatStore.shared.clear()
                AppLogger.log("🗑️ [ChatService] Local chat history cleared")
    }

    // MARK: - Session Management (local, on-device)

    /// All chat sessions, most recently updated first.
    func fetchSessions() async throws -> [ChatSession] {
        let sessions = LocalChatStore.shared.sessions()
                AppLogger.log("📋 [ChatService] Fetched \(sessions.count) local sessions")
        return sessions
    }

    /// All messages for a session, oldest first.
    func loadSessionMessages(sessionId: UUID) async throws -> [ChatMessageDTO] {
        let messages = LocalChatStore.shared.messages(for: sessionId)
                AppLogger.log("📖 [ChatService] Loaded \(messages.count) local messages for \(sessionId.uuidString.prefix(8))")
        return messages
    }

    /// Deletes a chat session and its messages.
    func deleteSession(sessionId: UUID) async throws {
        LocalChatStore.shared.deleteSession(sessionId)
                AppLogger.log("🗑️ [ChatService] Deleted local session \(sessionId.uuidString.prefix(8))")
    }

    /// Rebuilds the prior conversation as `[ChatTurn]` from the stored messages,
    /// unwrapping each assistant message's `{…, body}` JSON back to plain text.
    static func historyTurns(from dtos: [ChatMessageDTO]) -> [ChatTurn] {
        dtos.map { dto in
            dto.role == "user"
                ? ChatTurn(role: .user, text: dto.content)
                : ChatTurn(role: .assistant, text: unwrapAssistantBody(dto.content))
        }
    }

    static func unwrapAssistantBody(_ content: String) -> String {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = object["body"] as? String else {
            return content   // legacy plain text
        }
        return body
    }

    /// Builds the assistant message content in the JSON shape the chat UI parses
    /// on load (`ChatViewModel.extractBodyContent`): body + optional headings +
    /// sources so citations re-render for reloaded conversations.
    /// `promptVersion`/`modelIdentifier` are persisted per artifact (REQ-PRM-004)
    /// — without them a stored reply cannot be attributed to what produced it,
    /// and spec 022's quality study cannot explain a regression. Both are
    /// optional so replies stored before this shipped still parse; the reader
    /// ignores unknown keys, so this is backward-compatible in both directions.
    static func assistantContentJSON(body: String, heading1: String?, heading2: String?,
                                     sources: [ChatSource],
                                     promptVersion: String? = nil,
                                     modelIdentifier: String? = nil,
                                     zone: String? = nil,
                                     wasDegraded: Bool? = nil,
                                     safetyPresentation: ChatSafetyPresentation = .none) -> String {
        var object: [String: Any] = ["body": body]
        if let heading1 { object["heading1"] = heading1 }
        if let heading2 { object["heading2"] = heading2 }
        if let promptVersion { object["prompt_version"] = promptVersion }
        if let modelIdentifier { object["model_identifier"] = modelIdentifier }
        if let zone { object["zone"] = zone }
        if let wasDegraded { object["was_degraded"] = wasDegraded }
        // Spec 026: without this, reopening a saved conversation renders a past
        // crisis turn as ordinary prose — the resource card silently disappears.
        // Omitted when .none so existing stored messages stay byte-identical.
        if safetyPresentation != .none { object["safety_presentation"] = safetyPresentation.rawValue }
        object["sources"] = sources.map { ["id": $0.id, "created_at": $0.createdAt, "preview": $0.preview] }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else {
            return body
        }
        return json
    }

    // MARK: - Chat Summary

    /// Summarizes a chat conversation into a journal entry, on-device.
    func summarizeChat(messages: [ChatMessage], sessionId: UUID?) async throws -> ChatSummaryResponse {
                AppLogger.log("📝 [ChatService] Summarizing chat on-device (\(messages.count) messages)...")

        let turns = messages.map { ChatTurn(role: $0.isFromUser ? .user : .assistant, text: $0.content) }
        let outcome = try await intelligence.summarizeConversation(turns)

                AppLogger.log("✅ [ChatService] Summary generated (\(outcome.value.count) chars), "
                              + "zone: \(outcome.zoneUsed.identifier), degraded: \(outcome.wasDegraded)")

        return ChatSummaryResponse(title: nil, content: outcome.value)
    }

    // MARK: - Chat Feedback (local-only stub)

    // Thumbs up/down had a server backend (a feedback endpoint + table).
    // The backend was removed from the product, so feedback is now
    // UI-only: `ChatViewModel` already tracks the up/down state in memory for
    // the session. These stubs keep that surface working without persistence —
    // reimplement on-device if feedback needs to survive relaunches.

    /// No-op: records nothing server-side, echoes the submitted type back so the
    /// in-memory UI state is treated as applied.
    func submitFeedback(messageId: UUID, type: FeedbackType) async throws -> FeedbackType? {
        AppLogger.log("👍 [ChatService] Feedback \(type.rawValue) (local-only, not persisted) for \(messageId.uuidString.prefix(8))")
        return type
    }

    /// No persisted feedback to restore (no backend) — always empty.
    func fetchFeedback(messageIds: [UUID]) async throws -> [UUID: FeedbackType] {
        [:]
    }
}

extension ChatService: ChatServiceProtocol {}
