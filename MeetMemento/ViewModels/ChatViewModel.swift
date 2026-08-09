import Foundation
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var showingError: Bool = false

    // Session management
    @Published var currentSessionId: UUID?
    @Published var sessions: [ChatSession] = []
    @Published var isLoadingSessions: Bool = false

    // Summary generation
    @Published var isSummarizing: Bool = false

    // Feedback state per message (thumbs up/down) - using Sets for boolean-like behavior
    @Published var thumbsUpMessages: Set<UUID> = []
    @Published var thumbsDownMessages: Set<UUID> = []

    /// Whether there is an active chat conversation (1+ messages)
    var hasActiveChat: Bool {
        !messages.isEmpty || currentSessionId != nil
    }

    // User info
    @Published var userName: String?

    private let chatService: ChatServiceProtocol
    private let maxMessagesInMemory = 100

    /// Per-session message cache to avoid re-fetching on tab switches
    private var messageCache: [UUID: [ChatMessage]] = [:]

    /// Fire-and-forget `Task`s (send, feedback) spawned by this view model.
    /// Tracked so `cancelActiveTasks()` (called from the view's
    /// `onDisappear`) can stop in-flight work instead of leaking it — e.g.
    /// leaving the chat tab mid-send shouldn't keep the network call and
    /// its continuation alive in the background.
    private var activeTasks: [Task<Void, Never>] = []

    /// Bumped by `cancelActiveTasks()`. A send task captures the generation
    /// at launch and compares before writing shared state (`messages`,
    /// `isLoading`, error alert) so a cancelled task resuming late can't
    /// stomp the conversation that's now on screen.
    private var sendGeneration = 0

    private func track(_ task: Task<Void, Never>) {
        activeTasks.append(task)
    }

    /// Cancels every tracked in-flight task. Safe to call from `onDisappear`
    /// even with nothing in flight.
    func cancelActiveTasks() {
        sendGeneration += 1
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        // Cancelled work can no longer finish, so don't leave the input
        // dimmed and the loading indicator up.
        isLoading = false
    }

    // MARK: - Initialization

    init(chatService: ChatServiceProtocol = ChatService.shared) {
        self.chatService = chatService
    }

    /// Warm the on-device model so the first send doesn't pay cold model load.
    /// Call when the chat view appears / the input gains focus.
    func prewarm() {
        chatService.prewarm()
    }

    /// Reads the user's first name for personalized welcome messages. No
    /// accounts / no backend (the name is captured during onboarding and
    /// stored locally); this is a local UserDefaults read, kept `async` to
    /// preserve the call sites.
    func fetchUserName() async {
        let stored = UserDefaults.standard.string(forKey: "memento_first_name")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty {
            userName = stored
        }
    }

    // MARK: - JSON Content Extraction

    /// Extracts clean body text from potentially JSON-formatted content
    /// Handles: raw JSON strings, legacy plain text, nested JSON
    /// Also extracts sources/citations for display
    private func extractBodyContent(from content: String, role: String) -> (body: String, aiContent: AIOutputContent?, citations: [JournalCitation]?) {
        guard role == "assistant" else {
            return (content, nil, nil)
        }

        // Try parsing as generic JSON with body field and sources
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let body = json["body"] as? String {
            let heading1 = json["heading1"] as? String
            let heading2 = json["heading2"] as? String

            // Extract sources/citations from stored message
            var citations: [JournalCitation]? = nil
            var sources: [ChatSource] = []
            if let sourcesArray = json["sources"] as? [[String: Any]], !sourcesArray.isEmpty {
                citations = sourcesArray.compactMap { source -> JournalCitation? in
                    guard let idString = source["id"] as? String,
                          let entryId = UUID(uuidString: idString),
                          let preview = source["preview"] as? String else {
                        return nil
                    }

                    let createdAt = source["created_at"] as? String ?? ""
                    sources.append(ChatSource(id: idString, createdAt: createdAt, preview: preview))

                    let date: Date
                    if let parsed = ISO8601DateFormatter().date(from: createdAt) {
                        date = parsed
                    } else {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        date = formatter.date(from: createdAt) ?? Date()
                    }

                    return JournalCitation(
                        entryId: entryId,
                        entryTitle: "",
                        entryDate: date,
                        excerpt: preview
                    )
                }
            }

            let aiContent = AIOutputContent(heading1: heading1, heading2: heading2, body: body, citations: citations)
            return (body, aiContent, citations)
        }

        // Try parsing as AIOutputContent JSON (legacy format without sources)
        if let data = content.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(AIOutputContent.self, from: data) {
            return (parsed.body, parsed, parsed.citations)
        }

        // Check if content looks like JSON but parsing failed - try to extract body
        if content.hasPrefix("{") && content.contains("\"body\"") {
            // Regex fallback to extract body value
            if let range = content.range(of: #""body"\s*:\s*"([^"\\]*(\\.[^"\\]*)*)""#, options: .regularExpression),
               let bodyRange = content.range(of: #":\s*"([^"\\]*(\\.[^"\\]*)*)""#, options: .regularExpression, range: range) {
                let extracted = String(content[bodyRange])
                    .replacingOccurrences(of: #"^\s*:\s*""#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #""$"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\n", with: "\n")
                if !extracted.isEmpty {
                    let aiContent = AIOutputContent(heading1: nil, heading2: nil, body: extracted)
                    return (extracted, aiContent, nil)
                }
            }

            // Raw JSON leaked through - regex extraction failed, show user-friendly message
            AppLogger.log("[ChatViewModel] Raw JSON detected but body extraction failed", type: .error)
            let fallbackBody = "I had trouble processing this response. Please try again."
            let aiContent = AIOutputContent(heading1: nil, heading2: nil, body: fallbackBody)
            return (fallbackBody, aiContent, nil)
        }

        // Final check: if content still looks like raw JSON (starts with '{'), sanitize
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            AppLogger.log("[ChatViewModel] Unexpected JSON-like content in message", type: .error)
            let fallbackBody = "I had trouble processing this response. Please try again."
            let aiContent = AIOutputContent(heading1: nil, heading2: nil, body: fallbackBody)
            return (fallbackBody, aiContent, nil)
        }

        // Not JSON - return as-is (legacy plain text)
        let aiContent = AIOutputContent(heading1: nil, heading2: nil, body: content)
        return (content, aiContent, nil)
    }

    // MARK: - Send Message

    func sendMessage(prompt: String? = nil) {
        let text: String
        if let prompt = prompt {
            text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty, !isLoading else { return }

        if prompt == nil {
            inputText = ""
        }

        let userMessage = ChatMessage(content: text, isFromUser: true, isNew: true)
        appendMessage(userMessage)

        performSend(text: text, userMessageId: userMessage.id)
    }

    /// Retries a user message that previously failed to send (spec-010),
    /// reusing its existing id/bubble instead of appending a duplicate.
    func retryMessage(_ message: ChatMessage) {
        guard message.isFromUser, message.sendFailed, !isLoading else { return }
        setSendFailed(false, forMessageId: message.id)
        performSend(text: message.content, userMessageId: message.id)
    }

    private func setSendFailed(_ failed: Bool, forMessageId id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].sendFailed = failed
    }

    /// Shared send path for both a fresh message and a retry of a failed
    /// one. On failure, the user's message stays in the transcript marked
    /// `sendFailed` — never rolled back — so retrying doesn't require
    /// retyping.
    private func performSend(text: String, userMessageId: UUID) {
        isLoading = true
        let generation = sendGeneration

        // Empty assistant bubble appended immediately; it fills as the model
        // streams so text appears the moment generation starts (no waiting for
        // the whole reply, no artificial typewriter).
        let assistantId = UUID()
        appendMessage(ChatMessage.aiMessage(id: assistantId, body: "", isNew: true))

        track(Task { [weak self] in
            guard let self else { return }
            // Whatever ends the stream — success, error, or cancel — settle the
            // assistant bubble so the typewriter can complete instead of blinking
            // its caret forever. On the success path `.final` already cleared this,
            // so the flip is a no-op; on error/cancel `.final` never arrives, so
            // this is the only thing that settles a partial reply.
            defer {
                if let idx = messages.firstIndex(where: { $0.id == assistantId }),
                   messages[idx].isStreaming {
                    messages[idx].isStreaming = false
                }
            }
            var sawContent = false
            do {
                for try await event in chatService.sendMessageStream(text, sessionId: currentSessionId) {
                    // Cancelled or superseded mid-flight (user left / switched
                    // conversations): stop writing into whatever is on screen now.
                    guard generation == sendGeneration, !Task.isCancelled else { return }

                    switch event {
                    case .delta(let body, let heading1, let heading2):
                        // First visible token: drop the "thinking" indicator.
                        if isLoading { isLoading = false }
                        sawContent = sawContent || !body.isEmpty
                        updateStreamingMessage(id: assistantId, body: body,
                                               heading1: heading1, heading2: heading2, citations: nil,
                                               isStreaming: true)

                    case .final(let response):
                        // Handle new-session creation (first message of a chat).
                        if let newSessionId = UUID(uuidString: response.sessionId), currentSessionId == nil {
                            currentSessionId = newSessionId
                            await fetchSessions()
                        }
                        let citations = mapSourcesToCitations(response.sources)
                        updateStreamingMessage(id: assistantId, body: response.reply,
                                               heading1: response.heading1, heading2: response.heading2,
                                               citations: citations.isEmpty ? nil : citations,
                                               isStreaming: false)
                        sawContent = sawContent || !response.reply.isEmpty
                        if let sessionId = currentSessionId { messageCache[sessionId] = messages }
                    }
                }
            } catch {
                AppLogger.log("[ChatViewModel] sendMessage error: \(error)", type: .error)
                // Drop the empty placeholder so a failed send doesn't leave a
                // blank bubble; keep the retry affordance on the user's message.
                if !sawContent { messages.removeAll { $0.id == assistantId } }
                setSendFailed(true, forMessageId: userMessageId)
                // A cancelled/superseded send shouldn't pop the error alert
                // over unrelated content.
                if generation == sendGeneration, !Task.isCancelled,
                   !(error is CancellationError) {
                    errorMessage = chatErrorMessage(for: error)
                    showingError = true
                }
            }
            guard generation == sendGeneration else { return }
            // Nothing streamed at all (e.g. immediate cancel): clean the placeholder.
            if !sawContent { messages.removeAll { $0.id == assistantId } }
            isLoading = false
        })
    }

    /// Replaces the streaming assistant bubble (matched by id) with the
    /// latest body/headings/citations. Called on every delta (`isStreaming:
    /// true`) and once on final (`isStreaming: false`) so the typewriter knows
    /// when the stream has genuinely ended.
    private func updateStreamingMessage(id: UUID, body: String, heading1: String?, heading2: String?, citations: [JournalCitation]?, isStreaming: Bool) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = ChatMessage.aiMessage(
            id: id,
            heading1: heading1,
            heading2: heading2,
            body: body,
            citations: citations,
            timestamp: messages[index].timestamp,
            isNew: true,
            isStreaming: isStreaming
        )
    }

    // MARK: - Clear Conversation

    func clearConversation() {
        messages = []
        currentSessionId = nil
    }

    // MARK: - Session Management

    /// Fetches all chat sessions from the backend
    func fetchSessions() async {
        isLoadingSessions = true
        do {
            sessions = try await chatService.fetchSessions()
        } catch {
            AppLogger.log("[ChatViewModel] fetchSessions error: \(error)", type: .error)
        }
        isLoadingSessions = false
    }

    /// Loads a specific session's messages
    func loadSession(_ session: ChatSession) async {
        // Stop any in-flight send from the previous conversation so its
        // reply can't land in this one.
        cancelActiveTasks()
        currentSessionId = session.id

        // Check cache first - if cached, show instantly without loading state
        if let cached = messageCache[session.id] {
            messages = cached
            // Still load feedback for cached messages
            await loadFeedbackForMessages()
            return
        }

        // Not cached - show loading state and fetch from database
        messages = []
        isLoading = true

        do {
            let messageDTOs = try await chatService.loadSessionMessages(sessionId: session.id)
            let loadedMessages = messageDTOs.map { dto -> ChatMessage in
                let (body, aiContent, citations) = extractBodyContent(from: dto.content, role: dto.role)

                if dto.role == "assistant", let aiContent = aiContent {
                    // Loaded messages: isNew = false (default) - no animation
                    // Citations are now persisted and extracted from stored message
                    return ChatMessage.aiMessage(
                        heading1: aiContent.heading1,
                        heading2: aiContent.heading2,
                        body: body,
                        citations: citations
                    )
                }

                // User messages: isNew = false (default)
                return ChatMessage(content: dto.content, isFromUser: dto.role == "user")
            }
            messages = loadedMessages
            // Cache the loaded messages
            messageCache[session.id] = loadedMessages
            // Load feedback state for the messages
            await loadFeedbackForMessages()
        } catch {
            AppLogger.log("[ChatViewModel] loadSession error: \(error)", type: .error)
            errorMessage = "Failed to load conversation history."
            showingError = true
        }
        isLoading = false
    }

    /// Starts a new chat by clearing state
    func startNewChat() {
        // Stop any in-flight send so a stale reply can't appear in the
        // fresh conversation.
        cancelActiveTasks()
        messages = []
        currentSessionId = nil
        inputText = ""
        thumbsUpMessages = []
        thumbsDownMessages = []
    }

    /// Deletes a session and refreshes the sessions list
    func deleteSession(_ session: ChatSession) async {
        do {
            try await chatService.deleteSession(sessionId: session.id)
            // Remove from cache
            messageCache.removeValue(forKey: session.id)
            // Remove from local list immediately for responsiveness
            sessions.removeAll { $0.id == session.id }
            // If the deleted session was the current one, clear the chat
            if currentSessionId == session.id {
                startNewChat()
            }
        } catch {
            AppLogger.log("[ChatViewModel] deleteSession error: \(error)", type: .error)
            errorMessage = "Failed to delete conversation."
            showingError = true
        }
    }

    // MARK: - Retry

    /// Retries sending the last failed user message. Routes through
    /// `retryMessage` so the existing bubble is reused — previously this
    /// appended a duplicate user bubble while the original stayed marked
    /// "Failed to send".
    func retrySend() {
        guard let lastFailed = messages.last(where: { $0.isFromUser && $0.sendFailed }) else { return }
        retryMessage(lastFailed)
    }

    // MARK: - Chat Summary

    /// Generates a summary of the current chat conversation for creating a journal entry
    func generateChatSummary() async throws -> (title: String, content: String) {
        guard hasActiveChat else {
            throw NSError(domain: "ChatViewModel", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No active chat to summarize"])
        }

        isSummarizing = true
        defer { isSummarizing = false }

        let summary = try await chatService.summarizeChat(
            messages: messages,
            sessionId: currentSessionId
        )
        return (summary.title ?? "Chat Reflection", summary.content)
    }

    // MARK: - Regenerate

    func regenerateResponse(for messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }), index > 0 else { return }
        let precedingUserMessage = messages[index - 1]
        guard precedingUserMessage.isFromUser else { return }
        let userContent = precedingUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userContent.isEmpty else { return }
        messages.removeSubrange((index - 1)...index)
        sendMessage(prompt: userContent)
    }

    // MARK: - Feedback

    /// Toggles thumbs up for a message (boolean: on or off)
    func toggleThumbsUp(for messageId: UUID) {
        // Toggle the boolean state
        if thumbsUpMessages.contains(messageId) {
            // Turn off
            thumbsUpMessages.remove(messageId)
        } else {
            // Turn on (and turn off thumbs down if it was on)
            thumbsUpMessages.insert(messageId)
            thumbsDownMessages.remove(messageId)
        }

        // Persist to backend (fire and forget, don't affect UI state)
        track(Task { [weak self] in
            guard let self else { return }
            do {
                if thumbsUpMessages.contains(messageId) {
                    _ = try await (chatService as? ChatService)?.submitFeedback(messageId: messageId, type: .positive)
                } else {
                    // Clear feedback by sending the same type again (toggle behavior on backend)
                    _ = try await (chatService as? ChatService)?.submitFeedback(messageId: messageId, type: .positive)
                }
            } catch {
                AppLogger.log("[ChatViewModel] toggleThumbsUp error: \(error)", type: .error)
            }
        })
    }

    /// Toggles thumbs down for a message (boolean: on or off)
    func toggleThumbsDown(for messageId: UUID) {
        // Toggle the boolean state
        if thumbsDownMessages.contains(messageId) {
            // Turn off
            thumbsDownMessages.remove(messageId)
        } else {
            // Turn on (and turn off thumbs up if it was on)
            thumbsDownMessages.insert(messageId)
            thumbsUpMessages.remove(messageId)
        }

        // Persist to backend (fire and forget, don't affect UI state)
        track(Task { [weak self] in
            guard let self else { return }
            do {
                if thumbsDownMessages.contains(messageId) {
                    _ = try await (chatService as? ChatService)?.submitFeedback(messageId: messageId, type: .negative)
                } else {
                    // Clear feedback
                    _ = try await (chatService as? ChatService)?.submitFeedback(messageId: messageId, type: .negative)
                }
            } catch {
                AppLogger.log("[ChatViewModel] toggleThumbsDown error: \(error)", type: .error)
            }
        })
    }

    /// Returns the current feedback type for a message (for UI binding)
    func feedbackType(for messageId: UUID) -> FeedbackType? {
        if thumbsUpMessages.contains(messageId) {
            return .positive
        } else if thumbsDownMessages.contains(messageId) {
            return .negative
        }
        return nil
    }

    /// Loads feedback state for the current messages
    private func loadFeedbackForMessages() async {
        let assistantMessageIds = messages.filter { !$0.isFromUser }.map { $0.id }
        guard !assistantMessageIds.isEmpty else { return }

        do {
            let feedback = try await (chatService as? ChatService)?.fetchFeedback(messageIds: assistantMessageIds) ?? [:]
            await MainActor.run {
                for (messageId, type) in feedback {
                    switch type {
                    case .positive:
                        thumbsUpMessages.insert(messageId)
                        thumbsDownMessages.remove(messageId)
                    case .negative:
                        thumbsDownMessages.insert(messageId)
                        thumbsUpMessages.remove(messageId)
                    }
                }
            }
        } catch {
            AppLogger.log("[ChatViewModel] loadFeedbackForMessages error: \(error)", type: .error)
        }
    }

    // MARK: - Private Helpers

    private func appendMessage(_ message: ChatMessage) {
        // Only the incoming message should play its entrance animation;
        // earlier ones have already been seen.
        for index in messages.indices where messages[index].isNew {
            messages[index].isNew = false
        }
        messages.append(message)
        if messages.count > maxMessagesInMemory {
            messages.removeFirst(messages.count - maxMessagesInMemory)
        }
    }

    /// Marks a single message as seen once its typewriter finishes, so a
    /// LazyVStack recycle (scroll / keyboard / re-render) shows the full reply
    /// instead of replaying the animation. This is the fix for a reply appearing
    /// to "repeat" — `animate` (== `isNew`) flips false so recycles skip typing.
    func markMessageSeen(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }), messages[index].isNew else { return }
        messages[index].isNew = false
    }

    /// Marks every message as already seen so the transcript doesn't replay
    /// its typewriter animation when the view is rebuilt (tab switch,
    /// LazyVStack recycling). Called from the view's `onDisappear`.
    func markAllMessagesSeen() {
        for index in messages.indices where messages[index].isNew {
            messages[index].isNew = false
        }
    }

    private func chatErrorMessage(for error: Error) -> String {
        AppLogger.log("[ChatViewModel] Error details: \(String(describing: error))", type: .error)

        // spec-010: the chat function's structured error body already has a
        // user-facing message written for exactly this case — prefer it
        // over the generic per-status-code guesses below.
        if let chatError = error as? ChatServiceError {
            return chatError.errorDescription ?? "Unable to get a response. Please check your connection and try again."
        }

        let code = extractHTTPStatusCode(from: error)
        AppLogger.log("[ChatViewModel] Extracted HTTP code: \(code ?? -1)", type: .error)

        switch code {
        case 404:
            return "Chat service is not set up yet. Please ensure Edge Functions are deployed."
        case 401:
            return "Please sign in again."
        case 429:
            return "You've sent a lot of messages recently. Please wait a bit and try again."
        default:
            return "Unable to get a response. Please check your connection and try again."
        }
    }

    private func extractHTTPStatusCode(from error: Error) -> Int? {
        let mirror = Mirror(reflecting: error)
        for child in mirror.children where child.label == "httpError" {
            let tupleMirror = Mirror(reflecting: child.value)
            for tupleChild in tupleMirror.children {
                if let code = tupleChild.value as? Int {
                    return code
                }
            }
            return nil
        }
        return nil
    }

    private func mapSourcesToCitations(_ sources: [ChatSource]) -> [JournalCitation] {
        sources.compactMap { source in
            guard let entryId = UUID(uuidString: source.id) else { return nil }

            let date: Date
            if let parsed = ISO8601DateFormatter().date(from: source.createdAt) {
                date = parsed
            } else {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                date = formatter.date(from: source.createdAt) ?? Date()
            }

            return JournalCitation(
                entryId: entryId,
                entryTitle: "",
                entryDate: date,
                excerpt: source.preview
            )
        }
    }

}
