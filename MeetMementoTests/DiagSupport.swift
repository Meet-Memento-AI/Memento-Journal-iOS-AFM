import Foundation
@testable import MeetMemento

/// Shared corpus + automatic scoring for the iOS 27 chat diagnostics.
/// Throwaway diagnostics, not regression tests.
enum Diag {

    static let outDir = "/private/tmp/claude-501/-Users-sebastianmendo-Swift-projects-Memento-AI-MeetMemento/094f3be1-69b0-4026-bb20-1aad71a89c42/scratchpad/diag"

    static func write(_ text: String, _ file: String) {
        try? FileManager.default.createDirectory(atPath: outDir,
                                                 withIntermediateDirectories: true)
        try? text.write(toFile: "\(outDir)/\(file)", atomically: true, encoding: .utf8)
    }

    static func day(_ daysAgo: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    }

    static func secs(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
    }

    static func ms(_ d: Duration) -> String { String(format: "%.0f", secs(d) * 1000) }

    static func pct(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let i = min(s.count - 1, max(0, Int((Double(s.count - 1) * p).rounded())))
        return s[i]
    }

    // MARK: - Corpus

    /// Third parties act in these entries, so a correct reply must keep the
    /// subject straight (the attribution eval depends on it).
    static let corpus: [Entry] = [
        Entry(title: "Hiking Mount Tamalpais",
              text: "Drove out to Mount Tamalpais on Saturday with Maya. We started at 6am and the fog was so thick we could barely see the trailhead. Four hours up, and at the top it broke open completely. Maya said it was the first time she had felt calm in weeks. I have not felt that light in a long time. My knees hurt on the way down.",
              createdAt: day(21)),
        Entry(title: "The Q3 deadline is crushing me",
              text: "Third late night this week on the Q3 launch. Daniel pushed the deadline up two weeks without telling anyone and now the whole team is scrambling. I snapped at Priya in standup today over a staging bug that was not her fault. I need to apologise tomorrow. I keep telling myself this is temporary but I said the same thing in April.",
              createdAt: day(14)),
        Entry(title: "Coffee with Maya",
              text: "Maya came by the apartment with pastries. We talked for three hours about her leaving the nonprofit. She is scared she will regret it. I told her about how I felt before I left the agency. It is strange being the person with advice now. I want to be a better friend to her than I was last year.",
              createdAt: day(9)),
        Entry(title: "Sleep is falling apart",
              text: "Woke up at 3:40am again. That is five nights running. I checked my phone which I know makes it worse. Tried the breathing thing for ten minutes and it did nothing. I think it is the work stress but part of me thinks it started before the deadline moved. Going to try no screens after nine.",
              createdAt: day(4)),
        Entry(title: "Small good day",
              text: "Nothing dramatic today. Made eggs properly for once. Finished the Le Guin book on the balcony. Called my mother and we did not argue about the house, which is new. Priya accepted my apology and even made a joke about it. I want to remember that ordinary days like this count too.",
              createdAt: day(1))
    ]

    /// Larger corpus for context-scaling latency measurements.
    static func scaled(_ n: Int) -> [Entry] {
        guard n > corpus.count else { return Array(corpus.prefix(n)) }
        var out = corpus
        var i = 0
        while out.count < n {
            let base = corpus[i % corpus.count]
            out.append(Entry(title: "\(base.title) (\(out.count))",
                             text: base.text,
                             createdAt: day(21 + out.count)))
            i += 1
        }
        return out
    }

    // MARK: - Scoring

    struct Violation {
        let code: String
        let detail: String
    }

    /// Scaffolding that should never reach a chat bubble.
    static func leaks(_ body: String) -> [Violation] {
        var v: [Violation] = []
        if let r = body.range(of: "citedRefs") {
            v.append(.init(code: "leak.citedRefs", detail: String(body[r.lowerBound...].prefix(40))))
        }
        if body.contains("<ctrl") {
            let n = body.components(separatedBy: "<ctrl").count - 1
            v.append(.init(code: "leak.ctrlToken", detail: "\(n) token(s)"))
        }
        // [Name] / [Alex] style placeholders — bracketed non-numeric tokens.
        if let m = body.range(of: #"\[[A-Za-z][A-Za-z ]{1,20}\]"#, options: .regularExpression) {
            v.append(.init(code: "leak.placeholder", detail: String(body[m])))
        }
        if body.contains("*italic*") || body.contains("*bold*") {
            v.append(.init(code: "leak.literalMarkup", detail: "*italic*/*bold* emitted as text"))
        }
        // Section labels from the prompt recipe used as visible prose.
        for label in ["Meet them —", "Notebook —", "Sit —", "Open —"] {
            if body.contains(label) {
                v.append(.init(code: "leak.sectionLabel", detail: label))
                break
            }
        }
        if body.range(of: #"\[Turn:|\[Shape:|\[Name:"#, options: .regularExpression) != nil {
            v.append(.init(code: "leak.promptTag", detail: "[Turn:/[Shape:/[Name: echoed"))
        }
        if body.contains("}") && body.contains("citedRefs") {
            v.append(.init(code: "leak.rawSchema", detail: "JSON brace in body"))
        }
        return v
    }

    /// Explicit ask@14 rules that can be checked mechanically.
    static func ruleBreaks(_ body: String, isNotebookTurn: Bool, isCasual: Bool) -> [Violation] {
        var v: [Violation] = []
        let lower = body.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        for opener in ["you wrote", "you mentioned", "looking at your entries", "in your journal"] {
            if lower.hasPrefix(opener) {
                v.append(.init(code: "rule.bannedOpener", detail: "\"\(opener)\""))
                break
            }
        }
        // Open is required except on goodbye.
        if !body.contains("?") {
            v.append(.init(code: "rule.noOpen", detail: "no closing question"))
        }
        // Counts of entries are banned ("nine entries", "3 entries").
        if body.range(of: #"\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+entries\b"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            v.append(.init(code: "rule.entryCount", detail: "states a count of entries"))
        }
        // Markdown grammar: only ### allowed, at most one.
        let h3 = body.components(separatedBy: "###").count - 1
        if h3 > 1 { v.append(.init(code: "rule.multipleH3", detail: "\(h3) ### headings")) }
        if body.range(of: #"(^|\n)#{1,2}[^#]"#, options: .regularExpression) != nil {
            v.append(.init(code: "rule.badHeading", detail: "# or ## used"))
        }
        if body.contains("```") { v.append(.init(code: "rule.codeFence", detail: "code fence")) }
        if body.contains("|---") || body.range(of: #"\|.+\|.+\|"#, options: .regularExpression) != nil {
            v.append(.init(code: "rule.table", detail: "table"))
        }
        if body.range(of: #"[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]"#, options: .regularExpression) != nil {
            v.append(.init(code: "rule.emoji", detail: "emoji"))
        }
        // Casual turns: zero markdown structure.
        if isCasual {
            if body.contains("###") { v.append(.init(code: "rule.casualHeading", detail: "### on casual turn")) }
            if body.contains("**") { v.append(.init(code: "rule.casualBold", detail: "bold on casual turn")) }
            if body.range(of: #"(^|\n)- "#, options: .regularExpression) != nil {
                v.append(.init(code: "rule.casualList", detail: "list on casual turn"))
            }
        }
        // A stray, empty ### with nothing after it.
        if body.range(of: #"###\s*($|\n)"#, options: .regularExpression) != nil {
            v.append(.init(code: "rule.emptyHeading", detail: "dangling ###"))
        }
        // Third person about the user.
        if body.range(of: #"\bthe user\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            v.append(.init(code: "rule.thirdPerson", detail: "\"the user\""))
        }
        return v
    }

    /// Curly quotes and dashes vary between the model's output and the stored
    /// entry text; fold them so a real quote is not scored as fabricated.
    private static func fold(_ s: String) -> String {
        var t = s.lowercased()
        for (from, to) in [("’", "'"), ("‘", "'"), ("“", "\""), ("”", "\""),
                           ("—", "-"), ("–", "-"), ("…", "...")] {
            t = t.replacingOccurrences(of: from, with: to)
        }
        return t
    }

    private static func normalizedHaystack(_ entries: [Entry]) -> String {
        fold(entries.map { $0.title + " " + $0.text }.joined(separator: " \u{1} "))
    }

    private static func spans(_ body: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = body as NSString
        return re.matches(in: body, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges > 1 else { return nil }
            return fold(ns.substring(with: m.range(at: 1)))
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'.,;:-!?"))
        }
    }

    /// Did the reply put text in *italics* — which ask@14 reserves for an exact
    /// journal quote — that does not appear in the corpus?
    /// `(?<!\*)\*(?!\*)` keeps **bold** spans out of this check.
    static func fabricatedQuotes(_ body: String, entries: [Entry]) -> [Violation] {
        let hay = normalizedHaystack(entries)
        let pattern = #"(?<!\*)\*(?!\*)[“"]?([^*\n]{12,200}?)[”"]?(?<!\*)\*(?!\*)"#
        return spans(body, pattern: pattern)
            .filter { $0.count >= 12 && !hay.contains($0) }
            .map { .init(code: "hall.fabricatedQuote", detail: "\"\($0.prefix(60))\"") }
    }

    /// ask@14: "**bold** for a short span of *their* wording". A bolded phrase
    /// that appears nowhere in the journal is the model's own prose dressed as
    /// the user's words.
    static func boldNotTheirWords(_ body: String, entries: [Entry]) -> [Violation] {
        guard !entries.isEmpty else { return [] }
        let hay = normalizedHaystack(entries)
        return spans(body, pattern: #"\*\*([^*\n]{8,200}?)\*\*"#)
            .filter { span in
                guard span.count >= 8 else { return false }
                if hay.contains(span) { return false }
                // Allow a near-miss: most content words present in the journal.
                let words = span.split(separator: " ").map(String.init)
                    .filter { $0.count > 3 }
                guard !words.isEmpty else { return false }
                let present = words.filter { hay.contains($0) }.count
                return Double(present) / Double(words.count) < 0.6
            }
            .map { .init(code: "rule.boldNotTheirWords", detail: "\"\($0.prefix(60))\"") }
    }

    /// Ran to (or near) the channel's token ceiling — the runaway signature.
    static func runaway(_ body: String, capTokens: Int) -> [Violation] {
        // ~3.6 chars/token for this model's English output.
        let approxTokens = Double(body.count) / 3.6
        if approxTokens > Double(capTokens) * 0.85 {
            return [.init(code: "gen.hitTokenCap",
                          detail: "~\(Int(approxTokens)) tok vs cap \(capTokens)")]
        }
        return []
    }
}
