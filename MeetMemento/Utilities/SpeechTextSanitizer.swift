//
//  SpeechTextSanitizer.swift
//  MeetMemento
//
//  Markdown-bearing chat prose in, speakable plaintext out. A *transformer*,
//  deliberately distinct from spec 018 R9's `SpeakabilityLinter` (the
//  VALIDATOR in Utilities/SpeakabilityLinter.swift for reflection prose that
//  must be speakable by construction): chat bodies legitimately contain
//  markdown, so speech strips it at synthesis time, whereas a linter hit on
//  reflection prose is a generation bug.
//

import Foundation

enum SpeechTextSanitizer {

    /// Full pipeline. Order matters: Sources block and citation refs go first
    /// (they contain brackets/emphasis the later passes would half-eat), links
    /// before emphasis (link text may itself be bold), structural markers
    /// before whitespace collapse.
    static func sanitize(_ text: String) -> String {
        var out = text

        // 1. Trailing Sources block — same definition the renderer uses.
        out = RichTextParser.stripSourcesSection(out)

        // 2. Citation/reference markers: [2], [ref 3], "ref 1 and 2"…
        out = FoundationModelsIntelligenceService.strippingReferenceMarkers(out)

        // 3a. Markdown links: keep the text, drop the URL.
        out = replacing(out, pattern: #"\[([^\]]+)\]\(\s*[^)]*\)"#, template: "$1")
        // 3b. Bare URLs: nothing worth speaking.
        out = replacing(out, pattern: #"https?://\S+"#, template: "")

        // 4. Emphasis wrappers, innermost text kept. ** before * so the bold
        //    fence isn't consumed as two italics.
        out = replacing(out, pattern: #"\*\*([^*]+)\*\*"#, template: "$1")
        out = replacing(out, pattern: #"\*([^*\n]+)\*"#, template: "$1")
        out = replacing(out, pattern: #"(?<![A-Za-z0-9])_([^_\n]+)_(?![A-Za-z0-9])"#, template: "$1")
        out = replacing(out, pattern: #"`([^`\n]*)`"#, template: "$1")

        // 5. Line-start structure: headings, bullets, ordered-list numbers.
        out = replacing(out, pattern: #"(?m)^\s*#{1,6}\s+"#, template: "")
        out = replacing(out, pattern: #"(?m)^\s*(?:[-*•]\s+|\d+\.\s+)"#, template: "")

        // 6. Emoji — mirrors scripts/ci/speakability_lint.py in spirit. The
        //    value floor keeps digits/#/* (which report isEmoji for keycaps).
        out = String(String.UnicodeScalarView(out.unicodeScalars.filter { scalar in
            !(scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value > 0x238C))
        }))

        // 7. Whitespace: collapse blank-line runs and space runs, trim.
        out = replacing(out, pattern: #"\n{3,}"#, template: "\n\n")
        out = replacing(out, pattern: #"[ \t]{2,}"#, template: " ")
        out = replacing(out, pattern: #"(?m)[ \t]+$"#, template: "")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Joins heading1/heading2/body into one speakable string. Headings get a
    /// terminal period if they lack ending punctuation, so the synthesizer
    /// pauses instead of running a heading straight into the body.
    static func speakableText(heading1: String?, heading2: String?, body: String) -> String {
        let parts = [heading1, heading2]
            .compactMap { $0 }
            .map { sanitize($0) }
            .filter { !$0.isEmpty }
            .map { heading -> String in
                heading.last.map { ".!?…:".contains($0) } == true ? heading : heading + "."
            }
        let cleanBody = sanitize(body)
        return (parts + (cleanBody.isEmpty ? [] : [cleanBody])).joined(separator: "\n\n")
    }

    // MARK: - Helpers

    private static func replacing(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }
}
