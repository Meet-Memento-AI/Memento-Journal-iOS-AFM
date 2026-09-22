//
//  ReplyRenderer+Streaming.swift
//  MeetMemento
//
//  Spec 050 R5: what a streaming delta may show. Each snapshot is cut to a
//  stable prefix and rendered with the turn's pack, so raw model text never
//  reaches the bubble or TTS. No Foundation Models import.
//

import Foundation

extension ReplyRenderer {

    /// How much of a still-growing reply may be rendered now.
    enum StreamGranularity: Sendable {
        /// Whole sentences — the journal channels, where an unverifiable
        /// quotation takes its whole sentence with it.
        case sentence
        /// Whole words — the light channels, which carry no evidence.
        case word
    }

    /// Notebook and thread carry evidence; everything else streams per word.
    static func granularity(for channel: ReplyChannel) -> StreamGranularity {
        channel.allowsRetrieval ? .sentence : .word
    }

    /// The longest prefix of `raw` that can be rendered without later text
    /// changing it: never inside an open marker, italic, bold, or quotation,
    /// and never mid-sentence (`.sentence`) or mid-word (`.word`).
    static func stablePrefix(of raw: String, granularity: StreamGranularity) -> String {
        let characters = Array(raw)
        let limit = StreamCut.openConstructStart(characters) ?? characters.count
        let cut: Int
        switch granularity {
        case .sentence: cut = StreamCut.lastSentenceBoundary(characters, upTo: limit)
        case .word: cut = StreamCut.lastSettledWord(characters, upTo: limit)
        }
        return String(characters[0..<cut])
    }

    /// What a streaming delta may show: the rendered stable prefix. Raw
    /// model text never reaches the bubble or TTS.
    static func streamingBody(
        _ raw: String,
        pack: EvidencePack,
        context: RenderContext,
        granularity: StreamGranularity
    ) -> String {
        render(stablePrefix(of: raw, granularity: granularity), pack: pack, context: context, isFinal: false).body
    }
}

enum StreamCut {
    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "”", "’", "'", ")", "]", "*", "_"]
    static let months: Set<String> = [
        "January", "February", "March", "April", "May", "June", "July", "August",
        "September", "October", "November", "December",
        "Jan", "Feb", "Mar", "Apr", "Jun", "Jul", "Aug", "Sep", "Sept", "Oct", "Nov", "Dec"
    ]

    /// Where the earliest construct still waiting for its closer begins.
    /// Emphasis and quotations never span lines, so only the last line can
    /// hold an open one; a marker may be open anywhere.
    static func openConstructStart(_ characters: [Character]) -> Int? {
        var brace: Int?
        for (index, character) in characters.enumerated() {
            if character == "{", brace == nil { brace = index }
            if character == "}" { brace = nil }
        }
        let lineStart = (characters.lastIndex(of: "\n") ?? -1) + 1
        var italic: Int?, bold: Int?, underscore: Int?, curly: Int?, straight: Int?
        var index = lineStart
        while index < characters.count {
            let character = characters[index]
            if character == "*" {
                var run = 1
                while index + run < characters.count, characters[index + run] == "*" { run += 1 }
                if run >= 2 { bold = bold == nil ? index : nil }
                if run % 2 == 1 { italic = italic == nil ? index : nil }
                index += run
                continue
            }
            let previousIsWord = index > lineStart && isWord(characters[index - 1])
            switch character {
            case "_":
                if underscore == nil, !previousIsWord {
                    underscore = index
                } else if underscore != nil, previousIsWord {
                    underscore = nil
                }
            case "“": curly = curly ?? index
            case "”": curly = nil
            case "\"": straight = straight == nil ? index : nil
            default: break
            }
            index += 1
        }
        return [brace, italic, bold, underscore, curly, straight].compactMap { $0 }.min()
    }

    /// Just past the last sentence end (a terminator run and its closing
    /// marks, followed by whitespace) or line break before `limit`.
    static func lastSentenceBoundary(_ characters: [Character], upTo limit: Int) -> Int {
        var best = 0
        var index = 0
        while index < limit {
            let character = characters[index]
            if character == "\n" {
                best = index + 1
            } else if terminators.contains(character) {
                var end = index + 1
                while end < limit, terminators.contains(characters[end]) { end += 1 }
                while end < limit, closers.contains(characters[end]) { end += 1 }
                if end < limit, characters[end].isWhitespace { best = end }
                index = end
                continue
            }
            index += 1
        }
        return best
    }

    /// Up to the last whole word before `limit`, holding back a trailing
    /// month or number that may be the start of a date still arriving.
    static func lastSettledWord(_ characters: [Character], upTo limit: Int) -> Int {
        var cut = limit
        if cut == characters.count, let last = characters.last, !last.isWhitespace {
            cut = (characters[..<cut].lastIndex(where: \.isWhitespace) ?? 0)
        } else if cut < characters.count {
            cut = (characters[..<cut].lastIndex(where: \.isWhitespace) ?? 0)
        }
        var words: [(start: Int, text: String)] = []
        var index = cut - 1
        while index >= 0, words.count < 3 {
            while index >= 0, characters[index].isWhitespace { index -= 1 }
            guard index >= 0 else { break }
            let end = index + 1
            while index >= 0, !characters[index].isWhitespace { index -= 1 }
            words.append((start: index + 1, text: String(characters[(index + 1)..<end])))
        }
        let dateLike = words.filter { word in
            let bare = word.text.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:"))
            return months.contains(bare) || bare.range(of: #"^\d{1,4}(st|nd|rd|th)?$"#, options: .regularExpression) != nil
        }
        if let earliest = dateLike.map(\.start).min() { cut = earliest }
        return cut
    }

    private static func isWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
