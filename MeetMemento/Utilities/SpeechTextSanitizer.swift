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

        // 3–5 + 7. Links, emphasis, structure, whitespace — cached regexes.
        for step in replacements {
            out = apply(step.regex, to: out, template: step.template)
        }

        // 6. Emoji — mirrors scripts/ci/speakability_lint.py in spirit. The
        //    value floor keeps digits/#/* (which report isEmoji for keycaps).
        out = String(String.UnicodeScalarView(out.unicodeScalars.filter { scalar in
            !(scalar.properties.isEmojiPresentation
                || (scalar.properties.isEmoji && scalar.value > 0x238C))
        }))

        // 7. Whitespace: collapse blank-line runs and space runs, trim.
        // After emoji so removed glyphs don't leave double spaces behind.
        for step in whitespaceReplacements {
            out = apply(step.regex, to: out, template: step.template)
        }
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

    private struct CachedReplace {
        let regex: NSRegularExpression
        let template: String
    }

    /// Compiled once (spec 029 R3 / latency sweep P3). Order matches `sanitize`.
    private static let replacements: [CachedReplace] = {
        let patterns: [(String, String)] = [
            (#"\[([^\]]+)\]\(\s*[^)]*\)"#, "$1"),
            (#"https?://\S+"#, ""),
            (#"\*\*([^*]+)\*\*"#, "$1"),
            (#"\*([^*\n]+)\*"#, "$1"),
            (#"(?<![A-Za-z0-9])_([^_\n]+)_(?![A-Za-z0-9])"#, "$1"),
            (#"`([^`\n]*)`"#, "$1"),
            (#"(?m)^\s*#{1,6}\s+"#, ""),
            (#"(?m)^\s*(?:[-*•]\s+|\d+\.\s+)"#, "")
        ]
        return patterns.compactMap { pattern, template in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return CachedReplace(regex: regex, template: template)
        }
    }()

    private static let whitespaceReplacements: [CachedReplace] = {
        let patterns: [(String, String)] = [
            (#"\n{3,}"#, "\n\n"),
            (#"[ \t]{2,}"#, " "),
            (#"(?m)[ \t]+$"#, "")
        ]
        return patterns.compactMap { pattern, template in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return CachedReplace(regex: regex, template: template)
        }
    }()

    private static func replacing(_ text: String, pattern: String, template: String) -> String {
        // sanitize() uses the cached table; this overload stays for any
        // leftover call site and still compiles the pattern once per unique
        // string via the table lookup.
        if let cached = replacements.first(where: { $0.template == template && $0.regex.pattern == pattern }) {
            return apply(cached.regex, to: text, template: cached.template)
        }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return apply(regex, to: text, template: template)
    }

    private static func apply(_ regex: NSRegularExpression, to text: String, template: String) -> String {
        regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }
}
