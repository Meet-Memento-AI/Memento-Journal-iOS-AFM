//
//  ReplyRenderer.swift
//  withMemento
//
//  Spec 050 R4: the one path from model text to the bubble. The model places
//  {{quote:n}} / {{date:n}} markers; this expands them from the turn's
//  EvidencePack and strips whatever would put journal words on screen that
//  Swift did not already have. No Foundation Models import.
//

import Foundation

/// A quote the reply shows. The citation sheet mirrors these.
struct QuoteChip: Sendable, Equatable, Identifiable {
    let slotIndex: Int
    let entryId: UUID
    let date: Date
    let displayDate: String
    /// Exactly the words the body shows for this slot.
    let quoteText: String

    var id: UUID { entryId }
}

/// What one render did, in counts only. Safe to log and to write to eval rows.
struct ReplyRenderStats: Sendable, Equatable {
    var packState: EvidenceState
    var slotCount: Int
    var expandedQuoteSlots: [Int] = []
    var expandedDateSlots: [Int] = []
    /// Unmarked spans that were verbatim pack text, inserted as if marked.
    var adoptedQuoteCount = 0
    /// Markers that resolved to nothing: unknown kind, bad index, wrong pack state.
    var droppedMarkerCount = 0
    var droppedDuplicateQuoteCount = 0
    var strippedItalicCount = 0
    /// Quotations nothing backs; each took its sentence with it.
    var droppedQuotationCount = 0
    var unwrappedBoldCount = 0
    var strippedDateCount = 0
    var droppedHeadingCount = 0
    var usedFallback = false

    var logLine: String {
        "pack=\(packState.rawValue) slots=\(slotCount) quotes=\(expandedQuoteSlots.count) "
            + "dates=\(expandedDateSlots.count) adopted=\(adoptedQuoteCount) "
            + "dropped_markers=\(droppedMarkerCount) duplicates=\(droppedDuplicateQuoteCount) "
            + "italics=\(strippedItalicCount) quotations=\(droppedQuotationCount) "
            + "bold=\(unwrappedBoldCount) raw_dates=\(strippedDateCount) "
            + "headings=\(droppedHeadingCount) fallback=\(usedFallback ? 1 : 0)"
    }
}

struct RenderedReply: Sendable, Equatable {
    /// User-visible markdown. Never contains a marker.
    let body: String
    let chips: [QuoteChip]
    /// Entries the body references through a shown quote or date, in order.
    let citations: [UUID]
    /// Slots the body shows (quote or date), in order of first appearance.
    let expandedSlotIndexes: [Int]
    let stats: ReplyRenderStats

    var strippedItalicCount: Int { stats.strippedItalicCount }
    var droppedUnknownMarkerCount: Int { stats.droppedMarkerCount }
}

/// What the person has said in this conversation. Their own words may be
/// quoted back or dated; they are never journal evidence.
struct RenderContext: Sendable, Equatable {
    let userTexts: [String]

    static let empty = RenderContext(userTexts: [])

    init(userTexts: [String]) {
        self.userTexts = userTexts
    }

    init(question: String, history: [ChatTurn]) {
        self.init(userTexts: [question] + history.reversed().filter { $0.role == .user }.map(\.text))
    }
}

enum ReplyRenderer {
    static let version = "reply-render@1"

    /// Used only when a reply that had words renders to none.
    static let emptyFallback = "Say a little more about that. What's on your mind?"

    static func render(
        _ raw: String,
        pack: EvidencePack,
        context: RenderContext = .empty,
        isFinal: Bool = true
    ) -> RenderedReply {
        var pass = RenderPass(pack: pack, context: context)
        var text = OutputSafetyScanner.strippingHarnessMarkup(raw)
        text = pass.placeMarkers(in: text)
        text = CitationReconciliation.strippingReferenceMarkers(text)
        text = pass.resolveQuoteShapedSpans(in: text)
        text = pass.verifyBold(in: text)
        text = pass.banUnbackedDates(in: text)
        text = pass.dropHeadings(in: text)
        text = RenderText.dropFlaggedSentences(text)
        text = RenderText.recapitalizeAfterRemovals(text)
        text = RenderText.tidy(text)
        return pass.finish(text, isFinal: isFinal, rawHadWords: RenderText.hasContent(raw))
    }
}

// MARK: - Placeholders

/// Resolved markers become three private-use characters — an opener that
/// names the kind, an index, a closer — so no later pass can read or edit an
/// expansion. `EvidencePackBuilder` never admits these characters into a quote.
enum RenderToken {
    static let quoteOpen: Character = "\u{E002}"
    static let dateOpen: Character = "\u{E003}"
    static let statOpen: Character = "\u{E004}"
    static let close: Character = "\u{E001}"
    static let indexBase: UInt32 = 0xE100

    static let quotePattern = #"\x{E002}[\x{E100}-\x{E7FF}]\x{E001}"#
    static let datePattern = #"[\x{E003}\x{E004}][\x{E100}-\x{E7FF}]\x{E001}"#

    static func make(_ index: Int, open: Character) -> String {
        guard let scalar = Unicode.Scalar(indexBase + UInt32(index)) else { return "" }
        return String(open) + String(Character(scalar)) + String(close)
    }

    static func index(of character: Character) -> Int? {
        guard let value = character.unicodeScalars.first?.value,
              value >= indexBase, value < indexBase + 0x700 else { return nil }
        return Int(value - indexBase)
    }

    static func isToken(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        return (0xE000...0xE7FF).contains(value)
    }
}

// MARK: - One render

struct RenderExpansion {
    enum Kind { case quote, date, stat }
    let kind: Kind
    let slotIndex: Int?
    /// What the body shows, without the italic wrapper.
    let text: String
}

/// The state of one `ReplyRenderer.render` call. The strict span, bold,
/// date and heading passes live in `ReplyRenderer+Strict.swift`.
struct RenderPass {
    typealias Expansion = RenderExpansion

    let pack: EvidencePack
    let context: RenderContext
    var stats: ReplyRenderStats
    var expansions: [Expansion] = []
    /// What the person said, folded the way spans are folded.
    let foldedConversation: String

    init(pack: EvidencePack, context: RenderContext) {
        self.pack = pack
        self.context = context
        stats = ReplyRenderStats(packState: pack.state, slotCount: pack.slots.count)
        foldedConversation = context.userTexts.map(RenderText.foldedString).joined(separator: "\u{1}")
    }

    // MARK: Markers

    /// `{{quote:1}}`, `{quote:1}`, `{{ Quote : 1 }}` — a small model drifts on
    /// spelling, so parsing is lenient; resolving is not.
    private static let marker = RenderText.regex(
        #"\{\{?\s*(quote|date|stat)\s*:\s*([A-Za-z0-9_\-]+)\s*\}\}?"#, options: [.caseInsensitive]
    )
    /// Marker-shaped text that did not resolve: `{{quote:N}}`, `{{entry:2}}`,
    /// or a marker the reply ended inside (`{{quote:1`).
    private static let markerJunk = [
        RenderText.regex(#"\{\{[^{}\n]{0,40}\}\}|\{\s*[A-Za-z]+\s*:\s*[^{}\s]{1,20}\s*\}"#),
        RenderText.regex(#"\{\{?\s*(?:quote|date|stat)\s*:?\s*[A-Za-z0-9_\-]*"#, options: [.caseInsensitive])
    ]

    mutating func placeMarkers(in text: String) -> String {
        let clean = String(String.UnicodeScalarView(
            text.unicodeScalars.filter { !(0xE000...0xE7FF).contains($0.value) }
        ))
        var placed = RenderText.replacing(Self.marker, in: clean) { groups in
            self.resolve(kind: groups[1].lowercased(), id: groups[2]) ?? ""
        }
        for junk in Self.markerJunk {
            placed = RenderText.replacing(junk, in: placed) { _ in
                self.stats.droppedMarkerCount += 1
                return ""
            }
        }
        placed.removeAll { $0 == "{" || $0 == "}" }
        return RenderText.absorbWrappers(placed)
    }

    private mutating func resolve(kind: String, id: String) -> String? {
        switch kind {
        case "quote":
            guard pack.state == .matched, let index = Int(id),
                  let slot = pack.slot(index), let quote = slot.quoteText else {
                stats.droppedMarkerCount += 1
                return nil
            }
            guard !showsQuote(for: index) else {
                stats.droppedDuplicateQuoteCount += 1
                return nil
            }
            let shown = slot.quoteIsClipped ? quote + "…" : quote
            return add(Expansion(kind: .quote, slotIndex: index, text: shown))
        case "date":
            guard let index = Int(id), let slot = pack.slot(index) else {
                stats.droppedMarkerCount += 1
                return nil
            }
            return add(Expansion(kind: .date, slotIndex: index, text: slot.displayDate))
        default:
            guard let stat = pack.stat(id) else {
                stats.droppedMarkerCount += 1
                return nil
            }
            return add(Expansion(kind: .stat, slotIndex: nil, text: stat.spokenMagnitude))
        }
    }

    mutating func add(_ expansion: Expansion) -> String {
        expansions.append(expansion)
        let open: Character
        switch expansion.kind {
        case .quote: open = RenderToken.quoteOpen
        case .date: open = RenderToken.dateOpen
        case .stat: open = RenderToken.statOpen
        }
        return RenderToken.make(expansions.count - 1, open: open)
    }

    func showsQuote(for slotIndex: Int) -> Bool {
        expansions.contains { $0.kind == .quote && $0.slotIndex == slotIndex }
    }

    // MARK: Finish

    func finish(_ glue: String, isFinal: Bool, rawHadWords: Bool) -> RenderedReply {
        var stats = self.stats
        var body = ""
        var chips: [QuoteChip] = []
        var citations: [UUID] = []
        var shown: [Int] = []
        let characters = Array(glue)
        var position = 0
        while position < characters.count {
            let character = characters[position]
            guard RenderToken.isToken(character) else {
                body.append(character)
                position += 1
                continue
            }
            let isOpen = character == RenderToken.quoteOpen || character == RenderToken.dateOpen
                || character == RenderToken.statOpen
            guard isOpen, position + 2 < characters.count, characters[position + 2] == RenderToken.close,
                  let index = RenderToken.index(of: characters[position + 1]), index < expansions.count else {
                position += 1
                continue
            }
            let expansion = expansions[index]
            switch expansion.kind {
            case .quote:
                body += "*" + expansion.text + "*"
                if let slotIndex = expansion.slotIndex, let slot = pack.slot(slotIndex) {
                    chips.append(QuoteChip(
                        slotIndex: slotIndex,
                        entryId: slot.entryId,
                        date: slot.date,
                        displayDate: slot.displayDate,
                        quoteText: expansion.text
                    ))
                    stats.expandedQuoteSlots.append(slotIndex)
                }
            case .date:
                body += expansion.text
                if let slotIndex = expansion.slotIndex { stats.expandedDateSlots.append(slotIndex) }
            case .stat:
                body += expansion.text
            }
            if let slotIndex = expansion.slotIndex, !shown.contains(slotIndex), let slot = pack.slot(slotIndex) {
                shown.append(slotIndex)
                citations.append(slot.entryId)
            }
            position += 3
        }
        body = RenderText.replacing(RenderText.regex(#"([.!?…])\*([.!?])"#), in: body) { groups in
            groups[1] + "*"
        }
        if isFinal, rawHadWords, !RenderText.hasContent(body) {
            stats.usedFallback = true
            stats.expandedQuoteSlots = []
            stats.expandedDateSlots = []
            return RenderedReply(
                body: ReplyRenderer.emptyFallback,
                chips: [],
                citations: [],
                expandedSlotIndexes: [],
                stats: stats
            )
        }
        return RenderedReply(body: body, chips: chips, citations: citations, expandedSlotIndexes: shown, stats: stats)
    }
}

// MARK: - Text helpers

enum RenderText {

    static func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

    /// Replaces every match with `transform(groups)`, where `groups[0]` is the
    /// match and missing groups are empty.
    static func replacing(
        _ regex: NSRegularExpression?,
        in text: String,
        with transform: ([String]) -> String
    ) -> String {
        guard let regex else { return text }
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            out += transform(groups)
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// Emphasis or quotation marks hugging a quote marker are the model
    /// formatting the marker; the expansion brings its own.
    static func absorbWrappers(_ text: String) -> String {
        let wrap = #"[*_\x{201C}\x{201D}"]+"#
        var out = replacing(regex(wrap + "(" + RenderToken.quotePattern + ")"), in: text) { $0[1] }
        out = replacing(regex("(" + RenderToken.quotePattern + #")([.,;:!?]?)"# + wrap), in: out) {
            $0[1] + $0[2]
        }
        return replacing(regex(#"[*_]+("# + RenderToken.datePattern + #")[*_]+"#), in: out) { $0[1] }
    }

    static func isHeading(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        return trimmed.hasPrefix("#")
    }

    /// A letter, a digit, or an expansion.
    static func hasContent<S: StringProtocol>(_ text: S) -> Bool {
        text.contains { $0.isLetter || $0.isNumber || $0 == RenderToken.close }
    }

    /// Spacing and punctuation a removal can leave behind.
    static func tidy(_ text: String) -> String {
        var out = replacing(regex(#"(?<!\*)\*(?!\*)"#), in: text) { _ in "" }
        let passes: [(String, String)] = [
            (#"[ \t]{2,}"#, " "),
            (#"[ \t]+([,.;:!?])"#, "$1"),
            (#"\x{201C}\s*\x{201D}|""|\(\s*\)"#, ""),
            (#"(?m)^[ \t]*[,;:][ \t]*"#, ""),
            (#",(\s*,)+"#, ",")
        ]
        for (pattern, template) in passes {
            guard let compiled = regex(pattern) else { continue }
            out = compiled.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template
            )
        }
        out = out.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).isEmpty || hasContent($0) }
            .joined(separator: "\n")
        out = replacing(regex(#"\n{3,}"#), in: out) { _ in "\n\n" }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
