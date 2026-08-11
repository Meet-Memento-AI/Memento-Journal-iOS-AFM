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
    /// True while the reply is still streaming in. Nothing that implies "the
    /// answer is finished" — the action bar above all — may show until this is
    /// false, otherwise copy/redo appear over a half-written reply.
    var isStreaming: Bool
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

    // Typewriter state. Rather than appending to per-field strings (which the old
    // typewriter reset to "" on every delta, so it stuttered on a live stream), we
    // keep ONE monotonic character index and derive each shown substring from it.
    // The index rides the growing cumulative body — it never resets on a delta — so
    // the reply flows in one smooth ChatGPT-style stream.
    @State private var displayedCount = 0
    // Latest targets, mirrored from `content`/`isStreaming` into @State so the
    // long-lived drain Task reads live values (a captured view struct would be
    // stale). The single index spans, in order, [tHeading1 | tHeading2 | tBody].
    @State private var tHeading1 = ""
    @State private var tHeading2 = ""
    @State private var tBody = ""
    @State private var streamingState = false
    @State private var showCitation = false
    @State private var hasAnimated = false
    @State private var didComplete = false
    @State private var drainTask: Task<Void, Never>?

    /// Baseline tick (~14ms ≈ 70/s). With the adaptive step this gives a calm
    /// ~1-char trickle when caught up and a fast drain of any backlog, so the
    /// reveal never lags the model yet still reads as typing.
    private let baseTickNanos: UInt64 = 14_000_000

    /// Soft leading-edge dissolve (ChatGPT-style): the newest `dissolveRamp`
    /// characters ramp from `dissolveMinOpacity` up to full opacity, so streamed
    /// text melts in instead of snapping on. Redrawn each tick as the index
    /// advances, so the ramp glides forward and every character fades up over
    /// roughly `dissolveRamp` ticks (~200ms) — the "incredibly smooth" feel.
    private let dissolveRamp = 14
    private let dissolveMinOpacity: Double = 0.1

    /// Stable value that changes when content changes; used with onChange to avoid relying on AIOutputContent Equatable synthesis.
    private var contentIdentity: String {
        [
            content.heading1 ?? "",
            content.heading2 ?? "",
            content.body,
            String(content.citations?.count ?? 0),
            // The final `.delta` and the `.final` event carry byte-identical body
            // text for a citation-less reply, so without this the `isStreaming`
            // flip alone wouldn't re-trigger `syncTargets` and the typewriter
            // would idle forever (caret blinking, action bar never shown).
            isStreaming ? "streaming" : "done"
        ].joined(separator: "\u{0}")
    }

    public init(
        content: AIOutputContent,
        animate: Bool = true,
        isStreaming: Bool = false,
        feedbackType: FeedbackType? = nil,
        onCitationsTapped: (() -> Void)? = nil,
        onRedo: (() -> Void)? = nil,
        onThumbsUp: (() -> Void)? = nil,
        onThumbsDown: (() -> Void)? = nil,
        onAnimationComplete: (() -> Void)? = nil
    ) {
        self.content = content
        self.animate = animate
        self.isStreaming = isStreaming
        self.feedbackType = feedbackType
        self.onCitationsTapped = onCitationsTapped
        self.onRedo = onRedo
        self.onThumbsUp = onThumbsUp
        self.onThumbsDown = onThumbsDown
        self.onAnimationComplete = onAnimationComplete
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
    }

    /// Copy / thumbs / redo only make sense against a finished reply. Gated on
    /// both conditions: `hasRenderableContent` keeps it off the empty
    /// pre-stream placeholder, `!isStreaming` keeps it off a half-written one.
    private var showsActionBar: Bool { hasRenderableContent && !isStreaming }

    /// Full text for copy (heading1 + heading2 + body).
    private var fullTextForCopy: String {
        [content.heading1, content.heading2, content.body]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    // MARK: - Typewriter-derived substrings

    /// Total characters across the three fields; the index climbs toward this.
    private var totalCount: Int { tHeading1.count + tHeading2.count + tBody.count }

    /// The three fields sliced by the single `displayedCount`, in order. Because
    /// the `@Generable` fields fill in declaration order (h1 → h2 → body), typing
    /// only up to what's currently available means an early snapshot (heading
    /// present, body empty) types the heading, then continues seamlessly into the
    /// body as it arrives — no gap, no pop-in.
    private var shownHeading1: String { String(tHeading1.prefix(displayedCount)) }
    private var shownHeading2: String {
        String(tHeading2.prefix(max(0, displayedCount - tHeading1.count)))
    }
    private var shownBody: String {
        String(tBody.prefix(max(0, displayedCount - tHeading1.count - tHeading2.count)))
    }

    /// Still revealing characters (or the stream is live): show a trailing caret.
    private var isTyping: Bool { animate && (displayedCount < totalCount || streamingState) }

    /// Actively revealing backlog — apply the leading-edge dissolve. When caught
    /// up (a pause, or the end) text sits solid, matching ChatGPT.
    private var isDissolving: Bool { animate && displayedCount < totalCount }

    /// Whether to show the subtle caret: only while caught up but still streaming
    /// — a "still generating" hint during a pause. While text is actively
    /// dissolving in, the fading leading edge is the cue, so no caret (a
    /// full-opacity caret beside faded text looks disconnected).
    private var showsCaret: Bool {
        animate && streamingState && displayedCount >= totalCount && !shownBody.isEmpty
    }

    /// The body as a `Text` with the ChatGPT dissolve applied. Parses the shown
    /// prefix (markdown / RAG styling preserved), fades the newest `dissolveRamp`
    /// characters from faint to full so the leading edge melts in, and folds the
    /// caret into the same `AttributedString` (no deprecated `Text` concatenation).
    private var bodyText: Text {
        var attr = RichTextParser.parse(
            animate ? shownBody : content.body,
            baseFont: type.body1,
            boldFont: type.body1Bold,
            textColor: theme.foreground
        )
        if isDissolving {
            let ramp = min(dissolveRamp, attr.characters.count)
            if ramp > 0 {
                var upper = attr.characters.endIndex
                for k in 0..<ramp {
                    let lower = attr.characters.index(before: upper)
                    // k = 0 is the newest (last) character → faintest; opacity
                    // climbs toward 1.0 for characters further from the edge.
                    let t = Double(k + 1) / Double(ramp)
                    let alpha = dissolveMinOpacity + (1 - dissolveMinOpacity) * t
                    attr[lower..<upper].foregroundColor = theme.foreground.opacity(alpha)
                    upper = lower
                }
            }
        }
        if showsCaret {
            var caret = AttributedString("\u{258F}") // ▏
            caret.foregroundColor = theme.mutedForeground
            attr.append(caret)
        }
        return Text(attr)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        
            // Citation link — first element, opens the full list in
            // CitationsBottomSheet. Citations only arrive on the stream's
            // `.final` event (deltas carry body + headings only), so this view
            // is inserted *after* the reply has already laid out at full
            // height. Without a transition that insert snaps in and shoves the
            // answer down mid-read, so animate the insertion itself — opacity
            // alone does nothing for layout.
            if let citations = content.citations, !citations.isEmpty {
                CitationLink(count: citations.count, onTap: onCitationsTapped)
                    .opacity(showCitation ? 1 : 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Heading 1 (if provided)
            if let heading1 = content.heading1, !heading1.isEmpty {
                let shown = animate ? shownHeading1 : heading1
                if !shown.isEmpty {
                    Text(shown)
                        .font(type.h3)
                        .foregroundStyle(theme.foreground)
                        .modifier(type.headingLineSpacingModifier(for: type.size2XL))
                }
            }

            // Heading 2 (if provided)
            if let heading2 = content.heading2, !heading2.isEmpty {
                let shown = animate ? shownHeading2 : heading2
                if !shown.isEmpty {
                    Text(shown)
                        .font(type.h4)
                        .foregroundStyle(theme.foreground)
                        .modifier(type.headingLineSpacingModifier(for: type.sizeXL))
                        .padding(.top, (content.heading1?.isEmpty == false) ? 4 : 0)
                }
            }

            // Body text with the ChatGPT-style typewriter + leading-edge dissolve.
            // `bodyText` parses the shown prefix and fades the newest characters
            // in; the caret only appears during a mid-stream pause.
            let bodyShown = animate ? shownBody : content.body
            if !bodyShown.isEmpty || !animate {
                bodyText
                    .lineSpacing(type.bodyLineSpacing)
            }

            // Action bar (copy, thumbs up, thumbs down, re-do) — appears gently
            // once the reply has actually arrived.
            //
            // Conditional, not merely transparent: at opacity 0 this still
            // reserved ~30pt of layout, which put a blank gap directly above the
            // "Memento is thinking" shimmer for the whole generation.
            if showsActionBar {
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
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { syncTargets() }
        // Each delta grows `content.body`; mirror the new target into @State and
        // let the persistent drain loop chase it. The loop — not this callback —
        // paces the reveal, so text flows smoothly instead of jumping per snapshot.
        .onChange(of: contentIdentity) { _, _ in syncTargets() }
        .onDisappear {
            drainTask?.cancel()
            drainTask = nil
        }
    }

    // MARK: - Typewriter

    /// Copies the latest `content`/`isStreaming` into the @State the drain loop
    /// reads, updates the citation reveal, and ensures the loop is running.
    ///
    /// The "Reviewed your journals" link eases in whenever its presence changes on
    /// a new (animating) message — including the first appear, since grounded turns
    /// now carry the reviewed journals from the first delta, so the link shows
    /// right away with a gentle fade rather than waiting for the reply to finish.
    /// Reloaded history (`!animate`) renders settled, with no fade on scroll.
    private func syncTargets() {
        tHeading1 = content.heading1 ?? ""
        tHeading2 = content.heading2 ?? ""
        tBody = content.body
        streamingState = isStreaming

        let shouldShowCitation = (content.citations?.isEmpty == false)
        if shouldShowCitation != showCitation {
            if animate {
                withAnimation(.easeOut(duration: 0.3)) { showCitation = shouldShowCitation }
            } else {
                showCitation = shouldShowCitation
            }
        }

        guard animate else {
            // Reloaded history / already-seen: no typewriter, show everything.
            displayedCount = totalCount
            hasAnimated = hasRenderableContent
            if !didComplete && hasRenderableContent {
                didComplete = true
                onAnimationComplete?()
            }
            return
        }

        startDrainIfNeeded()
    }

    /// Persistent loop that eases `displayedCount` toward `totalCount`. It reads
    /// only @State (never the captured, stale `content`), rides across deltas
    /// without resetting, and completes only once the stream has ended AND the
    /// buffer is fully drained — so a mid-generation pause can't cut it off.
    private func startDrainIfNeeded() {
        guard animate, drainTask == nil else { return }
        drainTask = Task { @MainActor in
            while !Task.isCancelled {
                // Guard: `strippingReferenceMarkers` can shrink the cleaned body
                // between snapshots, so the target may drop below the index.
                if displayedCount > totalCount { displayedCount = totalCount }

                let remaining = totalCount - displayedCount
                if remaining > 0 {
                    // Ease toward the target: a large backlog drains fast (never
                    // lag the model), a trickle reveals ~1 char/tick (typing feel).
                    let step = max(1, remaining / 8)
                    displayedCount = min(totalCount, displayedCount + step)
                    try? await Task.sleep(nanoseconds: baseTickNanos)
                } else if streamingState {
                    // Caught up but more tokens may still come: idle, don't finish.
                    try? await Task.sleep(nanoseconds: baseTickNanos)
                } else {
                    // Stream ended and fully typed out.
                    hasAnimated = hasRenderableContent
                    if !didComplete && hasRenderableContent {
                        didComplete = true
                        onAnimationComplete?()
                    }
                    break
                }
            }
            drainTask = nil
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
