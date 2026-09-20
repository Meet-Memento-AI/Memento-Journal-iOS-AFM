//
//  SpokenFormFormatter.swift
//  MeetMemento
//
//  Spec 035: display register → spoken register, then the engine.
//  Order at the choke point: SpeechTextSanitizer → SpokenFormFormatter → engine.
//

import Foundation

enum SpeechDeliveryMode: Sendable {
    /// Narration / conversation path — no automatic breaths.
    case conversation
    /// Tap-to-read of a complete message — breaths at paragraph boundaries.
    case readBack
}

enum SpokenFormFormatter {
    /// Closed vocabulary. Enlarging this list is a spec 035 edit.
    static let allowedTags: Set<String> = ["breath", "sigh", "laugh"]

    static let conversationRateMultiplier: Float = 1.0
    static let readBackRateMultiplier: Float = 0.95

    static func format(_ text: String, mode: SpeechDeliveryMode) -> String {
        var out = rewriteDatesAndTimes(text)
        out = rewriteAmbiguousFractions(out)
        out = applyTagAllowlist(out)
        if mode == .readBack {
            out = insertReadBackBreaths(out)
        }
        return out
    }

    static func rate(preset: SpeechRatePreset, mode: SpeechDeliveryMode) -> Float {
        let multiplier = mode == .readBack ? readBackRateMultiplier : conversationRateMultiplier
        return preset.rawValue * multiplier
    }

    static func neuralSpeed(preset: SpeechRatePreset, mode: SpeechDeliveryMode) -> Float {
        let multiplier = mode == .readBack ? readBackRateMultiplier : conversationRateMultiplier
        return preset.neuralSpeed * multiplier
    }

    // MARK: - Dates / times

    /// ISO `yyyy-MM-dd` and 24-hour `HH:mm` only — raw numbers and currency
    /// pass through (R2).
    private static func rewriteDatesAndTimes(_ text: String) -> String {
        replacingTimes(in: replacingISODates(in: text))
    }

    private static func replacingISODates(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{4})-(\d{2})-(\d{2})\b"#) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges == 4,
                  let y = Int(ns.substring(with: match.range(at: 1))),
                  let m = Int(ns.substring(with: match.range(at: 2))),
                  let d = Int(ns.substring(with: match.range(at: 3))),
                  (1...12).contains(m), (1...31).contains(d)
            else { continue }
            var comps = DateComponents()
            comps.year = y
            comps.month = m
            comps.day = d
            guard let date = Calendar(identifier: .gregorian).date(from: comps) else { continue }
            let spoken = spokenDate(date)
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: spoken)
            }
        }
        return result
    }

    private static func spokenDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: date)
        let day = Calendar(identifier: .gregorian).component(.day, from: date)
        return "\(month) \(ordinal(day))"
    }

    private static func ordinal(_ day: Int) -> String {
        let suffix: String
        switch day % 100 {
        case 11, 12, 13: suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        let words: [Int: String] = [
            1: "first", 2: "second", 3: "third", 4: "fourth", 5: "fifth",
            6: "sixth", 7: "seventh", 8: "eighth", 9: "ninth", 10: "tenth",
            11: "eleventh", 12: "twelfth", 13: "thirteenth", 20: "twentieth",
            21: "twenty-first", 22: "twenty-second", 23: "twenty-third",
            30: "thirtieth", 31: "thirty-first"
        ]
        return words[day] ?? "\(day)\(suffix)"
    }

    private static func replacingTimes(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b([01]?\d|2[0-3]):([0-5]\d)\b"#) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges == 3,
                  let hour = Int(ns.substring(with: match.range(at: 1))),
                  let minute = Int(ns.substring(with: match.range(at: 2)))
            else { continue }
            let spoken = spokenTime(hour: hour, minute: minute)
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: spoken)
            }
        }
        return result
    }

    private static func spokenTime(hour: Int, minute: Int) -> String {
        if minute == 0 { return "\(hour) hundred" }
        let minuteWord = minute < 10 ? "oh \(minute)" : "\(minute)"
        return "\(hour) \(minuteWord)"
    }

    /// "3/4" as a date-or-fraction ambiguity → "three fourths". Dates already
    /// handled as ISO. Bare integers and $ amounts pass through.
    private static func rewriteAmbiguousFractions(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b([1-9])/([2-9]|1[0-9])\b"#) else {
            return text
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        let ordinals = [
            2: "halves", 3: "thirds", 4: "fourths", 5: "fifths",
            8: "eighths", 16: "sixteenths"
        ]
        let cardinals = [
            1: "one", 2: "two", 3: "three", 4: "four", 5: "five",
            6: "six", 7: "seven", 8: "eight", 9: "nine"
        ]
        for match in matches.reversed() {
            guard let n = Int(ns.substring(with: match.range(at: 1))),
                  let d = Int(ns.substring(with: match.range(at: 2))),
                  let card = cardinals[n],
                  let ord = ordinals[d]
            else { continue }
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: "\(card) \(ord)")
            }
        }
        return result
    }

    // MARK: - Tags

    /// Whitelist parse: only allowedTags survive. Everything else in angle
    /// brackets is stripped, including nested/malformed forms.
    static func applyTagAllowlist(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<([^<>]+)>"#) else {
            return text.replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            let inner = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let replacement = allowedTags.contains(inner) ? "<\(inner)>" : ""
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    /// Paragraph boundaries only — two breaths for three paragraphs.
    static func insertReadBackBreaths(_ text: String) -> String {
        let parts = text.components(separatedBy: "\n\n")
        guard parts.count > 1 else { return text }
        return parts.joined(separator: "\n\n<breath>\n\n")
    }
}
