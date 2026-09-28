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

    // MARK: - Initialization

    init(chatService: ChatServiceProtocol = ChatService.shared) {
        self.chatService = chatService
    }

    /// Fetches the user's first name for personalized welcome messages
    func fetchUserName() async {
        do {
            if let profile = try await UserService.shared.getCurrentProfile(),
               let fullName = profile.fullName {
                let parts = fullName.split(separator: " ")
                userName = parts.first.map(String.init)
            }
        } catch {
            #if DEBUG
            print("⚠️ [ChatViewModel] Failed to fetch user name: \(error)")
            #endif
        }
    }

    // MARK: - JSON Content Extraction

    /// Extracts clean body text from potentially JSON-formatted content
    /// Handles: raw JSON strings, legacy plain text, nested JSON
    private func extractBodyContent(from content: String, role: String) -> (body: String, aiContent: AIOutputContent?) {
        guard role == "assistant" else {
            return (content, nil)
        }

        // Try parsing as AIOutputContent JSON
        if let data = content.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(AIOutputContent.self, from: data) {
            return (parsed.body, parsed)
        }

        // Try parsing as generic JSON with body field
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let body = json["body"] as? String {
            let heading1 = json["heading1"] as? String
            let heading2 = json["heading2"] as? String

            // Extract inline citations from stored history JSON
            var inlineCitationInfos: [InlineCitationInfo]?
            if let rawCitations = json["inline_citations"] as? [[String: Any]] {
                inlineCitationInfos = rawCitations.compactMap { dict -> InlineCitationInfo? in
                    guard let ref = dict["ref"] as? Int,
                          let entryIdStr = dict["entry_id"] as? String,
                          let entryId = UUID(uuidString: entryIdStr),
                          let theme = dict["theme"] as? String else { return nil }
                    let dateStr = dict["date"] as? String ?? ""
                    return InlineCitationInfo(
                        ref: ref,
                        entryId: entryId,
                        theme: theme,
                        entryDate: Self.parseISO8601Date(dateStr),
                        excerpt: ""
                    )
                }
                if inlineCitationInfos?.isEmpty == true { inlineCitationInfos = nil }
            }

            let aiContent = AIOutputContent(
                heading1: heading1,
                heading2: heading2,
                body: body,
                inlineCitations: inlineCitationInfos
            )
            return (body, aiContent)
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
                    return (extracted, aiContent)
                }
            }

            // Raw JSON leaked through - regex extraction failed, show user-friendly message
            #if DEBUG
            print("⚠️ [ChatViewModel] Raw JSON detected but body extraction failed")
            #endif
            let fallbackBody = "I had trouble processing this response. Please try again."
            let aiContent = AIOutputContent(heading1: nil, heading2: nil, body: fallbackBody)
            return (fallbackBody, aiContent)
        }

        // Final check: if content still looks like raw JSON (starts with '{'), sanitize
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            #if DEBUG
            print("⚠️ [ChatViewModel] Unexpected JSON-like content in message")
            #endif
            let fallbackBody = "I had trouble processing this response. Please try again."
            let aiContent = AIOutputContent(heading1: nil, heading2: nil, body: fallbackBody)
            return (fallbackBody, aiContent)
        }

        // Not JSON - return as-is (legacy plain text)
        let aiContent = AIOutputContent(heading1: nil, heading2: nil, body: content)
        return (content, aiContent)
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

        isLoading = true

        Task {
            do {
                let response = try await chatService.sendMessage(text, sessionId: currentSessionId)

                // Update current session ID from response (handles new session creation)
                if let newSessionId = UUID(uuidString: response.sessionId) {
                    if currentSessionId == nil {
                        currentSessionId = newSessionId
                        // Refresh sessions list when a new session is created
                        await fetchSessions()
                    }
                }

                let citations = mapSourcesToCitations(response.sources)
                let inlineCitationInfos = mapInlineCitations(
                    response.inlineCitations ?? [],
                    sources: response.sources
                )
                let aiMessage = ChatMessage.aiMessage(
                    heading1: response.heading1,
                    heading2: response.heading2,
                    body: response.reply,
                    citations: citations.isEmpty ? nil : citations,
                    inlineCitations: inlineCitationInfos.isEmpty ? nil : inlineCitationInfos,
                    isNew: true
                )
                appendMessage(aiMessage)

                // Update cache after successful send
                if let sessionId = currentSessionId {
                    messageCache[sessionId] = messages
                }
            } catch {
                #if DEBUG
                print("❌ [ChatViewModel] sendMessage error: \(error)")
                #endif
                errorMessage = chatErrorMessage(for: error)
                showingError = true
            }
            isLoading = false
        }
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
            #if DEBUG
            print("❌ [ChatViewModel] fetchSessions error: \(error)")
            #endif
        }
        isLoadingSessions = false
    }

    /// Loads a specific session's messages
    func loadSession(_ session: ChatSession) async {
        currentSessionId = session.id

        // Check cache first - if cached, show instantly without loading state
        if let cached = messageCache[session.id] {
            messages = cached
            return
        }

        // Not cached - show loading state and fetch from database
        messages = []
        isLoading = true

        do {
            let messageDTOs = try await chatService.loadSessionMessages(sessionId: session.id)
            let loadedMessages = messageDTOs.map { dto -> ChatMessage in
                let (body, aiContent) = extractBodyContent(from: dto.content, role: dto.role)

                if dto.role == "assistant", let aiContent = aiContent {
                    // Loaded messages: isNew = false (default) - no animation
                    return ChatMessage.aiMessage(
                        heading1: aiContent.heading1,
                        heading2: aiContent.heading2,
                        body: body,
                        citations: nil // Citations are not persisted
                    )
                }

                // User messages: isNew = false (default)
                return ChatMessage(content: dto.content, isFromUser: dto.role == "user")
            }
            messages = loadedMessages
            // Cache the loaded messages
            messageCache[session.id] = loadedMessages
        } catch {
            #if DEBUG
            print("❌ [ChatViewModel] loadSession error: \(error)")
            #endif
            errorMessage = "Failed to load conversation history."
            showingError = true
        }
        isLoading = false
    }

    /// Starts a new chat by clearing state
    func startNewChat() {
        messages = []
        currentSessionId = nil
        inputText = ""
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
            #if DEBUG
            print("❌ [ChatViewModel] deleteSession error: \(error)")
            #endif
            errorMessage = "Failed to delete conversation."
            showingError = true
        }
    }

    // MARK: - Retry

    /// Retries sending the last user message if it failed
    func retrySend() {
        guard let lastUserMessage = messages.last(where: { $0.isFromUser }) else { return }
        sendMessage(prompt: lastUserMessage.content)
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
        return (summary.title, summary.content)
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

    // MARK: - Private Helpers

    private func appendMessage(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > maxMessagesInMemory {
            messages.removeFirst(messages.count - maxMessagesInMemory)
        }
    }

    private func chatErrorMessage(for error: Error) -> String {
        let code = extractHTTPStatusCode(from: error)
        switch code {
        case 404:
            return "Chat service is not set up yet. Please ensure Edge Functions are deployed."
        case 401:
            return "Please sign in again."
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

    private func mapInlineCitations(
        _ inlineCitations: [InlineCitation],
        sources: [ChatSource]
    ) -> [InlineCitationInfo] {
        inlineCitations.compactMap { citation in
            guard let entryId = UUID(uuidString: citation.entryId) else { return nil }
            let source = sources.first { $0.id == citation.entryId }
            let dateString = citation.date ?? source?.createdAt ?? ""
            let date = Self.parseISO8601Date(dateString)
            return InlineCitationInfo(
                ref: citation.ref,
                entryId: entryId,
                theme: citation.theme,
                entryDate: date,
                excerpt: source?.preview ?? ""
            )
        }
    }

    private static func parseISO8601Date(_ string: String) -> Date {
        if let parsed = ISO8601DateFormatter().date(from: string) {
            return parsed
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? Date()
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
