//
//  AIOutputComponent.swift
//  MeetMemento
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

    enum CodingKeys: String, CodingKey {
        case heading1
        case heading2
        case body
        case citations
    }

    public init(
        heading1: String? = nil,
        heading2: String? = nil,
        body: String,
        citations: [JournalCitation]? = nil
    ) {
        self.heading1 = heading1
        self.heading2 = heading2
        self.body = body
        self.citations = citations
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
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(heading1, forKey: .heading1)
        try container.encodeIfPresent(heading2, forKey: .heading2)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(citations, forKey: .citations)
    }
}

public struct AIOutputComponent: View {
    let content: AIOutputContent
    var animate: Bool
    var feedbackType: FeedbackType?
    var onCitationsTapped: (() -> Void)?
    var onRedo: (() -> Void)?
    var onThumbsUp: (() -> Void)?
    var onThumbsDown: (() -> Void)?
    /// Called once when the typewriter finishes. Lets the owner mark the message
    /// "seen" so a LazyVStack recycle (scroll / keyboard / re-render) doesn't
    /// replay the whole reply — the fix for a reply appearing to repeat.
    var onAnimationComplete: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    @State private var displayedHeading1 = ""
    @State private var displayedHeading2 = ""
    @State private var displayedBody = ""
    @State private var showCitation = false
    @State private var hasAnimated = false

    /// Stable value that changes when content changes; used with onChange to avoid relying on AIOutputContent Equatable synthesis.
    private var contentIdentity: String {
        [
            content.heading1 ?? "",
            content.heading2 ?? "",
            content.body,
            String(content.citations?.count ?? 0)
        ].joined(separator: "\u{0}")
    }

    public init(
        content: AIOutputContent,
        animate: Bool = true,
        feedbackType: FeedbackType? = nil,
        onCitationsTapped: (() -> Void)? = nil,
        onRedo: (() -> Void)? = nil,
        onThumbsUp: (() -> Void)? = nil,
        onThumbsDown: (() -> Void)? = nil,
        onAnimationComplete: (() -> Void)? = nil
    ) {
        self.content = content
        self.animate = animate
        self.feedbackType = feedbackType
        self.onCitationsTapped = onCitationsTapped
        self.onRedo = onRedo
        self.onThumbsUp = onThumbsUp
        self.onThumbsDown = onThumbsDown
        self.onAnimationComplete = onAnimationComplete
    }

    /// Full text for copy (heading1 + heading2 + body).
    private var fullTextForCopy: String {
        [content.heading1, content.heading2, content.body]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        
            // The journals this answer used, listed above the reply. Replaces
            // the inline "[ref N]" markers the model used to write into prose —
            // see ReviewedJournalsList. Still the first element, and still a
            // quick, sudden appearance ahead of the body typewriter.
            if let citations = content.citations, !citations.isEmpty {
                ReviewedJournalsList(citations: citations, onTap: onCitationsTapped)
                    .opacity(showCitation ? 1 : 0)
                    .animation(.easeOut(duration: 0.12), value: showCitation)
            }
            
            // Heading 1 (if provided)
            if let heading1 = content.heading1, !heading1.isEmpty {
                if !displayedHeading1.isEmpty || !animate {
                    Text(animate ? displayedHeading1 : heading1)
                        .font(type.h3)
                        .foregroundStyle(theme.foreground)
                        .modifier(type.headingLineSpacingModifier(for: type.size2XL))
                }
            }

            // Heading 2 (if provided)
            if let heading2 = content.heading2, !heading2.isEmpty {
                if !displayedHeading2.isEmpty || !animate {
                    Text(animate ? displayedHeading2 : heading2)
                        .font(type.h4)
                        .foregroundStyle(theme.foreground)
                        .modifier(type.headingLineSpacingModifier(for: type.sizeXL))
                        .padding(.top, (content.heading1?.isEmpty == false) ? 4 : 0)
                }
            }

            // Body text with typewriter effect and rich text parsing
            if !displayedBody.isEmpty || !animate {
                // Keep local rich-text parsing (RAG citations/markdown); adopt
                // upstream's semantic token for proper light/dark contrast.
                Text(RichTextParser.parse(
                    animate ? displayedBody : content.body,
                    baseFont: type.body1,
                    boldFont: type.body1Bold,
                    textColor: theme.foreground
                ))
                .lineSpacing(type.bodyLineSpacing)
            }

            // Action bar (copy, thumbs up, thumbs down, re-do) — appears gently after message has finished loading
            HStack(spacing: 8) {
                Button {
                    let text = fullTextForCopy
                    guard !text.isEmpty else { return }
                    UIPasteboard.general.string = text
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                        .foregroundStyle(theme.mutedForeground)
                }
                .accessibilityLabel("Copy")

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onThumbsUp?()
                } label: {
                    Image(systemName: feedbackType == .positive ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                        .foregroundStyle(feedbackType == .positive ? theme.primary : theme.mutedForeground)
                        .animation(.easeOut(duration: 0.2), value: feedbackType)
                }
                .accessibilityLabel(feedbackType == .positive ? "Remove thumbs up" : "Thumbs up")

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onThumbsDown?()
                } label: {
                    Image(systemName: feedbackType == .negative ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                        .foregroundStyle(feedbackType == .negative ? theme.destructive : theme.mutedForeground)
                        .animation(.easeOut(duration: 0.2), value: feedbackType)
                }
                .accessibilityLabel(feedbackType == .negative ? "Remove thumbs down" : "Thumbs down")

                Button {
                    onRedo?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                        .foregroundStyle(theme.mutedForeground)
                }
                .accessibilityLabel("Regenerate")
            }
            .padding(.top, 8)
            .opacity(hasAnimated || !animate ? 1 : 0)
            .animation(.easeOut(duration: 0.28), value: hasAnimated)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { revealContent(markComplete: animate) }
        // Streaming: `content.body` grows as the model produces tokens; each
        // update re-renders immediately (no artificial per-character delay), so
        // text appears at the model's real cadence. Non-streamed messages (e.g.
        // reloaded history) render whole on first appear.
        .onChange(of: contentIdentity) { _, _ in revealContent(markComplete: false) }
    }

    // MARK: - Reveal

    /// Show whatever `content` currently holds, immediately. During streaming
    /// this is called repeatedly as the body grows; `markComplete` fires the
    /// seen-callback exactly once on first appear so a finished reply isn't
    /// re-revealed when the row is recycled.
    private func revealContent(markComplete: Bool) {
        displayedHeading1 = content.heading1 ?? ""
        displayedHeading2 = content.heading2 ?? ""
        displayedBody = content.body
        showCitation = (content.citations?.isEmpty == false)
        hasAnimated = true
        if markComplete { onAnimationComplete?() }
    }
}

// MARK: - Previews

#Preview("AI Output with Headings and Citations") {
    AIOutputComponent(
        content: AIOutputContent(
            heading1: "Understanding Your Patterns",
            heading2: "Key Insights",
            body: "Based on your journal entries, I've noticed several patterns. **Work-related stress** appears frequently, especially around deadlines. You've also mentioned *feeling more balanced* after taking walks.",
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
