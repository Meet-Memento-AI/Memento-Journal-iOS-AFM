//
//  RichTextParser.swift
//  MeetMemento
//
//  Parses assistant chat markdown into a block AST (ask@11): ATX headings
//  (###–######; leaked # / ## demoted to h3), paragraphs, ordered and
//  unordered lists, plus **bold** / *italic* / `code` inlines. Citations stay
//  UI chips — `[1]` is plain text, not a markdown link.
//
//  Line-scoped so a streaming splice of (closed prefix through last newline)
//  + (trailing open line) equals a full parse of the shown prefix.
//

import SwiftUI

// MARK: - Parsed Text Segment (citations)

/// Represents a segment of parsed text - either plain text or a citation marker
enum ParsedTextSegment: Identifiable {
    case text(String)
    case citation(index: Int, date: Date, excerpt: String, entryId: UUID)

    var id: String {
        switch self {
        case .text(let str):
            return "text-\(str.hashValue)"
        case .citation(let index, _, _, let entryId):
            return "citation-\(index)-\(entryId.uuidString)"
        }
    }
}

// MARK: - Markdown AST

enum MarkdownInline: Equatable {
    case plain(String)
    case bold(String)
    case italic(String)
    case code(String)

    var text: String {
        switch self {
        case .plain(let t), .bold(let t), .italic(let t), .code(let t):
            return t
        }
    }
}

enum MarkdownBlock: Equatable {
    case heading(level: Int, runs: [MarkdownInline])
    case paragraph(runs: [MarkdownInline])
    case unorderedItem(depth: Int, runs: [MarkdownInline])
    case orderedItem(index: Int, depth: Int, runs: [MarkdownInline])
    case blank

    var isListItem: Bool {
        switch self {
        case .unorderedItem, .orderedItem: return true
        default: return false
        }
    }
}

/// Utility for parsing markdown-like body text into blocks / AttributedString.
/// Supports: ATX headings, paragraphs, `-` / `*` / `+` lists, `1.` lists,
/// **bold**, *italic*, _italic_, and `code`.
struct RichTextParser {

    /// Parses markdown into blocks. When `lastLineClosed` is false, the last
    /// line is forced to a paragraph (markers left in the text) so a half-typed
    /// `###` or `1.` does not flash a heading or list mid-token.
    static func parseBlocks(_ text: String, lastLineClosed: Bool = true) -> [MarkdownBlock] {
        let lines = splitLines(text)
        guard !lines.isEmpty else { return [] }

        var blocks: [MarkdownBlock] = []
        for (index, line) in lines.enumerated() {
            let isLast = index == lines.count - 1
            if isLast && !lastLineClosed {
                if line.isEmpty {
                    blocks.append(.blank)
                } else {
                    blocks.append(.paragraph(runs: parseInlines(line)))
                }
                continue
            }
            blocks.append(parseClosedLine(line))
        }
        return blocks
    }

    /// Flattens blocks to an AttributedString. Headings use `boldFont`; body
    /// and lists use `baseFont`. Prefer `parseBlocks` + `MarkdownBodyView` for
    /// chat rendering (Figtree heading tokens live there).
    static func parse(
        _ text: String,
        baseFont: Font,
        boldFont: Font,
        textColor: Color,
        lastLineClosed: Bool = true
    ) -> AttributedString {
        let blocks = parseBlocks(text, lastLineClosed: lastLineClosed)
        return flatten(
            blocks,
            baseFont: baseFont,
            boldFont: boldFont,
            textColor: textColor
        )
    }

    // MARK: - Citation Parsing

    /// Parses text with inline citations [1], [2] etc. into segments
    /// - Parameters:
    ///   - text: The body text containing [n] citation markers
    ///   - citations: Array of JournalCitation objects (1-indexed: [1] = citations[0])
    /// - Returns: Array of ParsedTextSegment for rendering with inline badges
    static func parseWithCitations(
        _ text: String,
        citations: [JournalCitation]
    ) -> [ParsedTextSegment] {
        let strippedText = stripSourcesSection(text)

        var segments: [ParsedTextSegment] = []

        let pattern = #"\[(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [.text(strippedText)]
        }

        let nsText = strippedText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: strippedText, options: [], range: fullRange)

        var lastEnd = 0

        for match in matches {
            if match.range.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let beforeText = nsText.substring(with: beforeRange)
                if !beforeText.isEmpty {
                    segments.append(.text(beforeText))
                }
            }

            if match.numberOfRanges >= 2 {
                let numberRange = match.range(at: 1)
                let numberString = nsText.substring(with: numberRange)
                if let citationIndex = Int(numberString), citationIndex >= 1, citationIndex <= citations.count {
                    let citation = citations[citationIndex - 1]
                    segments.append(.citation(
                        index: citationIndex,
                        date: citation.entryDate,
                        excerpt: citation.excerpt,
                        entryId: citation.entryId
                    ))
                } else {
                    let markerText = nsText.substring(with: match.range)
                    segments.append(.text(markerText))
                }
            }

            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsText.length {
            let afterText = nsText.substring(from: lastEnd)
            if !afterText.isEmpty {
                segments.append(.text(afterText))
            }
        }

        if segments.isEmpty {
            return [.text(strippedText)]
        }

        return segments
    }

    /// Strips the "**Sources:**" section from the end of the text.
    /// Internal (not private): `SpeechTextSanitizer` reuses it so spoken text
    /// and rendered text agree on what a Sources block is.
    static func stripSourcesSection(_ text: String) -> String {
        let patterns = [
            #"\n\n\*\*Sources:\*\*[\s\S]*$"#,
            #"\n\n\*\*Sources\*\*:[\s\S]*$"#,
            #"\n\nSources:[\s\S]*$"#
        ]

        var result = text
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: (result as NSString).length)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Legacy parse method that accepts citation parameters (ignored)
    @available(*, deprecated, message: "Citation refs are no longer used. Use parse(_:baseFont:boldFont:textColor:) instead.")
    static func parse(
        _ text: String,
        validCitationRefs: Set<Int>,
        baseFont: Font,
        boldFont: Font,
        citationFont: Font,
        textColor: Color,
        citationColor: Color
    ) -> AttributedString {
        return parse(text, baseFont: baseFont, boldFont: boldFont, textColor: textColor)
    }

    // MARK: - Line split

    /// Splits on `\n` and drops the empty trailing element that Swift adds when
    /// the string ends in a newline, so `"foo\n"` is one closed line.
    static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") {
            lines.removeLast()
        }
        return lines
    }

    // MARK: - Closed-line parse

    private static func parseClosedLine(_ line: String) -> MarkdownBlock {
        if line.isEmpty { return .blank }

        let indent = leadingSpaceCount(line)
        // Nested lists deeper than one indent level stay plain (v1).
        if indent >= 4 {
            return .paragraph(runs: parseInlines(line))
        }
        let depth = indent >= 2 ? 1 : 0
        let trimmed = String(line.dropFirst(indent))

        if let heading = parseHeading(trimmed) {
            return heading
        }
        if let unordered = parseUnordered(trimmed, depth: depth) {
            return unordered
        }
        if let ordered = parseOrdered(trimmed, depth: depth) {
            return ordered
        }
        return .paragraph(runs: parseInlines(line))
    }

    /// ATX `#{1,6}` plus space. `#` / `##` demote to level 3 so chat never
    /// asks for Lora display sizes.
    private static func parseHeading(_ trimmed: String) -> MarkdownBlock? {
        guard let regex = headingRegex else { return nil }
        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges >= 3 else {
            return nil
        }
        let hashes = ns.substring(with: match.range(at: 1))
        let content = ns.substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespaces)
        let rawLevel = hashes.count
        let level = min(6, max(3, rawLevel))
        return .heading(level: level, runs: parseInlines(content))
    }

    private static func parseUnordered(_ trimmed: String, depth: Int) -> MarkdownBlock? {
        guard let regex = unorderedRegex else { return nil }
        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges >= 2 else {
            return nil
        }
        let content = ns.substring(with: match.range(at: 1))
        return .unorderedItem(depth: depth, runs: parseInlines(content))
    }

    private static func parseOrdered(_ trimmed: String, depth: Int) -> MarkdownBlock? {
        guard let regex = orderedRegex else { return nil }
        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges >= 3 else {
            return nil
        }
        let numberString = ns.substring(with: match.range(at: 1))
        let content = ns.substring(with: match.range(at: 2))
        guard let index = Int(numberString) else { return nil }
        return .orderedItem(index: index, depth: depth, runs: parseInlines(content))
    }

    private static func leadingSpaceCount(_ line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 } else { break }
        }
        return count
    }

    // MARK: - Inlines

    static func parseInlines(_ text: String) -> [MarkdownInline] {
        guard !text.isEmpty else { return [] }
        guard let regex = inlineRegex else {
            return [.plain(text)]
        }

        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)

        var runs: [MarkdownInline] = []
        var lastEnd = 0

        for match in matches {
            if match.range.location > lastEnd {
                let before = ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                if !before.isEmpty { runs.append(.plain(before)) }
            }

            let matched = ns.substring(with: match.range)
            if matched.hasPrefix("`") && matched.hasSuffix("`") && matched.count >= 2 {
                let inner = String(matched.dropFirst().dropLast())
                runs.append(.code(inner))
            } else if matched.hasPrefix("**") && matched.hasSuffix("**") && matched.count >= 4 {
                let inner = String(matched.dropFirst(2).dropLast(2))
                runs.append(.bold(inner))
            } else if matched.hasPrefix("*") && matched.hasSuffix("*") {
                let inner = String(matched.dropFirst().dropLast())
                runs.append(.italic(inner))
            } else if matched.hasPrefix("_") && matched.hasSuffix("_") {
                let inner = String(matched.dropFirst().dropLast())
                runs.append(.italic(inner))
            } else {
                runs.append(.plain(matched))
            }

            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < ns.length {
            let after = ns.substring(from: lastEnd)
            if !after.isEmpty { runs.append(.plain(after)) }
        }

        if runs.isEmpty {
            return [.plain(text)]
        }
        return runs
    }

    // MARK: - Flatten (tests / fallback AttributedString)

    static func flatten(
        _ blocks: [MarkdownBlock],
        baseFont: Font,
        boldFont: Font,
        textColor: Color
    ) -> AttributedString {
        var result = AttributedString()
        for (index, block) in blocks.enumerated() {
            switch block {
            case .blank:
                break
            case .heading(_, let runs):
                result.append(attributed(runs, baseFont: boldFont, boldFont: boldFont, textColor: textColor))
            case .paragraph(let runs):
                result.append(attributed(runs, baseFont: baseFont, boldFont: boldFont, textColor: textColor))
            case .unorderedItem(_, let runs):
                var bullet = AttributedString("\u{2022} ")
                bullet.font = baseFont
                bullet.foregroundColor = textColor
                result.append(bullet)
                result.append(attributed(runs, baseFont: baseFont, boldFont: boldFont, textColor: textColor))
            case .orderedItem(let n, _, let runs):
                var marker = AttributedString("\(n). ")
                marker.font = baseFont
                marker.foregroundColor = textColor
                result.append(marker)
                result.append(attributed(runs, baseFont: baseFont, boldFont: boldFont, textColor: textColor))
            }
            if index < blocks.count - 1 {
                var newline = AttributedString("\n")
                newline.font = baseFont
                result.append(newline)
            }
        }
        return result
    }

    static func attributed(
        _ runs: [MarkdownInline],
        baseFont: Font,
        boldFont: Font,
        textColor: Color
    ) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var attr: AttributedString
            switch run {
            case .plain(let t):
                attr = AttributedString(t)
                attr.font = baseFont
            case .bold(let t):
                attr = AttributedString(t)
                attr.font = boldFont
            case .italic(let t):
                attr = AttributedString(t)
                attr.font = baseFont
                attr.inlinePresentationIntent = .emphasized
            case .code(let t):
                attr = AttributedString(t)
                attr.font = baseFont
                attr.inlinePresentationIntent = .code
            }
            attr.foregroundColor = textColor
            result.append(attr)
        }
        return result
    }

    // MARK: - Regex (compiled once)

    private static let headingRegex = try? NSRegularExpression(
        pattern: #"^(#{1,6})\s+(.*)$"#
    )
    private static let unorderedRegex = try? NSRegularExpression(
        pattern: #"^[-*+]\s+(.*)$"#
    )
    private static let orderedRegex = try? NSRegularExpression(
        pattern: #"^(\d+)\.\s+(.*)$"#
    )
    /// Order: code, then **bold**, then *italic*, then _italic_ with word bounds.
    private static let inlineRegex = try? NSRegularExpression(
        pattern: #"(`[^`\n]+`)|(\*\*[^*]+\*\*)|(\*[^*\n]+\*)|(?<![A-Za-z0-9])_[^_\n]+_(?![A-Za-z0-9])"#
    )
}

// MARK: - Previews

#Preview("Rich Text Parser") {
    VStack(alignment: .leading, spacing: 16) {
        Text(RichTextParser.parse(
            "This is **bold** and *italic* text.",
            baseFont: .body,
            boldFont: .body.bold(),
            textColor: .primary
        ))

        Text(RichTextParser.parse(
            "- First bullet point\n- Second **bold** item\n- Third *emphasized* point",
            baseFont: .body,
            boldFont: .body.bold(),
            textColor: .primary
        ))

        Text(RichTextParser.parse(
            "### 12 March\nYou asked about work.\n1. The long walk home\n2. Sunday dread",
            baseFont: .body,
            boldFont: .body.bold(),
            textColor: .primary
        ))
    }
    .padding()
}
