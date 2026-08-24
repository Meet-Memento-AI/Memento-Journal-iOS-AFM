import Foundation
@testable import MeetMemento

/// Mechanical scoring for the chat evaluation gate.
///
/// Every check here is deterministic — no judge model, no human read. That is
/// deliberate: the gate has to be reachable at 100%, so it may only assert
/// things that are true or false about the text. Semantic quality (is this a
/// *good* reflection?) is sampled into the report, never gated.
///
/// Violation codes are namespaced by family:
///   `leak.*` — scaffolding that should never reach a chat bubble
///   `rule.*` — an explicit ask@14 rule, checkable from the text alone
///   `hall.*` — a claim about the journal the corpus does not support
///   `gen.*`  — generation-shape problems (runaway, truncation signature)
enum ChatEvalScoring {

    struct Violation: Equatable {
        let code: String
        let detail: String
    }

    // MARK: - Normalisation

    /// The model rounds quotes and dashes; the stored entries do not. Fold both
    /// sides so a genuine quote is never scored as fabricated.
    static func fold(_ s: String) -> String {
        var t = s.lowercased()
        for (from, to) in [("\u{2019}", "'"), ("\u{2018}", "'"),
                           ("\u{201C}", "\""), ("\u{201D}", "\""),
                           ("\u{2014}", "-"), ("\u{2013}", "-"),
                           ("\u{2026}", "...")] {
            t = t.replacingOccurrences(of: from, with: to)
        }
        // Collapse whitespace so a line break in the entry cannot break a match.
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: - Quote index

    /// Answers two questions about a corpus fast enough to run per generation:
    /// does this span appear verbatim, and does this reply quote the journal at
    /// all? Built once per corpus, reused across every generation against it.
    struct QuoteIndex {
        private let haystack: String
        private let grams: Set<Int>
        private static let gram = 30

        init(_ entries: [Entry]) {
            haystack = entries.map { ChatEvalScoring.fold($0.title + " " + $0.text) }
                .joined(separator: " \u{1} ")
            var set = Set<Int>()
            let chars = Array(haystack)
            if chars.count >= Self.gram {
                set.reserveCapacity(chars.count)
                for i in 0...(chars.count - Self.gram) {
                    // Hash the slice directly. Materialising a `String` per
                    // window allocated a quarter of a million short strings over
                    // the 262-entry persona corpus, which was enough to get the
                    // test process killed on a busy machine.
                    set.insert(Self.hash(chars[i..<(i + Self.gram)]))
                }
            }
            grams = set
        }

        private static func hash(_ slice: ArraySlice<Character>) -> Int {
            var hasher = Hasher()
            for character in slice { hasher.combine(character) }
            return hasher.finalize()
        }

        /// Is `span` present verbatim in the corpus?
        func contains(_ span: String) -> Bool {
            haystack.contains(ChatEvalScoring.fold(span))
        }

        /// Does `body` reproduce at least `gram` consecutive characters of the
        /// corpus? Hash-prefiltered, then confirmed against the haystack so a
        /// hash collision cannot produce a false positive.
        func quotesCorpus(_ body: String) -> String? {
            let folded = ChatEvalScoring.fold(body)
            let chars = Array(folded)
            guard chars.count >= Self.gram else { return nil }
            for i in 0...(chars.count - Self.gram) {
                let slice = chars[i..<(i + Self.gram)]
                guard grams.contains(Self.hash(slice)) else { continue }
                // Confirm against the text itself — a hash hit alone could be a
                // collision, and a false "this reply quoted the journal" would
                // fail the gate on a reply that did nothing wrong.
                let window = String(slice)
                if haystack.contains(window) { return window }
            }
            return nil
        }
    }

    // MARK: - leak.*

    /// Scaffolding that should never reach a chat bubble.
    static func leaks(_ body: String) -> [Violation] {
        var v: [Violation] = []

        // Structured-output field names written as prose. Observed live as a
        // trailing "citedRefs:" and "citedRefs: 1." — the marker stripper's
        // `\brefs?` pattern cannot match inside `citedRefs`, so nothing removes it.
        for field in ["citedRefs", "heading1", "heading2"] {
            if let r = body.range(of: field) {
                v.append(.init(code: "leak.schemaField",
                               detail: String(body[r.lowerBound...].prefix(40))))
                break
            }
        }
        if body.contains("<ctrl") {
            let n = body.components(separatedBy: "<ctrl").count - 1
            v.append(.init(code: "leak.ctrlToken", detail: "\(n) token(s)"))
        }
        // [Name] / [Alex] style placeholders.
        if let m = body.range(of: #"\[[A-Za-z][A-Za-z ]{1,20}\]"#, options: .regularExpression) {
            v.append(.init(code: "leak.placeholder", detail: String(body[m])))
        }
        // Bracket pairs the marker stripper cannot see: its patterns all require
        // \d+ inside the brackets, so `[,]`, `[]` and `[ref]` survive to screen.
        if let m = body.range(of: #"\[\s*[^\]\d]{0,6}\s*\]"#, options: .regularExpression) {
            v.append(.init(code: "leak.emptyBracket", detail: String(body[m])))
        }
        if body.contains("*italic*") || body.contains("*bold*") {
            v.append(.init(code: "leak.literalMarkup", detail: "*italic*/*bold* emitted as text"))
        }
        for label in ["Meet them \u{2014}", "Notebook \u{2014}", "Sit \u{2014}", "Open \u{2014}"] {
            if body.contains(label) {
                v.append(.init(code: "leak.sectionLabel", detail: label))
                break
            }
        }
        if body.range(of: #"\[Turn:|\[Shape:|\[Name:|\[Safety:"#, options: .regularExpression) != nil {
            v.append(.init(code: "leak.promptTag", detail: "prompt tag echoed"))
        }
        // Evidence-block chrome.
        if body.contains("[ref ") || body.contains("[End of journal context]")
            || body.contains("Journal evidence") {
            v.append(.init(code: "leak.evidenceChrome", detail: "context block echoed"))
        }
        return v
    }

    // MARK: - rule.*

    /// ask@14 rules that can be decided from the text alone.
    /// `index` lets the banned-phrase check tell the assistant's own register
    /// from the person's. Pass it wherever a corpus is in play.
    static func ruleBreaks(_ body: String, isCasual: Bool, index: QuoteIndex? = nil) -> [Violation] {
        var v: [Violation] = []
        let lower = body.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        for opener in ["you wrote", "you mentioned", "looking at your entries", "in your journal"] {
            if lower.hasPrefix(opener) {
                v.append(.init(code: "rule.bannedOpener", detail: "\"\(opener)\""))
                break
            }
        }

        // Open is required, and there is never more than one question.
        let questionCount = body.filter { $0 == "?" }.count
        if questionCount == 0 {
            v.append(.init(code: "rule.noOpen", detail: "no closing question"))
        } else if questionCount > 1 {
            v.append(.init(code: "rule.multipleQuestions", detail: "\(questionCount) questions"))
        }

        if body.range(of: #"\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+entries\b"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            v.append(.init(code: "rule.entryCount", detail: "states a count of entries"))
        }

        let h3 = body.components(separatedBy: "###").count - 1
        if h3 > 1 { v.append(.init(code: "rule.multipleH3", detail: "\(h3) ### headings")) }
        if body.range(of: #"(^|\n)#{1,2}[^#]"#, options: .regularExpression) != nil {
            v.append(.init(code: "rule.badHeading", detail: "# or ## used"))
        }
        if body.range(of: #"###\s*($|\n)"#, options: .regularExpression) != nil {
            v.append(.init(code: "rule.emptyHeading", detail: "dangling ###"))
        }
        if body.contains("```") { v.append(.init(code: "rule.codeFence", detail: "code fence")) }
        if body.contains("|---") || body.range(of: #"\|.+\|.+\|"#, options: .regularExpression) != nil {
            v.append(.init(code: "rule.table", detail: "table"))
        }
        if body.range(of: #"[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]"#, options: .regularExpression) != nil {
            v.append(.init(code: "rule.emoji", detail: "emoji"))
        }
        if body.range(of: #"\bthe user\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            v.append(.init(code: "rule.thirdPerson", detail: "\"the user\""))
        }
        // The ban is on the assistant's own register — "obviously, you're
        // stressed" — not on the words the person used themselves. ask@15 is
        // explicit that "reflecting their own words is fine", and the gate
        // caught itself on that distinction: it flagged a reply for "Didn't
        // send it obviously", which is the entry's own sentence
        // (`entries-2026-03.json`) reflected back in second person. Exactly
        // what the prompt asks for. So a phrase the corpus already contains is
        // theirs, not ours.
        for phrase in ["you should", "obviously", "you always", "you never", "the problem is"] {
            guard lower.contains(phrase) else { continue }
            if let index, index.contains(phrase) { continue }
            v.append(.init(code: "rule.bannedPhrase", detail: "\"\(phrase)\""))
            break
        }
        if isCasual {
            if body.contains("###") { v.append(.init(code: "rule.casualHeading", detail: "### on casual turn")) }
            if body.contains("**") { v.append(.init(code: "rule.casualBold", detail: "bold on casual turn")) }
            if body.range(of: #"(^|\n)- "#, options: .regularExpression) != nil {
                v.append(.init(code: "rule.casualList", detail: "list on casual turn"))
            }
        }
        return v
    }

    // MARK: - hall.*

    private static func spans(_ body: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = body as NSString
        return re.matches(in: body, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges > 1 else { return nil }
            return fold(ns.substring(with: m.range(at: 1)))
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'.,;:-!?"))
        }
    }

    /// ask@14 reserves *italics* for an exact journal quote. An italic span that
    /// is not in the corpus is an invented entry — the single most damaging
    /// failure mode for a journal app.
    ///
    /// `(?<!\*)\*(?!\*)` keeps **bold** spans out of this check.
    static func fabricatedQuotes(_ body: String, index: QuoteIndex) -> [Violation] {
        let pattern = #"(?<!\*)\*(?!\*)[\u{201C}"]?([^*\n]{12,200}?)[\u{201D}"]?(?<!\*)\*(?!\*)"#
        return spans(body, pattern: pattern)
            .filter { $0.count >= 12 && !index.contains($0) }
            .map { .init(code: "hall.fabricatedQuote", detail: "\"\($0.prefix(60))\"") }
    }

    /// A reply that reproduces the journal verbatim must be citable. Zero
    /// citations alongside a verbatim span is the signature of the ambient
    /// retrieval path: the entries are in the prompt, so the model quotes them,
    /// but `reconcileCitations` suppresses the citation set and the reader has
    /// no way to check the quote.
    static func uncitedQuote(_ body: String, citations: [AskCitation],
                             index: QuoteIndex) -> [Violation] {
        guard citations.isEmpty, let span = index.quotesCorpus(body) else { return [] }
        return [.init(code: "hall.uncitedQuote", detail: "\"\(span.prefix(50))\" with 0 citations")]
    }

    // MARK: - gold.* — is the answer right, not just well-formed?

    /// Scores a reply's citations against the gold set's `expectedEntryIDs`.
    ///
    /// This is the gate's blind spot closed. Everything above judges the
    /// *contract* — is the reply well-formed, does it leak scaffolding, does it
    /// cite when it quotes. None of it asks whether the reply is **right**, and
    /// measured on 2026-08-23 that gap was hiding real failures: all three
    /// `match: "none"` honesty traps passed while being wrong, one of them
    /// answering *"What did I write about my brother in 2025?"* from a March
    /// **2026** entry, and another correctly saying *"I don't see any mention"*
    /// of a dog **while displaying three citations**.
    ///
    /// Semantics come from `Fixtures/gold/questions.json`'s own `notes` field
    /// and match `AgenticEval.GoldRecord`, which implemented this first — kept
    /// deliberately identical so the two instruments cannot disagree:
    ///   - `all`  — every expected entry must be cited
    ///   - `any`  — at least one expected entry must be cited
    ///   - `none` — nothing supports the question; any citation is invented
    ///
    /// `citedFixtureIDs` are fixture ids (`e-2026-01-12-1`), resolved from a
    /// citation's `entryId` through the map `personaCorpus()` returns.
    static func goldOutcome(citedFixtureIDs: [String],
                            expected: [String],
                            match: String) -> [Violation] {
        let cited = Set(citedFixtureIDs)
        let want = Set(expected)

        switch match {
        case "none":
            guard !cited.isEmpty else { return [] }
            return [.init(code: "gold.overcited",
                          detail: "\(cited.count) citation(s) on a question nothing supports")]

        case "any":
            if cited.isDisjoint(with: want) {
                return [.init(code: cited.isEmpty ? "gold.noCitation" : "gold.wrongCitation",
                              detail: cited.isEmpty
                                ? "expected any of \(want.count), cited none"
                                : "cited \(cited.sorted().prefix(3).joined(separator: ", ")), none expected")]
            }
            return []

        default: // "all"
            if cited.isEmpty {
                return [.init(code: "gold.noCitation",
                              detail: "expected \(want.count), cited none")]
            }
            if want.isSubset(of: cited) { return [] }
            if cited.isDisjoint(with: want) {
                return [.init(code: "gold.wrongCitation",
                              detail: "cited \(cited.sorted().prefix(3).joined(separator: ", ")), expected \(want.sorted().prefix(3).joined(separator: ", "))")]
            }
            let missing = want.subtracting(cited)
            return [.init(code: "gold.partialCitation",
                          detail: "missing \(missing.count) of \(want.count): \(missing.sorted().prefix(3).joined(separator: ", "))")]
        }
    }

    // MARK: - Reported, not gated

    /// ask@14 scopes `**bold**` to a short span of *their* wording. A bolded
    /// phrase absent from the journal is the model's own prose dressed as the
    /// user's words. Noisy enough to report rather than gate.
    static func boldNotTheirWords(_ body: String, index: QuoteIndex) -> [Violation] {
        spans(body, pattern: #"\*\*([^*\n]{8,200}?)\*\*"#)
            .filter { span in
                guard span.count >= 8, !index.contains(span) else { return false }
                let words = span.split(separator: " ").map(String.init).filter { $0.count > 3 }
                guard !words.isEmpty else { return false }
                let present = words.filter { index.contains($0) }.count
                return Double(present) / Double(words.count) < 0.6
            }
            .map { .init(code: "rule.boldNotTheirWords", detail: "\"\($0.prefix(60))\"") }
    }

    /// Ran to (or near) the channel's token ceiling — the truncation signature.
    static func runaway(_ body: String, capTokens: Int) -> [Violation] {
        let approxTokens = Double(body.count) / 3.6   // ~3.6 chars/token, this model, English
        guard approxTokens > Double(capTokens) * 0.85 else { return [] }
        return [.init(code: "gen.hitTokenCap", detail: "~\(Int(approxTokens)) tok vs cap \(capTokens)")]
    }

    // MARK: - Gate

    /// Families that must be empty for a run to pass.
    ///
    /// `rule.boldNotTheirWords` was reported-only in the first phase — 14 to 15
    /// hits per hundred, and a threshold picked before the first measurement is
    /// a guess. It is now gated: `ask@15` states the rule explicitly ("words
    /// that appear in the entry you just quoted, never your own phrasing dressed
    /// as theirs"), and a reply that bolds the model's own prose as if it were
    /// the person's own words is a correctness failure, not a style preference.
    ///
    /// `gen.*` stays reported. `gen.hitTokenCap` is a proximity warning about
    /// the budget, not a defect in the reply — a reply can legitimately run long.
    static func gating(_ violations: [Violation]) -> [Violation] {
        violations.filter { v in
            if v.code.hasPrefix("gen.") { return false }
            return v.code.hasPrefix("leak.") || v.code.hasPrefix("rule.")
                || v.code.hasPrefix("hall.") || v.code.hasPrefix("gold.")
        }
    }
}
