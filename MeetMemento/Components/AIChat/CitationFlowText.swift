//
//  CitationFlowText.swift
//  MeetMemento
//
//  Flow layout renderer for mixed text and citation badge content
//

import SwiftUI

/// Flow layout for rendering text with inline citation badges
/// Splits text into words and renders badges inline
struct CitationFlowText: View {
    let segments: [ParsedTextSegment]
    let baseFont: Font
    let boldFont: Font
    let textColor: Color
    let onCitationTap: (CitationPopoverData) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        CitationFlowLayout(hSpacing: 0, vSpacing: 4) {
            ForEach(Array(flattenedElements.enumerated()), id: \.offset) { _, element in
                renderElement(element)
            }
        }
    }

    // MARK: - Element Types

    private enum FlowElement: Identifiable {
        case word(String, isBold: Bool)
        case citation(index: Int, date: Date, excerpt: String, entryId: UUID)
        case lineBreak

        var id: String {
            switch self {
            case .word(let str, let isBold):
                return "word-\(str)-\(isBold)-\(UUID().uuidString)"
            case .citation(let index, _, _, let entryId):
                return "citation-\(index)-\(entryId.uuidString)"
            case .lineBreak:
                return "linebreak-\(UUID().uuidString)"
            }
        }
    }

    // MARK: - Flatten Segments to Elements

    private var flattenedElements: [FlowElement] {
        var elements: [FlowElement] = []

        for segment in segments {
            switch segment {
            case .text(let text):
                elements.append(contentsOf: parseTextToElements(text))
            case .citation(let index, let date, let excerpt, let entryId):
                elements.append(.citation(index: index, date: date, excerpt: excerpt, entryId: entryId))
            }
        }

        return elements
    }

    /// Parse text into word elements, handling bold markers and newlines
    private func parseTextToElements(_ text: String) -> [FlowElement] {
        var elements: [FlowElement] = []

        // Split by lines first
        let lines = text.components(separatedBy: "\n")

        for (lineIndex, line) in lines.enumerated() {
            // Parse bold markers within the line
            let lineElements = parseLineWithBold(line)
            elements.append(contentsOf: lineElements)

            // Add line break between lines (not after the last line)
            if lineIndex < lines.count - 1 {
                elements.append(.lineBreak)
            }
        }

        return elements
    }

    /// Parse a single line for **bold** markers and split into words
    private func parseLineWithBold(_ text: String) -> [FlowElement] {
        var elements: [FlowElement] = []

        // Pattern to find **bold** text
        let pattern = #"\*\*([^*]+)\*\*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // Fallback: split into words
            return splitIntoWords(text, isBold: false)
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)

        var lastEnd = 0

        for match in matches {
            // Add text before this bold segment
            if match.range.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let beforeText = nsText.substring(with: beforeRange)
                elements.append(contentsOf: splitIntoWords(beforeText, isBold: false))
            }

            // Add the bold text (without the ** markers)
            if match.numberOfRanges >= 2 {
                let innerRange = match.range(at: 1)
                let innerText = nsText.substring(with: innerRange)
                elements.append(contentsOf: splitIntoWords(innerText, isBold: true))
            }

            lastEnd = match.range.location + match.range.length
        }

        // Add remaining text
        if lastEnd < nsText.length {
            let afterText = nsText.substring(from: lastEnd)
            elements.append(contentsOf: splitIntoWords(afterText, isBold: false))
        }

        return elements
    }

    /// Split text into word elements, preserving spaces
    private func splitIntoWords(_ text: String, isBold: Bool) -> [FlowElement] {
        // Split by spaces but keep the spacing context
        let words = text.components(separatedBy: " ")
        var elements: [FlowElement] = []

        for (index, word) in words.enumerated() {
            if !word.isEmpty {
                // Add trailing space to all words except the last
                let wordWithSpace = index < words.count - 1 ? word + " " : word
                elements.append(.word(wordWithSpace, isBold: isBold))
            } else if index < words.count - 1 {
                // Empty word means consecutive spaces - add a space
                elements.append(.word(" ", isBold: false))
            }
        }

        return elements
    }

    // MARK: - Render Element

    @ViewBuilder
    private func renderElement(_ element: FlowElement) -> some View {
        switch element {
        case .word(let text, let isBold):
            Text(text)
                .font(isBold ? boldFont : baseFont)
                .foregroundStyle(textColor)

        case .citation(let index, let date, let excerpt, let entryId):
            InlineCitationDateBadge(date: date) {
                onCitationTap(CitationPopoverData(
                    index: index,
                    date: date,
                    excerpt: excerpt,
                    entryId: entryId
                ))
            }

        case .lineBreak:
            // Full-width spacer to force line break
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 1, maxHeight: 1)
        }
    }
}

// MARK: - Citation Flow Layout

/// Custom layout for inline flow of text and badges
struct CitationFlowLayout<Content: View>: View {
    let hSpacing: CGFloat
    let vSpacing: CGFloat
    @ViewBuilder var content: Content

    init(hSpacing: CGFloat = 0, vSpacing: CGFloat = 4, @ViewBuilder content: () -> Content) {
        self.hSpacing = hSpacing
        self.vSpacing = vSpacing
        self.content = content()
    }

    var body: some View {
        _CitationFlowLayout(hSpacing: hSpacing, vSpacing: vSpacing) {
            content
        }
    }

    private struct _CitationFlowLayout: Layout {
        let hSpacing: CGFloat
        let vSpacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let maxWidth = proposal.width ?? .infinity
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                // Check if this is a line break (full width element)
                if size.width > maxWidth * 0.9 && size.height <= 1 {
                    // Line break - move to next line
                    x = 0
                    y += rowHeight + vSpacing
                    rowHeight = 0
                    continue
                }

                if x > 0 && x + size.width > maxWidth {
                    // Wrap to next line
                    x = 0
                    y += rowHeight + vSpacing
                    rowHeight = 0
                }

                rowHeight = max(rowHeight, size.height)
                x += size.width + hSpacing
            }

            return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let maxWidth = bounds.width
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                // Check if this is a line break
                if size.width > maxWidth * 0.9 && size.height <= 1 {
                    x = 0
                    y += rowHeight + vSpacing
                    rowHeight = 0
                    continue
                }

                if x > 0 && x + size.width > maxWidth {
                    // Wrap
                    x = 0
                    y += rowHeight + vSpacing
                    rowHeight = 0
                }

                let origin = CGPoint(x: bounds.minX + x, y: bounds.minY + y)
                subview.place(at: origin, proposal: ProposedViewSize(width: size.width, height: size.height))

                rowHeight = max(rowHeight, size.height)
                x += size.width + hSpacing
            }
        }
    }
}

// MARK: - Previews

#Preview("Citation Flow Text") {
    let segments: [ParsedTextSegment] = [
        .text("Based on your entries, I noticed you've been feeling stressed about "),
        .citation(index: 1, date: Date(), excerpt: "Work has been overwhelming lately with all the deadlines.", entryId: UUID()),
        .text(" and also mentioned taking some time for "),
        .citation(index: 2, date: Calendar.current.date(byAdding: .day, value: -3, to: Date())!, excerpt: "Went for a long walk in the park today.", entryId: UUID()),
        .text(". These are **positive steps** toward better balance.")
    ]

    CitationFlowText(
        segments: segments,
        baseFont: Typography().body1,
        boldFont: Typography().body1Bold,
        textColor: GrayScale.gray800
    ) { data in
        print("Tapped citation \(data.index)")
    }
    .padding()
    .useTheme()
    .useTypography()
}
