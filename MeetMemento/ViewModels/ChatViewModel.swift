import Foundation
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var loadingPhrase: String = LoadingStatus.fallback
    @Published var errorMessage: String?
    @Published var showingError: Bool = false

    // Session management
    @Published var currentSessionId: UUID?

    /// Bumped exactly once per *transcript replacement*: a different
    /// conversation loaded, or a new one started. The chat view watches this to
    /// decide when to drop its send pin and open at the bottom of the thread.
    ///
    /// Deliberately not `currentSessionId`, which the view used to watch. A
    /// brand new chat has no id until the first reply's `.final` mints one — so
    /// `currentSessionId` changes MID-CONVERSATION, and the view read that as
    /// "the user opened a different conversation": on every new chat's first
    /// send, the reply completing scrolled the transcript to the bottom and
    /// destroyed the pin, leaving the reader on the last line of an answer they
    /// had just watched arrive.
    ///
    /// The rule for any new call site: bump only if `messages` is being
    /// replaced with a different conversation's contents in the same update.
    /// Cancelling in-flight work is not that — `cancelActiveTasks()` runs on
    /// every swipe back to Journal and leaves the transcript exactly as it is.
    /// Giving the conversation already on screen an id is not that either.
    @Published private(set) var transcriptGeneration = 0
    @Published var sessions: [ChatSession] = []
    @Published var isLoadingSessions: Bool = false

    // Summary generation
    @Published var isSummarizing: Bool = false

    /// The assistant message currently being streamed into, or nil once the
    /// stream settles (success, error, or cancel). Narration mode observes
    /// this to know which message to read aloud as it arrives; ordinary chat
    /// UI ignores it (bubbles already track their own `isStreaming`).
    @Published private(set) var streamingAssistantMessageID: UUID?

    /// Where a send came from.
    ///
    /// Four entry points reach `performSend` — the composer, narration,
    /// regenerate, and retry — and only the composer one has an on-screen
    /// composer to fly a bubble out of. The view layer cannot tell them apart
    /// from `messages` alone, so the origin has to travel with the send.
    enum SendOrigin: Equatable { case composer, narration, regenerate, retry }

    /// Published once per send, *after* both appends, so the view observes a
    /// consistent `messages` array rather than the half-mutated state between
    /// the user message and the assistant placeholder.
    ///
    /// `seq` keeps consecutive retries of the same message id distinguishable —
    /// without it `Equatable` would collapse them and `onChange` would not fire.
    struct SendTicket: Equatable {
        let userMessageID: UUID
        let origin: SendOrigin
        let seq: Int
    }

    @Published private(set) var lastSend: SendTicket?
    private var sendSeq = 0

    // Feedback state per message (thumbs up/down) - using Sets for boolean-like behavior
    @Published var thumbsUpMessages: Set<UUID> = []
    @Published var thumbsDownMessages: Set<UUID> = []
    @Published var reportedMessageIDs: Set<UUID> = []
    @Published var feedbackDraft: FeedbackDraft?
    @Published var feedbackToast: String?

    /// Whether there is an active chat conversation (1+ messages)
    var hasActiveChat: Bool {
        !messages.isEmpty || currentSessionId != nil
    }

    /// True when the transcript has enough substance to turn into a journal
    /// entry: at least two user turns and one assistant reply. Independent of
    /// `hasActiveChat` — a minted session id with an empty transcript is not
    /// summarizable.
    var canSummarizeChat: Bool { Self.canSummarize(messages) }

    /// Counts a user turn if it has text or attached photos. Failed sends with
    /// content still count: the substance is on screen. Empty streaming
    /// assistant placeholders do not count until they have a body.
    static func canSummarize(_ messages: [ChatMessage]) -> Bool {
        var userCount = 0
        var assistantCount = 0
        for message in messages {
            if message.isFromUser {
                if countsAsUserTurn(message) { userCount += 1 }
            } else if countsAsAssistantReply(message) {
                assistantCount += 1
            }
        }
        return userCount >= 2 && assistantCount >= 1
    }

    private static func countsAsUserTurn(_ message: ChatMessage) -> Bool {
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty || !message.imageJPEGs.isEmpty
    }

    private static func countsAsAssistantReply(_ message: ChatMessage) -> Bool {
        !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // User info
    @Published var userName: String?

    private let chatService: ChatServiceProtocol
    private let feedbackStore: AnswerFeedbackStore
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

    /// Announces that `messages` is being replaced wholesale.
    /// See `transcriptGeneration` for the rule.
    private func beginNewTranscript() {
        transcriptGeneration += 1
    }

    private func track(_ task: Task<Void, Never>) {
        activeTasks.append(task)
    }

    /// Cancels every tracked in-flight task. Safe to call from `onDisappear`
    /// even with nothing in flight.
    func cancelActiveTasks() {
        sendGeneration += 1
        lastSend = nil
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        // Cancelled work can no longer finish, so don't leave the input
        // dimmed and the loading indicator up.
        isLoading = false
    }

    // MARK: - Initialization

    init(chatService: ChatServiceProtocol = ChatService.shared,
         feedbackStore: AnswerFeedbackStore = .shared) {
        self.chatService = chatService
        self.feedbackStore = feedbackStore
        seedUITestTranscriptIfRequested()
    }

    /// Seeds one tall completed turn when launched with `-SeedChatTranscript`.
    ///
    /// Exists for `ChatSendPinUITests`. The send choreography's pin is only
    /// exercised when the transcript is already taller than the viewport — with
    /// an empty thread the first row sits at content offset 0 and needs no
    /// scrolling at all, which is how a clamped scroll went unnoticed. Seeding
    /// the precondition makes that regression test hermetic and fast instead of
    /// waiting ~60s on live on-device generation.
    ///
    /// Compiled out of release builds entirely, so the flag cannot fire in a
    /// shipped app. It is deliberately NOT gated on `-UITesting` as well —
    /// that flag forces the Welcome screen, and this test needs the real
    /// post-onboarding app (same launch posture as `TTSReadAloudUITests`).
    private func seedUITestTranscriptIfRequested() {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-SeedChatTranscript") else { return }

        messages = [
            ChatMessage(content: Self.uiTestSeedPrompt, isFromUser: true),
            ChatMessage.aiMessage(body: Self.uiTestSeedReply)
        ]
        #endif
    }

    /// Verbatim in `ChatSendPinUITests` — it queries the bubble by this text.
    static let uiTestSeedPrompt = "What have I been writing about?"
    /// Deliberately long: the seeded turn has to exceed one viewport for the
    /// second send to require a real scroll.
    static let uiTestSeedReply = String(
        repeating: "You have been circling the same few themes for a while now. ", count: 40
    )

    /// Warm the on-device model so the first send doesn't pay cold model load.
    /// Call when the chat view appears / the input gains focus.
    func prewarm() {
        chatService.prewarm()
    }

    /// Prefill the next turn from the current conversation's history.
    /// Safe to call repeatedly — the intelligence layer dedupes by fingerprint.
    func prewarmNextTurn() {
        chatService.prewarmConversation(sessionId: currentSessionId)
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
    private func extractBodyContent(from content: String, role: String) -> (
        body: String,
        aiContent: AIOutputContent?,
        citations: [JournalCitation]?,
        safety: ChatSafetyPresentation,
        promptVersion: String?,
        modelIdentifier: String?,
        zone: String?,
        wasDegraded: Bool?
    ) {
        guard role == "assistant" else {
            return (content, nil, nil, .none, nil, nil, nil, nil)
        }

        // Try parsing as generic JSON with body field and sources. One parse
        // serves body, headings, citations AND the safety presentation —
        // loadSession used to re-parse the same string for the safety key
        // (spec 029 Amendment A).
        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let body = json["body"] as? String {
            let heading1 = json["heading1"] as? String
            let heading2 = json["heading2"] as? String
            let safety = (json["safety_presentation"] as? String)
                .flatMap(ChatSafetyPresentation.init(rawValue:)) ?? .none
            let promptVersion = json["prompt_version"] as? String
            let modelIdentifier = json["model_identifier"] as? String
            let zone = json["zone"] as? String
            let wasDegraded = json["was_degraded"] as? Bool

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

                    return JournalCitation(
                        entryId: entryId,
                        entryTitle: "",
                        entryDate: Self.parseISODate(createdAt) ?? Date(),
                        excerpt: preview
                    )
                }
            }

            let aiContent = AIOutputContent(heading1: heading1, heading2: heading2, body: body, citations: citations)
            return (body, aiContent, citations, safety, promptVersion, modelIdentifier, zone, wasDegraded)
        }

        // Try parsing as AIOutputContent JSON (legacy format without sources)
        if let data = content.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(AIOutputContent.self, from: data) {
            return (parsed.body, parsed, parsed.citations, .none, nil, nil, nil, nil)
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
                    return (extracted, aiContent, nil, .none, nil, nil, nil, nil)
                }
            }

            // Raw JSON leaked through - regex extraction failed, show user-friendly message
            AppLogger.log("[ChatViewModel] Raw JSON detected but body extraction failed", type: .error)
            let fallbackBody = "I had trouble processing this response. Please try again."
            let aiContent = AIOutputContent(heading1: nil, heading2: nil, body: fallbackBody)
            return (fallbackBody, aiContent, nil, .none, nil, nil, nil, nil)
        }

        // Final check: if content still looks like raw JSON (starts with '{'), sanitize
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            AppLogger.log("[ChatViewModel] Unexpected JSON-like content in message", type: .error)
            let fallbackBody = "I had trouble processing this response. Please try again."
            let aiContent = AIOutputContent(heading1: nil, heading2: nil, body: fallbackBody)
            return (fallbackBody, aiContent, nil, .none, nil, nil, nil, nil)
        }

        // Not JSON - return as-is (legacy plain text)
        let aiContent = AIOutputContent(heading1: nil, heading2: nil, body: content)
        return (content, aiContent, nil, .none, nil, nil, nil, nil)
    }

    // MARK: - Send Message

    func sendMessage(prompt: String? = nil, images: [Data] = [], origin: SendOrigin = .composer) {
        let typed: String
        if let prompt = prompt {
            typed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            typed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !isLoading else { return }
        let modelText: String
        if typed.isEmpty {
            guard !images.isEmpty else { return }
            modelText = Self.attachedPhotosPrompt(count: images.count)
        } else {
            modelText = typed
        }

        if prompt == nil {
            inputText = ""
        }

        let userMessage = ChatMessage(content: typed, isFromUser: true, imageJPEGs: images, isNew: true)
        appendMessage(userMessage)

        performSend(text: modelText, images: images, userMessageId: userMessage.id, origin: origin)
    }

    /// Copy the model reads when the person sends photos without typing.
    static func attachedPhotosPrompt(count: Int) -> String {
        if count <= 1 {
            return "I've attached a photo. Look at it carefully and respond to what you see."
        }
        return "I've attached \(count) photos. Look at them carefully and respond to what you see."
    }

    /// Retries a user message that never got a reply — a failed send
    /// (spec-010) or an unanswered last turn. Reuses the existing bubble
    /// instead of appending a duplicate.
    func retryMessage(_ message: ChatMessage) {
        guard message.isFromUser, !isLoading else { return }
        guard isUnansweredUserMessage(message) else { return }
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            let next = index + 1
            if next < messages.count, !messages[next].isFromUser {
                messages.remove(at: next)
            }
        }
        setSendFailed(false, forMessageId: message.id)
        let typed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelText = typed.isEmpty
            ? Self.attachedPhotosPrompt(count: message.imageJPEGs.count)
            : typed
        performSend(text: modelText, images: message.imageJPEGs, userMessageId: message.id, origin: .retry)
    }

    /// True when this user turn has no assistant reply to show: a failed send,
    /// or the last user message with no (or empty) follow-up while idle.
    func isUnansweredUserMessage(_ message: ChatMessage) -> Bool {
        guard message.isFromUser else { return false }
        if message.sendFailed { return true }
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return false }
        if messages[(index + 1)...].contains(where: \.isFromUser) { return false }
        if isLoading { return false }
        guard let reply = messages[(index + 1)...].first(where: { !$0.isFromUser }) else {
            return true
        }
        if reply.isStreaming { return false }
        return assistantHasNoVisibleContent(reply)
    }

    private func assistantHasNoVisibleContent(_ message: ChatMessage) -> Bool {
        let body = (message.aiOutputContent?.body ?? message.content)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let heading1 = (message.aiOutputContent?.heading1 ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let heading2 = (message.aiOutputContent?.heading2 ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty && heading1.isEmpty && heading2.isEmpty
    }

    private func setSendFailed(_ failed: Bool, forMessageId id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].sendFailed = failed
    }

    /// Shared send path for both a fresh message and a retry of a failed
    /// one. On failure, the user's message stays in the transcript marked
    /// `sendFailed` — never rolled back — so retrying doesn't require
    /// retyping.
    private func performSend(text: String, images: [Data] = [], userMessageId: UUID, origin: SendOrigin) {
        isLoading = true
        let generation = sendGeneration
        // Prior turns only — the current user message is already appended.
        let priorHistory: [ChatTurn] = messages.dropLast().map {
            ChatTurn(role: $0.isFromUser ? .user : .assistant, text: $0.content)
        }
        let answeringLastQuestion = origin == .narration
            && ConversationalMove.lastAssistantQuestion(in: priorHistory) != nil
        let turn = TurnClassifier.classify(
            text,
            hasHistory: messages.count > 1,
            lastAssistantAskedQuestion: answeringLastQuestion
        )
        loadingPhrase = LoadingStatus.phrase(for: turn, history: priorHistory)
        if let second = LoadingStatus.followUpPhrase(for: turn, history: priorHistory) {
            track(Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self, generation == self.sendGeneration, !Task.isCancelled, self.isLoading else { return }
                self.loadingPhrase = second
            })
        }

        // Empty assistant bubble appended immediately; it fills as the model
        // streams so text appears the moment generation starts (no waiting for
        // the whole reply, no artificial typewriter).
        let assistantId = UUID()
        appendMessage(ChatMessage.aiMessage(id: assistantId, body: "", isNew: true))
        streamingAssistantMessageID = assistantId

        // Both appends have landed, so the transcript is consistent. This is
        // the signal the send choreography drives off — never `messages.count`,
        // which fires twice per send and whose second firing points at the
        // empty assistant placeholder rather than the user's message.
        sendSeq += 1
        lastSend = SendTicket(userMessageID: userMessageId, origin: origin, seq: sendSeq)

        track(Task { [weak self] in
            guard let self else { return }
            LiveTurnClock.shared.beginTurn()
            // Whatever ends the stream — success, error, or cancel — settle the
            // assistant bubble so the typewriter can complete instead of blinking
            // its caret forever. On the success path `.final` already cleared this,
            // so the flip is a no-op; on error/cancel `.final` never arrives, so
            // this is the only thing that settles a partial reply.
            defer {
                LiveTurnClock.shared.finishAndLog()
                if let idx = messages.firstIndex(where: { $0.id == assistantId }),
                   messages[idx].isStreaming {
                    messages[idx].isStreaming = false
                }
                // Settle the narration observer with the bubble. Guarded so a
                // superseded send can't clear a newer send's marker.
                if streamingAssistantMessageID == assistantId {
                    streamingAssistantMessageID = nil
                }
            }
            var sawContent = false

            // Delta coalescing (spec 029 R6): snapshots can arrive far faster
            // than 30Hz, and every application replaces the message value and
            // re-diffs the transcript. Bodies are cumulative, so intermediate
            // snapshots are safely superseded — apply at most every 33ms, with
            // a trailing flush so a stream stall can't leave the bubble stale.
            // Narration applies the first delta immediately and coalesces at
            // ~16ms so the chunker can speak a clause as soon as one exists.
            let deltaClock = ContinuousClock()
            let isNarration = origin == .narration
            let minDeltaInterval: Duration = isNarration ? .milliseconds(16) : .milliseconds(33)
            var lastDeltaApply = deltaClock.now - minDeltaInterval
            var appliedFirstNarrationDelta = false
            var pendingDelta: (body: String, heading1: String?, heading2: String?,
                               citations: [JournalCitation]?)?
            // Mapped once per turn — the reviewed set is constant across deltas.
            var reviewedCitations: [JournalCitation]?
            var deltaFlushTask: Task<Void, Never>?
            defer { deltaFlushTask?.cancel() }

            @MainActor func applyPendingDelta() {
                guard let d = pendingDelta else { return }
                pendingDelta = nil
                lastDeltaApply = deltaClock.now
                updateStreamingMessage(id: assistantId, body: d.body,
                                       heading1: d.heading1, heading2: d.heading2,
                                       citations: d.citations,
                                       isStreaming: true)
            }

            do {
                for try await event in chatService.sendMessageStream(
                    text, sessionId: currentSessionId, images: images, spoken: origin == .narration
                ) {
                    // Cancelled or superseded mid-flight (user left / switched
                    // conversations): stop writing into whatever is on screen now.
                    guard generation == sendGeneration, !Task.isCancelled else { return }

                    switch event {
                    case .delta(let body, let heading1, let heading2, let sources):
                        // First visible token: drop the "thinking" indicator.
                        if isLoading { isLoading = false }
                        sawContent = sawContent || !body.isEmpty
                        // Reviewed-journals citations arrive from the first delta on
                        // grounded turns, so the "Reviewed your journals" link shows
                        // right away rather than waiting for `.final`. The set is
                        // constant for the whole turn (computed before the model's
                        // first token), so map it once, not per delta
                        // (spec 029 Amendment A: this ran per snapshot on main).
                        if reviewedCitations == nil {
                            let mapped = mapSourcesToCitations(sources)
                            reviewedCitations = mapped.isEmpty ? nil : mapped
                        }
                        pendingDelta = (body, heading1, heading2, reviewedCitations)
                        let applyFirstImmediately = isNarration && !appliedFirstNarrationDelta
                        if applyFirstImmediately || deltaClock.now - lastDeltaApply >= minDeltaInterval {
                            deltaFlushTask?.cancel()
                            deltaFlushTask = nil
                            applyPendingDelta()
                            appliedFirstNarrationDelta = true
                        } else if deltaFlushTask == nil {
                            deltaFlushTask = Task { [weak self] in
                                try? await Task.sleep(for: minDeltaInterval)
                                guard !Task.isCancelled, let self,
                                      generation == self.sendGeneration else { return }
                                applyPendingDelta()
                                deltaFlushTask = nil
                            }
                        }

                    case .final(let response):
                        deltaFlushTask?.cancel()
                        deltaFlushTask = nil
                        pendingDelta = nil
                        // Handle new-session creation (first message of a chat).
                        // This deliberately does NOT bump `transcriptGeneration`:
                        // it is the conversation already on screen getting a
                        // name, not a different one being loaded.
                        if let newSessionId = UUID(uuidString: response.sessionId), currentSessionId == nil {
                            currentSessionId = newSessionId
                            await fetchSessions()
                        }
                        let citations = mapSourcesToCitations(response.sources)
                        // Carry the Safety route through: ChatService now returns a
                        // designed crisis/refusal reply as `.final` rather than
                        // throwing, so dropping this would render the crisis card
                        // as plain prose.
                        updateStreamingMessage(id: assistantId, body: response.reply,
                                               heading1: response.heading1, heading2: response.heading2,
                                               citations: citations.isEmpty ? nil : citations,
                                               safetyPresentation: response.safetyPresentation,
                                               isStreaming: false)
                        sawContent = sawContent || !response.reply.isEmpty
                        if let sessionId = currentSessionId { messageCache[sessionId] = messages }
                        // Next-turn prefill while the user reads / the typewriter
                        // settles — history now includes this turn (persisted
                        // before `.final`).
                        prewarmNextTurn()
                    }
                }
            } catch {
                AppLogger.log("[ChatViewModel] sendMessage error: \(error)", type: .error)

                // A guardrail / safety route is a designed state, not a failure:
                // it fills the assistant bubble with authored copy (and for
                // crisis, the static resource card) — no alert, no retry.
                if isDesignedEmptyState(error), generation == sendGeneration, !Task.isCancelled {
                    let presentation = safetyPresentation(for: error)
                    let body = (error as? IntelligenceError)?.errorDescription
                        ?? IntelligenceError.guardrailRefusal.errorDescription
                        ?? ""
                    updateStreamingMessage(
                        id: assistantId,
                        body: body,
                        heading1: nil, heading2: nil, citations: nil,
                        safetyPresentation: presentation,
                        isStreaming: false
                    )
                    sawContent = true
                } else {
                    // Drop the empty placeholder so a failed send doesn't leave a
                    // blank bubble; keep the retry affordance on the user's message.
                    if !sawContent { messages.removeAll { $0.id == assistantId } }
                    // A cancelled/superseded send is not a failure: it is the
                    // user swiping back to Journal, or switching conversations.
                    // Both the alert AND the "Failed to send · Retry" row have
                    // to be suppressed for it — marking the message failed used
                    // to sit above this condition, so leaving the chat mid-send
                    // left a red retry row on a message that was never rejected.
                    if generation == sendGeneration, !Task.isCancelled,
                       !(error is CancellationError) {
                        setSendFailed(true, forMessageId: userMessageId)
                        errorMessage = chatErrorMessage(for: error)
                        showingError = true
                    }
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
    private func updateStreamingMessage(
        id: UUID,
        body: String,
        heading1: String?,
        heading2: String?,
        citations: [JournalCitation]?,
        safetyPresentation: ChatSafetyPresentation = .none,
        isStreaming: Bool
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = ChatMessage.aiMessage(
            id: id,
            heading1: heading1,
            heading2: heading2,
            body: body,
            citations: citations,
            safetyPresentation: safetyPresentation,
            timestamp: messages[index].timestamp,
            isNew: true,
            isStreaming: isStreaming
        )
    }

    // MARK: - Clear Conversation

    func clearConversation() {
        beginNewTranscript()
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
        // Above the cached early-return below: that path replaces `messages`
        // just as completely as the fetched one.
        beginNewTranscript()
        currentSessionId = session.id

        // Check cache first - if cached, show instantly without loading state
        if let cached = messageCache[session.id] {
            messages = cached
            // Still load feedback for cached messages
            await loadFeedbackForMessages()
            prewarmNextTurn()
            return
        }

        // Not cached - show loading state and fetch from database
        messages = []
        isLoading = true
        loadingPhrase = LoadingStatus.sessionLoad

        do {
            let messageDTOs = try await chatService.loadSessionMessages(sessionId: session.id)
            let loadedMessages = messageDTOs.map { dto -> ChatMessage in
                // One parse per message: body, headings, citations, and the
                // spec 026 safety presentation (restored so reopening a saved
                // conversation re-renders the crisis card rather than
                // silently downgrading it to prose) all come from the same
                // extraction (spec 029 Amendment A — this used to parse the
                // JSON twice per assistant message).
                let extracted = extractBodyContent(from: dto.content, role: dto.role)

                if dto.role == "assistant", let aiContent = extracted.aiContent {
                    // Loaded messages: isNew = false (default) - no animation
                    // Citations are now persisted and extracted from stored message
                    return ChatMessage.aiMessage(
                        id: dto.id,
                        heading1: aiContent.heading1,
                        heading2: aiContent.heading2,
                        body: extracted.body,
                        citations: extracted.citations,
                        safetyPresentation: extracted.safety,
                        promptVersion: extracted.promptVersion,
                        modelIdentifier: extracted.modelIdentifier,
                        zone: extracted.zone,
                        wasDegraded: extracted.wasDegraded
                    )
                }

                // User messages: isNew = false (default)
                return ChatMessage(id: dto.id, content: dto.content, isFromUser: dto.role == "user")
            }
            messages = loadedMessages
            // Cache the loaded messages
            messageCache[session.id] = loadedMessages
            // Load feedback state for the messages
            await loadFeedbackForMessages()
            prewarmNextTurn()
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
        // `deleteSession` reaches here when the deleted conversation is the one
        // on screen, so it inherits this bump rather than adding its own.
        beginNewTranscript()
        messages = []
        lastSend = nil
        currentSessionId = nil
        inputText = ""
        thumbsUpMessages = []
        thumbsDownMessages = []
        reportedMessageIDs = []
        feedbackDraft = nil
        prewarmNextTurn()
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
        guard canSummarizeChat else {
            throw NSError(domain: "ChatViewModel", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Conversation isn't long enough to summarize"])
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
        // Only the last reply can be regenerated. The re-send always appends at
        // the end, so regenerating an older turn used to lift it out of the
        // middle of the conversation and drop it at the bottom — reordering the
        // transcript — while the store kept the original where it was.
        guard index == messages.count - 1 else { return }
        let precedingUserMessage = messages[index - 1]
        guard precedingUserMessage.isFromUser else { return }
        let userContent = precedingUserMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userContent.isEmpty else { return }
        messages.removeSubrange((index - 1)...index)
        // Keep the store in step. Without this the rejected turn stayed on disk,
        // the re-sent one was appended beside it, and the history handed to the
        // model on the next turn still contained the reply the user rejected.
        if let sessionId = currentSessionId {
            LocalChatStore.shared.removeLastTurn(from: sessionId)
            messageCache[sessionId] = messages
        }
        sendMessage(prompt: userContent, origin: .regenerate)
    }

    // MARK: - Feedback

    func isReported(_ messageId: UUID) -> Bool {
        reportedMessageIDs.contains(messageId)
    }

    /// Toggles thumbs up. Persists immediately (spec 041 R2).
    func toggleThumbsUp(for messageId: UUID) {
        if thumbsUpMessages.contains(messageId) {
            thumbsUpMessages.remove(messageId)
            persistFeedback(
                messageID: messageId,
                rating: .none,
                flaggedForReview: isReported(messageId),
                category: isReported(messageId) ? feedbackStore.feedback(for: messageId)?.category : nil,
                note: isReported(messageId) ? feedbackStore.feedback(for: messageId)?.note : nil,
                source: .thumbsUp
            )
        } else {
            thumbsUpMessages.insert(messageId)
            thumbsDownMessages.remove(messageId)
            persistFeedback(
                messageID: messageId,
                rating: .positive,
                flaggedForReview: isReported(messageId),
                category: nil,
                note: nil,
                source: .thumbsUp
            )
        }
    }

    /// Opens the reason sheet unless this message is already downvoted (undo).
    func toggleThumbsDown(for messageId: UUID) {
        if thumbsDownMessages.contains(messageId) {
            thumbsDownMessages.remove(messageId)
            let reported = isReported(messageId)
            persistFeedback(
                messageID: messageId,
                rating: .none,
                flaggedForReview: reported,
                category: reported ? feedbackStore.feedback(for: messageId)?.category : nil,
                note: reported ? feedbackStore.feedback(for: messageId)?.note : nil,
                source: .thumbsDown
            )
            return
        }
        beginFeedback(messageID: messageId, source: .thumbsDown)
    }

    func beginFeedback(messageID: UUID, source: FeedbackDraft.Source) {
        let existing = feedbackStore.feedback(for: messageID)
        feedbackDraft = FeedbackDraft(
            messageID: messageID,
            source: source,
            category: existing?.category,
            note: existing?.note ?? ""
        )
    }

    func cancelFeedbackDraft() {
        feedbackDraft = nil
    }

    func submitFeedbackDraft(category: AnswerFeedbackCategory, note: String) {
        guard let draft = feedbackDraft else { return }
        feedbackDraft = nil
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.source {
        case .thumbsDown:
            thumbsDownMessages.insert(draft.messageID)
            thumbsUpMessages.remove(draft.messageID)
            persistFeedback(
                messageID: draft.messageID,
                rating: .negative,
                flaggedForReview: isReported(draft.messageID),
                category: category,
                note: trimmed.isEmpty ? nil : trimmed,
                source: .thumbsDown
            )
            feedbackToast = "Thanks — we'll use this to improve."
        case .report:
            reportedMessageIDs.insert(draft.messageID)
            let rating: AnswerFeedbackRating
            if thumbsUpMessages.contains(draft.messageID) {
                rating = .positive
            } else if thumbsDownMessages.contains(draft.messageID) {
                rating = .negative
            } else {
                rating = .none
            }
            persistFeedback(
                messageID: draft.messageID,
                rating: rating,
                flaggedForReview: true,
                category: category,
                note: trimmed.isEmpty ? nil : trimmed,
                source: .report
            )
            feedbackToast = "Reported for review."
        }
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
        let assistantMessages = messages.filter { !$0.isFromUser }
        guard !assistantMessages.isEmpty else { return }

        let byID = feedbackStore.feedback(forMessageIDs: assistantMessages.map(\.id))
        thumbsUpMessages = []
        thumbsDownMessages = []
        reportedMessageIDs = []
        for message in assistantMessages {
            let row = byID[message.id]
                ?? feedbackStore.feedbackMatching(assistantReply: message.content)
            guard let row else { continue }
            switch row.rating {
            case .positive:
                thumbsUpMessages.insert(message.id)
            case .negative:
                thumbsDownMessages.insert(message.id)
            case .none:
                break
            }
            if row.flaggedForReview {
                reportedMessageIDs.insert(message.id)
            }
        }
    }

    private func persistFeedback(
        messageID: UUID,
        rating: AnswerFeedbackRating,
        flaggedForReview: Bool,
        category: AnswerFeedbackCategory?,
        note: String?,
        source: AnswerFeedbackSource
    ) {
        let snapshot = snapshot(for: messageID)
        _ = feedbackStore.upsert(AnswerFeedback(
            messageID: messageID,
            sessionID: currentSessionId,
            rating: rating,
            flaggedForReview: flaggedForReview,
            category: category,
            note: note,
            source: source,
            userPrompt: snapshot.prompt,
            assistantReply: snapshot.reply,
            citationEntryIDs: snapshot.citationIDs,
            promptVersion: snapshot.promptVersion,
            modelIdentifier: snapshot.modelIdentifier,
            zone: snapshot.zone,
            wasDegraded: snapshot.wasDegraded,
            safetyPresentation: snapshot.safety
        ))
    }

    private func snapshot(for messageID: UUID) -> (
        prompt: String,
        reply: String,
        citationIDs: [UUID],
        promptVersion: String?,
        modelIdentifier: String?,
        zone: String?,
        wasDegraded: Bool?,
        safety: String
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return ("", "", [], nil, nil, nil, nil, ChatSafetyPresentation.none.rawValue)
        }
        let assistant = messages[index]
        let prompt: String
        if index > 0, messages[index - 1].isFromUser {
            prompt = messages[index - 1].content
        } else {
            prompt = ""
        }
        return (
            prompt,
            assistant.content,
            assistant.citations?.map(\.entryId) ?? [],
            assistant.promptVersion,
            assistant.modelIdentifier,
            assistant.zone,
            assistant.wasDegraded,
            assistant.safetyPresentation.rawValue
        )
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

    /// Designed empty / safety states (spec 017 R4 / spec 026) — never alerts.
    private func isDesignedEmptyState(_ error: Error) -> Bool {
        guard let intelligenceError = error as? IntelligenceError else { return false }
        switch intelligenceError {
        case .guardrailRefusal, .crisisResource, .safetyRefusal:
            return true
        default:
            return false
        }
    }

    private func safetyPresentation(for error: Error) -> ChatSafetyPresentation {
        guard let intelligenceError = error as? IntelligenceError else { return .none }
        switch intelligenceError {
        case .crisisResource: return .crisisResource
        case .safetyRefusal: return .hardRefuse
        case .guardrailRefusal: return .emptyObservation
        default: return .none
        }
    }

    private func chatErrorMessage(for error: Error) -> String {
        AppLogger.log("[ChatViewModel] Error details: \(String(describing: error))", type: .error)

        // IntelligenceError already carries copy written for each case — the
        // unavailability reasons in particular ("Apple Intelligence is still
        // getting ready") tell the user something true and actionable.
        if let intelligenceError = error as? IntelligenceError {
            return intelligenceError.errorDescription ?? Self.genericFailureMessage
        }

        return Self.genericFailureMessage
    }

    /// Deliberately says nothing about connectivity. Generation is on-device;
    /// the app has no network path, so "check your connection" was advice the
    /// user could not act on and that misdescribed every real failure.
    private static let genericFailureMessage = "I couldn't put a reply together just now. Please try again."

    /// Static and reused (spec 029 Amendment A): this used to allocate 1–2
    /// fresh formatters per source, and it ran per streamed delta on the main
    /// actor. ISO8601DateFormatter is thread-safe.
    private static let isoPlain = ISO8601DateFormatter()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseISODate(_ string: String) -> Date? {
        isoPlain.date(from: string) ?? isoFractional.date(from: string)
    }

    private func mapSourcesToCitations(_ sources: [ChatSource]) -> [JournalCitation] {
        sources.compactMap { source in
            guard let entryId = UUID(uuidString: source.id) else { return nil }
            return JournalCitation(
                entryId: entryId,
                entryTitle: "",
                entryDate: Self.parseISODate(source.createdAt) ?? Date(),
                excerpt: source.preview
            )
        }
    }

}
