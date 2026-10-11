//
//  AIOutputComponent.swift
//  withMemento
//
//  AI output component with markdown support, headings, and citation links
//

import SwiftUI

/// Structured AI output content
public struct AIOutputContent: Hashable, Codable {
    public let heading1: String?
    public let heading2: String?
    public let body: String
    public let citations: [JournalCitation]?
    public let facts: [InsightFact]?

    enum CodingKeys: String, CodingKey {
        case heading1
        case heading2
        case body
        case citations
        case facts
    }

    public init(
        heading1: String? = nil,
        heading2: String? = nil,
        body: String,
        citations: [JournalCitation]? = nil,
        facts: [InsightFact]? = nil
    ) {
        self.heading1 = heading1
        self.heading2 = heading2
        self.body = body
        self.citations = citations
        self.facts = facts
    }

    /// Sanitizes body text that may contain leaked JSON (e.g. "{body: ...") from malformed AI output.
    /// Ensures production never displays raw JSON to users.
    public static func sanitizeBody(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.contains("body") else { return trimmed }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["body"] as? String else {
            return trimmed
        }
        return body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        heading1 = try container.decodeIfPresent(String.self, forKey: .heading1)
        heading2 = try container.decodeIfPresent(String.self, forKey: .heading2)
        let rawBody = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        body = Self.sanitizeBody(rawBody)
        citations = try container.decodeIfPresent([JournalCitation].self, forKey: .citations)
        facts = try container.decodeIfPresent([InsightFact].self, forKey: .facts)
    }

    /// Facts first, then body — statistic turns have an empty body on purpose.
    public var speakableBody: String {
        let factText = (facts ?? []).map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n\n")
        if body.isEmpty { return factText }
        if factText.isEmpty { return body }
        return factText + "\n\n" + body
    }

    public var plainTextForCopy: String {
        [heading1, heading2, speakableBody]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(heading1, forKey: .heading1)
        try container.encodeIfPresent(heading2, forKey: .heading2)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(citations, forKey: .citations)
        try container.encodeIfPresent(facts, forKey: .facts)
    }
}

public struct AIOutputComponent: View {
    let content: AIOutputContent
    /// False for history: the citation link appears without easing in.
    var animate: Bool
    /// True while the reply is still streaming in **or still revealing on
    /// screen**. Nothing that implies "the answer is finished" — the action
    /// bar above all — may show until this is false, otherwise copy/redo
    /// appear over a half-written reply.
    var isStreaming: Bool
    var feedbackType: FeedbackType?
    /// True while this message is the one VoicePlaybackService is speaking.
    /// Prop-down like `feedbackType` — the component doesn't know its message
    /// ID, so observation happens once in AIChatView, which owns identity.
    var isSpeaking: Bool
    /// True while this message's playback is paused (tap resumes).
    var isPaused: Bool
    var onCitationsTapped: (() -> Void)?
    var onSpeak: (() -> Void)?
    var onRedo: (() -> Void)?
    var onThumbsUp: (() -> Void)?
    var onThumbsDown: (() -> Void)?
    /// Spec 041: overflow Report answer. Nil hides the ellipsis (previews,
    /// surfaces that are not chat).
    var isReported: Bool
    var onReportAnswer: (() -> Void)?
    /// When each character appears (`StreamLayout` order). Nil renders the
    /// reply settled. Lives on the message, so a recycled row resumes
    /// mid-reveal and a settled reply never replays. Set with
    /// `revealing(_:)`; internal because `StreamSchedule` is.
    var schedule: StreamSchedule?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    @State private var showCitation = false

    /// Single-entry memo for `RichTextParser.parseBlocks`. A class (not @State
    /// value) on purpose: mutating a boxed cache during body evaluation
    /// publishes nothing — no re-render loop.
    private final class ParseCache {
        private var text: String?
        private var blocks: [MarkdownBlock] = []

        func parse(_ text: String) -> [MarkdownBlock] {
            if text == self.text { return blocks }
            let parsed = RichTextParser.parseBlocks(text)
            self.text = text
            self.blocks = parsed
            return parsed
        }
    }

    @State private var parseCache = ParseCache()

    public init(
        content: AIOutputContent,
        animate: Bool = true,
        isStreaming: Bool = false,
        feedbackType: FeedbackType? = nil,
        isSpeaking: Bool = false,
        isPaused: Bool = false,
        onCitationsTapped: (() -> Void)? = nil,
        onSpeak: (() -> Void)? = nil,
        onRedo: (() -> Void)? = nil,
        onThumbsUp: (() -> Void)? = nil,
        onThumbsDown: (() -> Void)? = nil,
        isReported: Bool = false,
        onReportAnswer: (() -> Void)? = nil
    ) {
        self.content = content
        self.animate = animate
        self.isStreaming = isStreaming
        self.feedbackType = feedbackType
        self.isSpeaking = isSpeaking
        self.isPaused = isPaused
        self.onCitationsTapped = onCitationsTapped
        self.onSpeak = onSpeak
        self.onRedo = onRedo
        self.onThumbsUp = onThumbsUp
        self.onThumbsDown = onThumbsDown
        self.isReported = isReported
        self.onReportAnswer = onReportAnswer
    }

    /// The same component, revealing its text on `schedule`.
    func revealing(_ schedule: StreamSchedule?) -> AIOutputComponent {
        var copy = self
        copy.schedule = schedule
        return copy
    }

    /// Whether there is anything worth showing chrome for.
    ///
    /// `ChatViewModel.performSend` appends an EMPTY assistant bubble the instant
    /// a prompt is sent, so it can fill in as the model streams. That placeholder
    /// still renders this component, so everything that implies "the reply is
    /// here" — the action bar in particular — must check this first. Citations
    /// are excluded deliberately: they only arrive with the finished reply.
    private var hasRenderableContent: Bool {
        !content.body.isEmpty
            || !(content.heading1 ?? "").isEmpty
            || !(content.heading2 ?? "").isEmpty
            || !(content.facts ?? []).isEmpty
    }

    /// Copy / thumbs / redo only make sense against a finished reply. Gated on
    /// both conditions: `hasRenderableContent` keeps it off the empty
    /// pre-stream placeholder, `!isStreaming` keeps it off a half-written one.
    private var showsActionBar: Bool { hasRenderableContent && !isStreaming }

    /// Full text for copy (headings + Swift facts + body).
    private var fullTextForCopy: String { content.plainTextForCopy }

    /// Body blocks plus where each sits in the schedule. Parsed with every
    /// line closed — the same parse the view model schedules from — so the
    /// indices agree. Snapshots are already cut on word or sentence
    /// boundaries upstream, so a half-typed `###` never reaches here.
    private var streamLayout: StreamLayout {
        StreamLayout(
            blocks: parseCache.parse(content.body),
            heading1: content.heading1,
            heading2: content.heading2
        )
    }

    @ViewBuilder
    private func headingText(_ text: String, start: Int) -> some View {
        if let schedule {
            StreamingText(
                attributed: AttributedString(text),
                schedule: schedule,
                range: start..<(start + text.count)
            )
        } else {
            Text(text)
        }
    }

    public var body: some View {
        let layout = streamLayout
        VStack(alignment: .leading, spacing: 12) {
            // Citation link — first element, opens the full list in
            // CitationsBottomSheet. Grounded turns carry it from the first
            // delta, but `.final` can still add or change it after text is
            // on screen. Without a transition that insert snaps in and shoves
            // the answer down mid-read, so animate the insertion itself —
            // opacity alone does nothing for layout.
            if let facts = content.facts, !facts.isEmpty {
                InsightFactSection(facts: facts, onTap: onCitationsTapped)
                    .accessibilityIdentifier("ask.insightFacts")
            }

            if let citations = content.citations, !citations.isEmpty {
                CitationLink(count: citations.count, onTap: onCitationsTapped)
                    .opacity(showCitation ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Legacy structured headings (Figtree h3/h4 — never Lora h1/h2).
            if let heading1 = content.heading1, !heading1.isEmpty {
                headingText(heading1, start: layout.heading1Start)
                    .font(type.h3)
                    .foregroundStyle(theme.foreground)
                    .modifier(type.headingLineSpacingModifier(for: type.size2XL))
                    .accessibilityAddTraits(.isHeader)
            }

            if let heading2 = content.heading2, !heading2.isEmpty {
                headingText(heading2, start: layout.heading2Start)
                    .font(type.h4)
                    .foregroundStyle(theme.foreground)
                    .modifier(type.headingLineSpacingModifier(for: type.sizeXL))
                    .padding(.top, (content.heading1?.isEmpty == false) ? 4 : 0)
                    .accessibilityAddTraits(.isHeader)
            }

            if !content.body.isEmpty {
                MarkdownBodyView(
                    blocks: layout.blocks,
                    schedule: schedule,
                    blockStarts: layout.blockStarts
                )
            }

            // Action bar (copy, thumbs up, thumbs down, re-do) — eases in once
            // the last glyph of the reply has settled, not when the stream
            // ends.
            //
            // Conditional, not merely transparent: at opacity 0 this still
            // reserved ~30pt of layout, which put a blank gap directly above the
            // "Memento is thinking" shimmer for the whole generation.
            if showsActionBar {
            HStack(spacing: 8) {
                // Read-aloud first: playback is the primary consumption action;
                // copy/feedback are secondary. Real Button (not onTapGesture) —
                // the ScrollView-level dismissKeyboard tap swallows anything else.
                if onSpeak != nil {
                    // Three states, one action each: idle → start, speaking →
                    // pause, paused → resume. No in-app hard stop (user
                    // decision) — playback ends at drain, or implicitly via
                    // dictation/regenerate/another message/lock-screen Stop.
                    let speakIcon = isPaused ? "play.fill"
                        : (isSpeaking ? "pause.fill" : "speaker.wave.2")
                    let speakLabel = isPaused ? "Resume reading aloud"
                        : (isSpeaking ? "Pause reading aloud" : "Read aloud")
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSpeak?()
                    } label: {
                        Image(systemName: speakIcon)
                            .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                            .foregroundStyle(isSpeaking || isPaused ? theme.accent : theme.iconForeground)
                            .animation(.easeOut(duration: 0.2), value: isSpeaking)
                            .animation(.easeOut(duration: 0.2), value: isPaused)
                    }
                    .accessibilityLabel(speakLabel)
                }

                Button {
                    let text = fullTextForCopy
                    guard !text.isEmpty else { return }
                    UIPasteboard.general.string = text
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                        .foregroundStyle(theme.iconForeground)
                }
                .accessibilityLabel("Copy")

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onThumbsUp?()
                } label: {
                    Image(systemName: feedbackType == .positive ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                        .foregroundStyle(feedbackType == .positive ? theme.accent : theme.iconForeground)
                        .animation(.easeOut(duration: 0.2), value: feedbackType)
                }
                .accessibilityLabel(feedbackType == .positive ? "Remove thumbs up" : "Thumbs up")
                .accessibilityIdentifier("chat.reply.thumbsUp")

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onThumbsDown?()
                } label: {
                    Image(systemName: feedbackType == .negative ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                        .foregroundStyle(feedbackType == .negative ? theme.destructive : theme.iconForeground)
                        .animation(.easeOut(duration: 0.2), value: feedbackType)
                }
                .accessibilityLabel(feedbackType == .negative ? "Remove thumbs down" : "Thumbs down")
                .accessibilityIdentifier("chat.reply.thumbsDown")

                // Conditional like read-aloud above: narration mode passes nil
                // (regenerating mid-voice-loop would fight the TTS chunker, and
                // its Figma action bar omits the affordance); chat always passes
                // a handler, so the chat page is unchanged.
                if onRedo != nil {
                    Button {
                        onRedo?()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                            .foregroundStyle(theme.iconForeground)
                    }
                    .accessibilityLabel("Regenerate")
                }

                if let onReportAnswer {
                    ReplyOverflowMenu(isReported: isReported, onReportAnswer: onReportAnswer)
                }
            }
            .padding(.top, 8)
            .transition(.opacity)
            }
        }
        .animation(animate ? .easeOut(duration: 0.28) : nil, value: showsActionBar)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { syncCitation() }
        .onChange(of: content.citations?.count ?? 0) { _, _ in syncCitation() }
    }
}

// MARK: - Citation reveal

extension AIOutputComponent {

    /// The "Reviewed your journals" link eases in whenever its presence changes
    /// on a new (animating) message — including the first appear, since
    /// grounded turns carry the reviewed journals from the first delta.
    /// Reloaded history (`!animate`) renders settled, with no fade on scroll.
    private func syncCitation() {
        let shouldShowCitation = (content.citations?.isEmpty == false)
        guard shouldShowCitation != showCitation else { return }
        if animate {
            withAnimation(.easeOut(duration: 0.3)) { showCitation = shouldShowCitation }
        } else {
            showCitation = shouldShowCitation
        }
    }
}

/// Stat card for 045 R5 quantitative Ask. `n` is always visible.
private struct InsightFactSection: View {
    let facts: [InsightFact]
    var onTap: (() -> Void)?
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(fact.label.capitalized)
                        .font(type.captionMedium)
                        .foregroundStyle(theme.mutedForeground)
                    Text(fact.value)
                        .font(type.h3)
                        .foregroundStyle(theme.foreground)
                    Text("n = \(fact.n)")
                        .font(type.caption)
                        .foregroundStyle(theme.mutedForeground)
                    if fact.isLowConfidence {
                        Text(InsightFact.lowConfidenceCopy(n: fact.n))
                            .font(type.caption)
                            .foregroundStyle(theme.mutedForeground)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(fact.isLowConfidence ? 0.55 : 1)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !fact.supportingEntryIDs.isEmpty {
                        onTap?()
                    }
                }
                .accessibilityAddTraits(fact.supportingEntryIDs.isEmpty ? [] : .isButton)
            }
        }
        .padding(16)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Previews

#Preview("AI Output with Headings and Citations") {
    AIOutputComponent(
        content: AIOutputContent(
            heading1: "Understanding Your Patterns",
            heading2: "Key Insights",
            body: """
            You asked how work has been landing.

            ### 12 March
            *I left the office with my jaw still tight.*
            That walk is the part you stayed with — not the meeting, the leaving.

            - 12 March — the long walk home
            - 4 April — Sunday dread
            """,
            citations: [
                JournalCitation(
                    entryId: UUID(),
                    entryTitle: "Morning Thoughts",
                    entryDate: Date(),
                    excerpt: "Work has been stressful this week..."
                )
            ]
        ),
        onCitationsTapped: {
            AppLogger.log("Citations tapped")
        }
    )
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("AI Output with Body Only") {
    AIOutputComponent(
        content: AIOutputContent(
            body: "This is a simple response with **bold text** and *italic text*. You can include `code snippets` and [links](https://example.com)."
        )
    )
    .padding()
    .useTheme()
    .useTypography()
}
