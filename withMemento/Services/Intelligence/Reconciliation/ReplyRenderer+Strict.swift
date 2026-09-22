//
//  ReplyRenderer+Strict.swift
//  MeetMemento
//
//  Spec 050 R4 steps 4–7: what the renderer does with journal-shaped text
//  the model wrote itself instead of placing a marker. A span the pack can
//  back is inserted from the pack; the person's own words stay theirs; a
//  quotation nothing backs takes its sentence with it; a date nothing backs
//  is removed. No Foundation Models import.
//

import Foundation

extension RenderToken {
    /// Marks a fabricated quotation; the sentence holding it is dropped.
    static let drop: Character = "\u{E0FF}"
    /// Marks where a date was removed, so a sentence it opened is recapitalised.
    static let removal: Character = "\u{E0FE}"
}

// MARK: - Quote-shaped spans

extension RenderPass {

    /// A folded span this long that the pack holds verbatim becomes a real
    /// expansion. Matches the eval scorer's 12-character italic threshold.
    static let adoptionMinimum = 12

    private static let italicStar = RenderText.regex(#"(?<![*\w])\*(?![\s*])([^*\n]+?)(?<![\s*])\*(?![*\w])"#)
    private static let italicUnderscore = RenderText.regex(
        #"(?<![_\p{L}\p{N}])_(?![\s_])([^_\n]+?)(?<![\s_])_(?![_\p{L}\p{N}])"#
    )
    private static let curlyQuotation = RenderText.regex(#"\x{201C}([^\x{201C}\x{201D}\n]{1,240})\x{201D}"#)
    private static let straightQuotation = RenderText.regex(#""([^"\n]{1,240})""#)

    /// Italics first (they may hold quotation marks), then bare quotations.
    mutating func resolveQuoteShapedSpans(in text: String) -> String {
        var out = RenderText.replacing(RenderText.regex(#"\*{3,}"#), in: text) { _ in "**" }
        for regex in [Self.italicStar, Self.italicUnderscore] {
            out = RenderText.replacing(regex, in: out) { groups in
                self.resolveSpan(inner: groups[1], whole: groups[0], italic: true)
            }
        }
        for regex in [Self.curlyQuotation, Self.straightQuotation] {
            out = RenderText.replacing(regex, in: out) { groups in
                self.resolveSpan(inner: groups[1], whole: groups[0], italic: false)
            }
        }
        return out
    }

    /// One span, in priority order: an expansion inside it; verbatim pack
    /// text (adopted); the person's own words; a short verbatim fragment;
    /// an unverifiable quotation (dropped with its sentence); emphasis.
    private mutating func resolveSpan(inner: String, whole: String, italic: Bool) -> String {
        let bare = inner.trimmingCharacters(in: RenderText.quoteMarksAndSpace)
        let quoted = !italic || bare.count < inner.trimmingCharacters(in: .whitespaces).count
        if inner.contains(where: RenderToken.isToken) {
            if italic { stats.strippedItalicCount += 1 }
            return italic ? inner : whole
        }
        let needle = RenderText.foldedCharacters(bare, trimmingPunctuation: true)
        let ending = RenderText.sentenceEnding(of: bare)
        if pack.state == .matched, needle.count >= Self.adoptionMinimum,
           let found = adoptable(needle, keepingEnding: !ending.isEmpty) {
            guard !showsQuote(for: found.slot.index) else {
                stats.droppedDuplicateQuoteCount += 1
                return ""
            }
            guard found.text.rangeOfCharacter(from: EvidencePackBuilder.unquotableCharacters) == nil else {
                if italic { stats.strippedItalicCount += 1 }
                return bare
            }
            stats.adoptedQuoteCount += 1
            let token = add(Expansion(kind: .quote, slotIndex: found.slot.index, text: found.text))
            // A sentence the model ended inside the span still ends here.
            return token + (RenderText.sentenceEnding(of: found.text).isEmpty ? ending : "")
        }
        if !needle.isEmpty, foldedConversation.contains(String(needle)) {
            guard italic else { return whole }
            stats.strippedItalicCount += 1
            return quoted ? inner : "\u{201C}" + bare + "\u{201D}"
        }
        if pack.state == .matched, !needle.isEmpty,
           pack.slots.contains(where: { FoldedText($0.passageText).contains(needle) }) {
            guard italic else { return whole }
            stats.strippedItalicCount += 1
            return inner
        }
        if RenderText.isQuotationShaped(bare, foldedCount: needle.count, quoted: quoted) {
            stats.droppedQuotationCount += 1
            // Keep the span's own sentence end, so only its sentence goes.
            return String(RenderToken.drop) + RenderText.sentenceEnding(of: bare)
        }
        if italic { stats.strippedItalicCount += 1 }
        return bare
    }

    /// The slot that holds `needle` verbatim, and the exact pack text for it:
    /// the slot's own quote when the span is that quote, otherwise the span's
    /// original characters in the passage — through the passage's own
    /// sentence end when the model's span had one.
    private func adoptable(_ needle: [Character], keepingEnding: Bool) -> (slot: EvidenceSlot, text: String)? {
        for slot in pack.slots {
            guard let quote = slot.quoteText,
                  RenderText.foldedCharacters(quote, trimmingPunctuation: true) == needle else { continue }
            return (slot, slot.quoteIsClipped ? quote + "…" : quote)
        }
        let trailing: Set<Character> = keepingEnding ? [".", "!", "?", "…"] : []
        for slot in pack.slots {
            if let original = FoldedText(slot.passageText).original(matching: needle, keepingTrailing: trailing) {
                return (slot, original)
            }
        }
        return nil
    }

    // MARK: Bold

    private static let bold = RenderText.regex(#"\*\*([^*\n]+?)\*\*"#)

    /// Bold stays only on words from a slot the body shows (the Sit rule:
    /// "bold only words that appear in the quoted entry").
    mutating func verifyBold(in text: String) -> String {
        let shownPassages = expansions.indices
            .filter { text.contains(RenderToken.make($0, open: Self.open(for: expansions[$0].kind))) }
            .compactMap { expansions[$0].slotIndex }
            .compactMap { pack.slot($0)?.passageText }
            .map(FoldedText.init)
        return RenderText.replacing(Self.bold, in: text) { groups in
            let needle = RenderText.foldedCharacters(groups[1], trimmingPunctuation: true)
            let backed = !groups[1].contains(where: RenderToken.isToken) && !needle.isEmpty
                && shownPassages.contains { $0.contains(needle) }
            if backed { return groups[0] }
            self.stats.unwrappedBoldCount += 1
            return groups[1]
        }
    }

    private static func open(for kind: Expansion.Kind) -> Character {
        switch kind {
        case .quote: return RenderToken.quoteOpen
        case .date: return RenderToken.dateOpen
        case .stat: return RenderToken.statOpen
        }
    }

    // MARK: Headings

    /// A heading is journal form: without evidence it goes. With evidence it
    /// goes only when a removal left it empty.
    mutating func dropHeadings(in text: String) -> String {
        let lines = text.components(separatedBy: "\n").filter { line in
            guard RenderText.isHeading(line) else { return true }
            let content = line.drop { $0 == "#" || $0.isWhitespace }
            guard pack.state != .none, RenderText.hasContent(content) else {
                stats.droppedHeadingCount += 1
                return false
            }
            return true
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Dates

extension RenderPass {

    private static let months = "January|February|March|April|May|June|July|August|September|October|November|December"
        + "|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sept|Sep|Oct|Nov|Dec"
    private static let preposition = #"(?:\b(?:[Oo]n|[Ii]n|[Ff]rom|[Ss]ince|[Aa]round|[Bb]y|[Bb]ack in|[Aa]s of|[Oo]f)\s+)?"#

    private enum DateForm { case iso, numeric, monthDay, dayMonth, monthYear }

    private static let datePatterns: [(DateForm, NSRegularExpression?)] = [
        (.iso, RenderText.regex(preposition + #"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#)),
        (.numeric, RenderText.regex(preposition + #"\b(\d{1,2})/(\d{1,2})/(\d{4}|\d{2})\b"#)),
        (.monthDay, RenderText.regex(
            preposition + #"\b("# + months + #")\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4})\b)?"#
        )),
        (.dayMonth, RenderText.regex(
            preposition + #"\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?("# + months + #")\b\.?(?:,?\s+(\d{4})\b)?"#
        )),
        (.monthYear, RenderText.regex(preposition + #"\b("# + months + #")\.?\s+(\d{4})\b"#))
    ]

    /// A date in glue survives only if a slot the prompt carried falls on it
    /// (at the precision written) or the person wrote it. Otherwise it goes,
    /// with the preposition that introduced it. Dates inside expansions are
    /// the person's own words and are never seen here.
    mutating func banUnbackedDates(in text: String) -> String {
        var out = text
        for (form, regex) in Self.datePatterns {
            out = RenderText.replacing(regex, in: out) { groups in
                guard let date = Self.parse(form, groups) else { return groups[0] }
                if self.dateIsBacked(date, written: groups[0]) { return groups[0] }
                self.stats.strippedDateCount += 1
                return String(RenderToken.removal)
            }
        }
        return out
    }

    /// A date as written: the precision the model chose is the precision checked.
    private struct WrittenDate {
        let year: Int?
        let month: Int
        let day: Int?
    }

    private static func parse(_ form: DateForm, _ groups: [String]) -> WrittenDate? {
        func number(_ index: Int) -> Int? { index < groups.count ? Int(groups[index]) : nil }
        func year(_ index: Int) -> Int? {
            guard let value = number(index) else { return nil }
            return value < 100 ? 2000 + value : value
        }
        let written: WrittenDate?
        switch form {
        case .iso:
            written = number(2).map { WrittenDate(year: year(1), month: $0, day: number(3)) }
        case .numeric:
            guard let first = number(1), let second = number(2) else { return nil }
            written = first > 12
                ? WrittenDate(year: year(3), month: second, day: first)
                : WrittenDate(year: year(3), month: first, day: second)
        case .monthDay:
            written = monthNumber(groups[1]).map { WrittenDate(year: year(3), month: $0, day: number(2)) }
        case .dayMonth:
            written = monthNumber(groups[2]).map { WrittenDate(year: year(3), month: $0, day: number(1)) }
        case .monthYear:
            written = monthNumber(groups[1]).map { WrittenDate(year: year(2), month: $0, day: nil) }
        }
        guard let date = written, (1...12).contains(date.month),
              date.day.map({ (1...31).contains($0) }) ?? true else { return nil }
        return date
    }

    private static func monthNumber(_ name: String) -> Int? {
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return names.firstIndex(of: String(name.lowercased().prefix(3))).map { $0 + 1 }
    }

    private func dateIsBacked(_ date: WrittenDate, written: String) -> Bool {
        let calendar = Calendar.current
        for shipped in pack.contextDates {
            let parts = calendar.dateComponents([.year, .month, .day], from: shipped)
            guard parts.month == date.month else { continue }
            if let day = date.day, parts.day != day { continue }
            if let year = date.year, parts.year != year { continue }
            return true
        }
        let bare = RenderText.stripLeadingPreposition(written)
        return foldedConversation.contains(RenderText.foldedString(bare))
    }
}

// MARK: - Folding

/// Text folded the way the eval scorer and `quotedRefs` fold it — case,
/// curly quotes, dashes, ellipses, whitespace — keeping a map back to the
/// original characters so a match can be lifted out verbatim.
struct FoldedText {
    private let source: [Character]
    private let folded: [Character]
    private let origins: [Int]

    init(_ text: String) {
        source = Array(text)
        var characters: [Character] = []
        var map: [Int] = []
        var pendingSpace = false
        for (index, character) in source.enumerated() {
            if character.isWhitespace {
                pendingSpace = !characters.isEmpty
                continue
            }
            if pendingSpace {
                characters.append(" ")
                map.append(index)
                pendingSpace = false
            }
            for piece in RenderText.fold(character) {
                characters.append(piece)
                map.append(index)
            }
        }
        folded = characters
        origins = map
    }

    func contains(_ needle: [Character]) -> Bool {
        firstMatch(needle) != nil
    }

    /// The original characters behind the first folded match of `needle`,
    /// extended through any directly following `trailing` characters.
    func original(matching needle: [Character], keepingTrailing trailing: Set<Character> = []) -> String? {
        guard let start = firstMatch(needle) else { return nil }
        var end = origins[start + needle.count - 1]
        while end + 1 < source.count, trailing.contains(source[end + 1]) { end += 1 }
        return String(source[origins[start]...end])
    }

    private func firstMatch(_ needle: [Character]) -> Int? {
        guard !needle.isEmpty, needle.count <= folded.count else { return nil }
        var start = 0
        while start + needle.count <= folded.count {
            if folded[start] == needle[0], Array(folded[start..<(start + needle.count)]) == needle {
                return start
            }
            start += 1
        }
        return nil
    }
}

extension RenderText {

    static let quoteMarksAndSpace = CharacterSet(charactersIn: "\"\u{201C}\u{201D}").union(.whitespaces)
    private static let edgePunctuation = CharacterSet(charactersIn: " \"'.,;:-!?\u{201C}\u{201D}\u{2026}")
    private static let firstPersonWords: Set<String> = ["i", "i'm", "i've", "i'd", "i'll", "me", "my", "mine", "myself"]

    static func fold(_ character: Character) -> [Character] {
        switch character {
        case "\u{2019}", "\u{2018}": return ["'"]
        case "\u{201C}", "\u{201D}": return ["\""]
        case "\u{2014}", "\u{2013}": return ["-"]
        case "\u{2026}": return [".", ".", "."]
        default: return Array(String(character).lowercased())
        }
    }

    static func foldedString(_ text: String) -> String {
        String(foldedCharacters(text, trimmingPunctuation: false))
    }

    static func foldedCharacters(_ text: String, trimmingPunctuation: Bool) -> [Character] {
        let trimmed = trimmingPunctuation ? text.trimmingCharacters(in: edgePunctuation) : text
        var out: [Character] = []
        var pendingSpace = false
        for character in trimmed {
            if character.isWhitespace {
                pendingSpace = !out.isEmpty
                continue
            }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            out.append(contentsOf: fold(character))
        }
        return out
    }

    /// First-person, or set in quotation marks and at least four words — the
    /// shapes that assert "someone wrote exactly this."
    static func isQuotationShaped(_ text: String, foldedCount: Int, quoted: Bool) -> Bool {
        guard foldedCount >= RenderPass.adoptionMinimum else { return false }
        let words = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !$0.isLetter && $0 != "'" }
            .map(String.init)
        if words.contains(where: firstPersonWords.contains) { return true }
        return quoted && words.count >= 4
    }

    static func stripLeadingPreposition(_ written: String) -> String {
        replacing(regex(#"^(?:on|in|from|since|around|by|back in|as of|of)\s+"#, options: [.caseInsensitive]),
                  in: written) { _ in "" }
    }

    // MARK: Sentences

    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "”", "’", "'", ")", "]", "*", "_"]

    /// The terminator run `text` ends with, if any ("", ".", "?!").
    static func sentenceEnding(of text: String) -> String {
        String(text.reversed().prefix { terminators.contains($0) }.reversed())
    }

    /// A line's sentences, each keeping the whitespace after it.
    static func sentences(of line: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            current.append(characters[index])
            guard terminators.contains(characters[index]) else {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count, terminators.contains(characters[end]) || closers.contains(characters[end]) {
                current.append(characters[end])
                end += 1
            }
            if end >= characters.count || characters[end].isWhitespace {
                while end < characters.count, characters[end].isWhitespace {
                    current.append(characters[end])
                    end += 1
                }
                pieces.append(current)
                current = ""
            }
            index = end
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// A fabricated quotation cannot be repaired into truth, so the sentence
    /// that carried it goes too.
    static func dropFlaggedSentences(_ text: String) -> String {
        guard text.contains(RenderToken.drop) else { return text }
        return text.components(separatedBy: "\n").map { line in
            guard line.contains(RenderToken.drop) else { return line }
            return sentences(of: line).filter { !$0.contains(RenderToken.drop) }.joined()
        }.joined(separator: "\n")
    }

    /// Where a removed date opened a sentence, the words after it do now.
    static func recapitalizeAfterRemovals(_ text: String) -> String {
        guard text.contains(RenderToken.removal) else { return text }
        var characters = Array(text)
        var index = 0
        while index < characters.count {
            guard characters[index] == RenderToken.removal else {
                index += 1
                continue
            }
            characters.remove(at: index)
            var before = index - 1
            while before >= 0, characters[before] == " " || characters[before] == "\t" { before -= 1 }
            let opensSentence = before < 0 || characters[before] == "\n" || terminators.contains(characters[before])
                || characters[before] == "#"
            guard opensSentence else { continue }
            while index < characters.count, " \t,;:".contains(characters[index]) {
                characters.remove(at: index)
            }
            if index < characters.count, characters[index].isLowercase {
                let upper = characters[index].uppercased()
                if upper.count == 1, let first = upper.first { characters[index] = first }
            }
        }
        return String(characters)
    }
}
