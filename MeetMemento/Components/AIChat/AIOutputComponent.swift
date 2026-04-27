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
    var onCitationsTapped: (() -> Void)?
    var onRedo: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    @State private var displayedHeading1 = ""
    @State private var displayedHeading2 = ""
    @State private var displayedBody = ""
    @State private var showCitation = false
    @State private var isAnimating = false
    @State private var hasAnimated = false
    @State private var animationTask: Task<Void, Never>?

    // Fast typing speed like ChatGPT (characters per second)
    private let charactersPerSecond: Double = 120

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
        onCitationsTapped: (() -> Void)? = nil,
        onRedo: (() -> Void)? = nil
    ) {
        self.content = content
        self.animate = animate
        self.onCitationsTapped = onCitationsTapped
        self.onRedo = onRedo
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
        
            // Citation link: appears first with a quick, sudden appearance
            if let citations = content.citations, !citations.isEmpty {
                CitationLink(count: citations.count, onTap: onCitationsTapped)
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

            // Body text with typewriter effect
            if !displayedBody.isEmpty || !animate {
                Text(LocalizedStringKey(animate ? displayedBody : content.body))
                    .font(type.body1)
                    .foregroundStyle(GrayScale.gray800)
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.mutedForeground)
                }
                .accessibilityLabel("Copy")

                Button {
                    print("Thumbs up")
                } label: {
                    Image(systemName: "hand.thumbsup")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.mutedForeground)
                }
                .accessibilityLabel("Thumbs up")

                Button {
                    print("Thumbs down")
                } label: {
                    Image(systemName: "hand.thumbsdown")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.mutedForeground)
                }
                .accessibilityLabel("Thumbs down")

                Button {
                    onRedo?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
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
        .onAppear {
            if animate && !hasAnimated {
                startTypewriterSequence()
            } else if !animate {
                showAllContent()
            }
        }
        .onChange(of: contentIdentity) { _, _ in
            if animate {
                resetAnimation()
                startTypewriterSequence()
            } else {
                showAllContent()
            }
        }
    }

    // MARK: - Animation Helpers

    private func showAllContent() {
        displayedHeading1 = content.heading1 ?? ""
        displayedHeading2 = content.heading2 ?? ""
        displayedBody = content.body
        showCitation = true
        hasAnimated = true
    }

    private func resetAnimation() {
        animationTask?.cancel()
        animationTask = nil
        displayedHeading1 = ""
        displayedHeading2 = ""
        displayedBody = ""
        showCitation = false
        hasAnimated = false
        isAnimating = false
    }

    // MARK: - Typewriter Animation Sequence

    private func startTypewriterSequence() {
        animationTask?.cancel()
        guard !isAnimating else { return }
        isAnimating = true

        // Citation appears first, quick and sudden
        if content.citations != nil, !(content.citations?.isEmpty ?? true) {
            showCitation = true
        }

        animationTask = Task { @MainActor in
            let interval: UInt64 = UInt64(1_000_000_000 / charactersPerSecond)

            // Phase 1: Heading 1
            if let heading1 = content.heading1, !heading1.isEmpty {
                for character in heading1 {
                    guard !Task.isCancelled else { return }
                    displayedHeading1.append(character)
                    try? await Task.sleep(nanoseconds: interval)
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms pause between sections
            }

            // Phase 2: Heading 2
            if let heading2 = content.heading2, !heading2.isEmpty {
                for character in heading2 {
                    guard !Task.isCancelled else { return }
                    displayedHeading2.append(character)
                    try? await Task.sleep(nanoseconds: interval)
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms pause between sections
            }

            // Phase 3: Body
            for character in content.body {
                guard !Task.isCancelled else { return }
                displayedBody.append(character)
                try? await Task.sleep(nanoseconds: interval)
            }

            guard !Task.isCancelled else { return }
            isAnimating = false
            hasAnimated = true
        }
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
            print("Citations tapped")
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
