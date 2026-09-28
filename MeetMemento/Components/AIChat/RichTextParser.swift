//
//  RichTextParser.swift
//  MeetMemento
//
//  Parses body text into an AttributedString with markdown formatting and
//  inline citation badges. Used by AIOutputComponent for rich text rendering.
//
//  Supports: **bold**, *italic*, [N] citation refs, and - bullet lists.
//  Citation refs are rendered as tappable links via the .link attribute.
//

import SwiftUI

struct RichTextParser {

    /// Parses body text into a SwiftUI AttributedString with markdown and citation styling.
    ///
    /// - Parameters:
    ///   - text: The raw body text (may contain **bold**, *italic*, [N] citations, and - bullet lines)
    ///   - validCitationRefs: Set of valid citation ref numbers (e.g. {1, 2, 3})
    ///   - baseFont: Font for regular body text
    ///   - boldFont: Font for bold text
    ///   - citationFont: Font for citation badges
    ///   - textColor: Default text color
    ///   - citationColor: Color for citation ref text
    /// - Returns: An AttributedString ready for use in SwiftUI `Text()`
    static func parse(
        _ text: String,
        validCitationRefs: Set<Int>,
        baseFont: Font,
        boldFont: Font,
        citationFont: Font,
        textColor: Color,
        citationColor: Color
    ) -> AttributedString {
        guard !text.isEmpty else {
            return AttributedString()
        }

        var result = AttributedString()

        // Process line by line for bullet list detection
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (lineIndex, line) in lines.enumerated() {
            let lineStr = String(line)

            // Detect unordered list items (- or * prefix)
            let isBullet = lineStr.hasPrefix("- ") || lineStr.hasPrefix("* ")
            let contentLine: String
            if isBullet {
                contentLine = String(lineStr.dropFirst(2))
                var bullet = AttributedString("  \u{2022}  ")
                bullet.font = baseFont
                bullet.foregroundColor = textColor
                result.append(bullet)
            } else {
                contentLine = lineStr
            }

            // Parse inline formatting within this line
            let parsedLine = parseInlineFormatting(
                contentLine,
                validCitationRefs: validCitationRefs,
                baseFont: baseFont,
                boldFont: boldFont,
                citationFont: citationFont,
                textColor: textColor,
                citationColor: citationColor
            )
            result.append(parsedLine)

            // Add newline between lines (except after last)
            if lineIndex < lines.count - 1 {
                var newline = AttributedString("\n")
                newline.font = baseFont
                result.append(newline)
            }
        }

        return result
    }

    // MARK: - Inline Formatting Parser

    /// Parses a single line for **bold**, *italic*, and [N] citation refs.
    private static func parseInlineFormatting(
        _ text: String,
        validCitationRefs: Set<Int>,
        baseFont: Font,
        boldFont: Font,
        citationFont: Font,
        textColor: Color,
        citationColor: Color
    ) -> AttributedString {
        var result = AttributedString()
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            // Check for bold: **text**
            if i + 1 < chars.count && chars[i] == "*" && chars[i + 1] == "*" {
                if let endIdx = findClosingDouble(chars, from: i + 2, delimiter: "*") {
                    let inner = String(chars[(i + 2)..<endIdx])
                    // Recursively parse inner content (for nested [N] inside bold)
                    var parsed = parseInlineFormatting(
                        inner,
                        validCitationRefs: validCitationRefs,
                        baseFont: boldFont,
                        boldFont: boldFont,
                        citationFont: citationFont,
                        textColor: textColor,
                        citationColor: citationColor
                    )
                    // Apply bold font to all runs that aren't citations
                    for run in parsed.runs {
                        if run.link == nil {
                            let range = run.range
                            parsed[range].font = boldFont
                        }
                    }
                    result.append(parsed)
                    i = endIdx + 2 // skip closing **
                    continue
                }
            }

            // Check for italic: *text* (but not **)
            if chars[i] == "*" && (i + 1 >= chars.count || chars[i + 1] != "*") {
                if let endIdx = findClosingSingle(chars, from: i + 1, delimiter: "*") {
                    let inner = String(chars[(i + 1)..<endIdx])
                    var segment = AttributedString(inner)
                    segment.font = baseFont
                    segment.foregroundColor = textColor
                    // SwiftUI AttributedString doesn't have direct italic, but we can use
                    // the system italic trait via UIFont or just use the font parameter
                    result.append(segment)
                    i = endIdx + 1
                    continue
                }
            }

            // Check for citation ref: [N]
            if chars[i] == "[" {
                if let (ref, endIdx) = parseCitationRef(chars, from: i, validRefs: validCitationRefs) {
                    var citation = AttributedString("[\(ref)]")
                    citation.font = citationFont
                    citation.foregroundColor = citationColor
                    citation.link = URL(string: "memento://citation/\(ref)")
                    result.append(citation)
                    i = endIdx + 1 // skip past ]
                    continue
                }
            }

            // Regular character
            var ch = AttributedString(String(chars[i]))
            ch.font = baseFont
            ch.foregroundColor = textColor
            result.append(ch)
            i += 1
        }

        return result
    }

    // MARK: - Delimiter Helpers

    /// Finds the index of a closing double delimiter (e.g. **) starting from `from`.
    private static func findClosingDouble(_ chars: [Character], from: Int, delimiter: Character) -> Int? {
        var j = from
        while j + 1 < chars.count {
            if chars[j] == delimiter && chars[j + 1] == delimiter {
                return j
            }
            j += 1
        }
        return nil
    }

    /// Finds the index of a closing single delimiter (e.g. *) starting from `from`.
    /// Does not match if the next char after opening is also the delimiter (that would be **).
    private static func findClosingSingle(_ chars: [Character], from: Int, delimiter: Character) -> Int? {
        var j = from
        while j < chars.count {
            if chars[j] == delimiter {
                return j
            }
            j += 1
        }
        return nil
    }

    /// Parses a [N] citation ref at position `from` (where chars[from] == '[').
    /// Returns (ref number, index of ']') if valid, nil otherwise.
    private static func parseCitationRef(
        _ chars: [Character],
        from: Int,
        validRefs: Set<Int>
    ) -> (Int, Int)? {
        guard from < chars.count && chars[from] == "[" else { return nil }

        // Scan for digits followed by ]
        var j = from + 1
        var digits = ""
        while j < chars.count && chars[j].isNumber {
            digits.append(chars[j])
            j += 1
        }

        // Must have at least one digit and end with ]
        guard !digits.isEmpty, j < chars.count, chars[j] == "]" else { return nil }

        guard let ref = Int(digits), validRefs.contains(ref) else { return nil }

        return (ref, j)
    }
}
