//
//  RichTextParser.swift
//  MeetMemento
//
//  Parses rich text with bold, italic, and bullet lists
//  into AttributedString for SwiftUI Text rendering.
//

import SwiftUI

// MARK: - Parsed Text Segment

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

/// Utility for parsing markdown-like body text into AttributedString
/// Supports: **bold**, *italic*, and - bullet lists
struct RichTextParser {

    /// Parses the text into an AttributedString with styling applied
    /// - Parameters:
    ///   - text: The body text to parse
    ///   - baseFont: Font for regular text
    ///   - boldFont: Font for **bold** text
    ///   - textColor: Color for regular text
    /// - Returns: An AttributedString with styling applied
    static func parse(
        _ text: String,
        baseFont: Font,
        boldFont: Font,
        textColor: Color
    ) -> AttributedString {
        var result = AttributedString()

        // Split by lines to handle bullet lists
        let lines = text.components(separatedBy: "\n")

        for (lineIndex, line) in lines.enumerated() {
            var processedLine = line

            // Check for bullet list item (starts with "- ")
            var isBullet = false
            if line.hasPrefix("- ") {
                isBullet = true
                processedLine = String(line.dropFirst(2))
            }

            // Parse the line content
            let lineAttributed = parseLine(
                processedLine,
                baseFont: baseFont,
                boldFont: boldFont,
                textColor: textColor
            )

            // Add bullet prefix if needed
            if isBullet {
                var bullet = AttributedString("\u{2022} ") // bullet character
                bullet.font = baseFont
                bullet.foregroundColor = textColor
                result.append(bullet)
            }

            result.append(lineAttributed)

            // Add newline between lines (not after the last line)
            if lineIndex < lines.count - 1 {
                var newline = AttributedString("\n")
                newline.font = baseFont
                result.append(newline)
            }
        }

        return result
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
        // Strip "**Sources:**" section from end of text
        let strippedText = stripSourcesSection(text)

        var segments: [ParsedTextSegment] = []

        // Regex to find [1], [2], etc.
        let pattern = #"\[(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // Fallback: return entire text as single segment
            return [.text(strippedText)]
        }

        let nsText = strippedText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: strippedText, options: [], range: fullRange)

        var lastEnd = 0

        for match in matches {
            // Add text before this citation marker
            if match.range.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let beforeText = nsText.substring(with: beforeRange)
                if !beforeText.isEmpty {
                    segments.append(.text(beforeText))
                }
            }

            // Extract the citation number
            if match.numberOfRanges >= 2 {
                let numberRange = match.range(at: 1)
                let numberString = nsText.substring(with: numberRange)
                if let citationIndex = Int(numberString), citationIndex >= 1, citationIndex <= citations.count {
                    // citations array is 0-indexed, citation markers are 1-indexed
                    let citation = citations[citationIndex - 1]
                    segments.append(.citation(
                        index: citationIndex,
                        date: citation.entryDate,
                        excerpt: citation.excerpt,
                        entryId: citation.entryId
                    ))
                } else {
                    // Invalid citation number - keep as plain text
                    let markerText = nsText.substring(with: match.range)
                    segments.append(.text(markerText))
                }
            }

            lastEnd = match.range.location + match.range.length
        }

        // Add remaining text after last citation
        if lastEnd < nsText.length {
            let afterText = nsText.substring(from: lastEnd)
            if !afterText.isEmpty {
                segments.append(.text(afterText))
            }
        }

        // If no segments were created, return the whole text
        if segments.isEmpty {
            return [.text(strippedText)]
        }

        return segments
    }

    /// Strips the "**Sources:**" section from the end of the text.
    /// Internal (not private): `SpeechTextSanitizer` reuses it so spoken text
    /// and rendered text agree on what a Sources block is.
    static func stripSourcesSection(_ text: String) -> String {
        // Look for **Sources:** or Sources: followed by bullet list at the end
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

    // MARK: - Legacy API (deprecated, forwards to simplified version)

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
        // Forward to simplified version, ignoring citation parameters
        return parse(text, baseFont: baseFont, boldFont: boldFont, textColor: textColor)
    }

    /// Parses a single line for bold and italic
    private static func parseLine(
        _ text: String,
        baseFont: Font,
        boldFont: Font,
        textColor: Color
    ) -> AttributedString {
        var result = AttributedString()

        // Regex patterns
        // Order matters: check ** before * to avoid conflicts
        // Pattern matches: **bold**, *italic*
        let pattern = #"(\*\*[^*]+\*\*)|(\*[^*]+\*)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // Fallback: return plain text
            var plain = AttributedString(text)
            plain.font = baseFont
            plain.foregroundColor = textColor
            return plain
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: fullRange)

        var lastEnd = 0

        for match in matches {
            // Add text before this match
            if match.range.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let beforeText = nsText.substring(with: beforeRange)
                var beforeAttr = AttributedString(beforeText)
                beforeAttr.font = baseFont
                beforeAttr.foregroundColor = textColor
                result.append(beforeAttr)
            }

            let matchedText = nsText.substring(with: match.range)

            if matchedText.hasPrefix("**") && matchedText.hasSuffix("**") {
                // Bold text
                let innerText = String(matchedText.dropFirst(2).dropLast(2))
                var boldAttr = AttributedString(innerText)
                boldAttr.font = boldFont
                boldAttr.foregroundColor = textColor
                result.append(boldAttr)

            } else if matchedText.hasPrefix("*") && matchedText.hasSuffix("*") {
                // Italic text - emphasize with medium weight since Manrope doesn't have italic
                let innerText = String(matchedText.dropFirst(1).dropLast(1))
                var italicAttr = AttributedString(innerText)
                // Use oblique text transform as fallback for italic
                italicAttr.font = baseFont
                italicAttr.foregroundColor = textColor
                // Add inlinePresentationIntent for semantic emphasis
                italicAttr.inlinePresentationIntent = .emphasized
                result.append(italicAttr)
            }

            lastEnd = match.range.location + match.range.length
        }

        // Add remaining text after last match
        if lastEnd < nsText.length {
            let afterText = nsText.substring(from: lastEnd)
            var afterAttr = AttributedString(afterText)
            afterAttr.font = baseFont
            afterAttr.foregroundColor = textColor
            result.append(afterAttr)
        }

        // If no matches were found, return the whole text as plain
        if matches.isEmpty {
            var plain = AttributedString(text)
            plain.font = baseFont
            plain.foregroundColor = textColor
            return plain
        }

        return result
    }
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
            "**Sources:**\n- March 5th - work stress\n- April 2nd - self-care",
            baseFont: .body,
            boldFont: .body.bold(),
            textColor: .primary
        ))
    }
    .padding()
}
