import XCTest
@testable import withMemento

/// A starter card must never put words in the person's mouth.
///
/// This is the property, not a style preference. `ChatService.summarizeChat`
/// maps the on-screen messages to `ChatTurn`s by `isFromUser` and hands them to
/// `summarizeConversation`, which writes a journal entry. If tapping a card
/// appended a user bubble, that text would be summarised back into the person's
/// own journal as something they said — in an app whose whole promise is that
/// the journal is theirs.
///
/// So: the card shows a topic, the assistant opens, and nothing enters the
/// transcript or the store as the person's turn until they type.
@MainActor
final class StarterOpensConversationTests: XCTestCase {

    /// The mock throws unless configured, and a failed send correctly removes
    /// the empty assistant bubble — which would make every assertion below pass
    /// vacuously. Give it a reply.
    private func viewModel(reply: String = "What has this week been like for you?") -> ChatViewModel {
        let service = MockChatService()
        service.sendMessageImpl = { _, sessionId in
            ChatResponse(
                reply: reply,
                sources: [],
                sessionId: (sessionId ?? UUID()).uuidString
            )
        }
        return ChatViewModel(chatService: service)
    }

    /// A card whose question is shown on screen. Built by hand rather than
    /// from `DeepPromptBuilder` so this file tests the transcript property in
    /// isolation; the generated prompts get their own routing guard.
    private var analysisCard: ChatSuggestion {
        ChatSuggestion(
            label: "The thread through work",
            seed: "Look across my entries about work and tell me what keeps coming up.",
            themeName: "Patterns",
            kind: .analysis,
            promptText: "What keeps coming up when I write about work?"
        )
    }

    func test_tappingAStarter_appendsNoUserTurn() async {
        let model = viewModel()
        model.startConversation(about: ChatSuggestion.fallbackStarters[0])

        // Let the streamed reply land.
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(
            model.messages.allSatisfy { !$0.isFromUser },
            "a starter card wrote a turn as the person: "
                + model.messages.filter(\.isFromUser).map(\.content).joined(separator: " | ")
        )
    }

    func test_tappingAStarter_producesAnAssistantTurn() async {
        let model = viewModel()
        model.startConversation(about: ChatSuggestion.fallbackStarters[0])
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(model.messages.isEmpty, "the assistant never opened")
    }

    /// The seed is an instruction to the model, not something the person reads.
    func test_theSeedIsNeverShownOnScreen() async {
        let starter = ChatSuggestion.fallbackStarters[0]
        let model = viewModel()
        model.startConversation(about: starter)
        try? await Task.sleep(for: .milliseconds(300))

        for message in model.messages {
            XCTAssertFalse(message.content.contains(starter.seed),
                           "the model-facing seed reached the transcript")
        }
    }

    /// Guard the shape of the content itself: a card face is a topic, so it
    /// should not be written as the person speaking.
    func test_cardFaces_areNotFirstPerson() {
        for starter in ChatSuggestion.fallbackStarters + ChatSuggestion.previewSamples {
            let lower = starter.label.lowercased()
            for opening in ["i ", "i'", "my ", "me "] {
                XCTAssertFalse(lower.hasPrefix(opening),
                               "card face is written as the person speaking: \(starter.label)")
            }
        }
    }

    /// And a starter only opens a conversation that has not started.
    func test_starterIsIgnoredOnceTheConversationHasBegun() async {
        let model = viewModel()
        model.sendMessage(prompt: "I had a hard week")
        try? await Task.sleep(for: .milliseconds(300))
        let before = model.messages.count

        model.startConversation(about: ChatSuggestion.fallbackStarters[0])
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(model.messages.count, before,
                       "a starter opened over an existing conversation")
    }

    // MARK: - Analysis cards

    /// The bubble the person asked for — and the reason it cannot be a user
    /// turn. `isStarterPrompt` renders like one without being one.
    func test_tappingAnAnalysisCard_showsThePromptWithoutAUserTurn() async {
        let model = viewModel()
        model.startConversation(about: analysisCard)
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(
            model.messages.allSatisfy { !$0.isFromUser },
            "an analysis card wrote a turn as the person: "
                + model.messages.filter(\.isFromUser).map(\.content).joined(separator: " | ")
        )
        XCTAssertEqual(
            model.messages.filter(\.isStarterPrompt).map(\.content),
            ["What keeps coming up when I write about work?"],
            "the question that started the conversation is not in the transcript"
        )
    }

    /// The seed reads like an instruction to the model. It is not what the
    /// person sees, on either kind of card.
    func test_analysisSeedIsNeverShownOnScreen() async {
        let card = analysisCard
        let model = viewModel()
        model.startConversation(about: card)
        try? await Task.sleep(for: .milliseconds(300))

        for message in model.messages {
            XCTAssertFalse(message.content.contains(card.seed),
                           "the model-facing seed reached the transcript")
        }
    }

    /// The whole reason the starter is not a user turn: this transcript
    /// becomes a journal entry, and the person did not write the question.
    func test_summaryNeverCarriesTheStarterPrompt() {
        let prompt = "What keeps coming up when I write about work?"
        let messages = [
            ChatMessage.starterPrompt(text: prompt),
            ChatMessage.aiMessage(body: "Work shows up mostly late at night."),
            ChatMessage(content: "that tracks", isFromUser: true)
        ]

        let turns = ChatService.summaryTurns(from: messages)

        XCTAssertFalse(turns.contains { $0.text == prompt },
                       "the starter question reached the journal summariser")
        XCTAssertEqual(turns.map(\.role), [.assistant, .user],
                       "dropping the starter must not disturb the other turns")
    }
}
