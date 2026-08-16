//
//  SpeakabilityLinter.swift
//  MeetMemento
//
//  Spec 018 R9 (REQ-VOX-006, P6): "speakable by construction" enforced
//  mechanically. Every reflection Memento produces is also spoken by
//  AVSpeechSynthesizer, so markdown, bullets, headings, emoji, URLs, and
//  blank-line runs read terribly aloud and are forbidden.
//
//  This is a VALIDATOR for reflection prose — a thin Swift port of the CI
//  reference engine `scripts/ci/speakability_lint.py` (same patterns, same
//  order; keep them in sync). It is deliberately distinct from
//  `SpeechTextSanitizer`, the TRANSFORMER for markdown-bearing chat prose:
//  chat legitimately contains markdown and gets cleaned at synthesis time;
//  reflection prose must never have contained it, and a violation here is a
//  generation bug, not input to clean up.
//

import Foundation

/// A speakability violation. `description` names the pattern and REQ-VOX-006
/// so a test failure reads as the spec gate it is (R9 exit criteria).
struct SpeakabilityViolation: Error, CustomStringConvertible {
    let patternName: String
    let range: Range<String.Index>
    let snippet: String

    var description: String {
        "REQ-VOX-006 speakability violation [\(patternName)]: \"\(snippet)\""
    }
}

struct SpeakabilityLinter {

    /// (name, pattern) in the same order as the Python engine's HARD_FAIL
    /// dict — first match wins, so order is part of the contract.
    private static let hardFail: [(name: String, regex: NSRegularExpression)] = {
        let sources: [(String, String)] = [
            ("markdown-heading", #"(?m)^\s{0,3}#{1,6}\s"#),
            ("markdown-emphasis-or-code", #"(\*|_{1,2}|`)"#),
            ("list-marker", #"(?m)^\s*(?:[-*•]|\d+\.)\s+"#),
            ("url", #"https?://"#),
            ("blank-line-run", #"\n[ \t]*\n[ \t]*\n"#),
            // Emoji scalar ranges, verbatim from the Python character class.
            ("emoji", "[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F1E6}-\u{1F1FF}\u{2190}-\u{21FF}\u{2B00}-\u{2BFF}\u{FE00}-\u{FE0F}]"),
        ]
        return sources.map { name, pattern in
            // Patterns are compile-time constants; a failure to compile is a
            // programmer error, so crash loudly rather than silently skip.
            (name, try! NSRegularExpression(pattern: pattern))
        }
    }()

    /// Throws `SpeakabilityViolation` naming the first forbidden pattern
    /// found and its offending range. Clean text returns normally.
    static func validate(_ text: String) throws {
        let nsRange = NSRange(text.startIndex..., in: text)
        for (name, regex) in hardFail {
            guard let match = regex.firstMatch(in: text, range: nsRange),
                  let range = Range(match.range, in: text) else { continue }
            let snippet = text[range].replacingOccurrences(of: "\n", with: "\\n")
            throw SpeakabilityViolation(patternName: name, range: range, snippet: snippet)
        }
    }
}
