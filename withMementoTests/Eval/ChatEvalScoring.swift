import Foundation
@testable import withMemento

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

        /// True when the index was built from no entries. An italic span or
        /// `###` heading against this index is fabricated journal form.
        let isEmpty: Bool

        init(_ entries: [Entry]) {
            isEmpty = entries.isEmpty
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
        if let m = body.range(of: placeholderPattern, options: .regularExpression) {
            v.append(.init(code: "leak.placeholder", detail: String(body[m])))
        }
        // Bracket pairs the marker stripper cannot see: its patterns all require
        // \d+ inside the brackets, so `[,]`, `[]` and `[ref]` survive to screen.
        if let m = body.range(of: emptyBracketPattern, options: .regularExpression) {
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
        if body.range(of: promptTagPattern, options: .regularExpression) != nil {
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
    static func ruleBreaks(
        _ body: String,
        isCasual: Bool,
        index: QuoteIndex? = nil,
        openRequired: Bool = true
    ) -> [Violation] {
        var v: [Violation] = []
        let lower = body.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        for opener in ["you wrote", "you mentioned", "looking at your entries", "in your journal"] {
            if lower.hasPrefix(opener) {
                v.append(.init(code: "rule.bannedOpener", detail: "\"\(opener)\""))
                break
            }
        }

        // Open is required on reflect. Task policies and empty statistic
        // bodies do not owe a question. More than one question still counts.
        let questionCount = body.filter { $0 == "?" }.count
        if openRequired && questionCount == 0 {
            v.append(.init(code: "rule.noOpen", detail: "no closing question"))
        } else if questionCount > 1 {
            v.append(.init(code: "rule.multipleQuestions", detail: "\(questionCount) questions"))
        }

        if body.range(of: entryCountPattern,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            v.append(.init(code: "rule.entryCount", detail: "states a count of entries"))
        }

        let h3 = body.components(separatedBy: "###").count - 1
        if h3 > 1 { v.append(.init(code: "rule.multipleH3", detail: "\(h3) ### headings")) }
        if body.range(of: badHeadingPattern, options: .regularExpression) != nil {
            v.append(.init(code: "rule.badHeading", detail: "# or ## used"))
        }
        if body.range(of: emptyHeadingPattern, options: .regularExpression) != nil {
            v.append(.init(code: "rule.emptyHeading", detail: "dangling ###"))
        }
        if body.contains("```") { v.append(.init(code: "rule.codeFence", detail: "code fence")) }
        if body.contains("|---") || body.range(of: tablePattern, options: .regularExpression) != nil {
            v.append(.init(code: "rule.table", detail: "table"))
        }
        if body.range(of: emojiPattern, options: .regularExpression) != nil {
            v.append(.init(code: "rule.emoji", detail: "emoji"))
        }
        if body.range(of: thirdPersonPattern, options: [.regularExpression, .caseInsensitive]) != nil {
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
            if body.range(of: casualListPattern, options: .regularExpression) != nil {
                v.append(.init(code: "rule.casualList", detail: "list on casual turn"))
            }
        }
        return v
    }

    // MARK: - Patterns

    // Named so `ChatEvalScoringTests` can compile every one of them. Inline
    // literals cannot be reached by a test, and an unreachable pattern that
    // fails to compile is indistinguishable from a clean reply (046 R1).

    static let placeholderPattern = #"\[[A-Za-z][A-Za-z ]{1,20}\]"#
    static let emptyBracketPattern = #"\[\s*[^\]\d]{0,6}\s*\]"#
    static let promptTagPattern = #"\[Turn:|\[Shape:|\[Name:|\[Safety:"#
    static let entryCountPattern =
        #"\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+entries\b"#
    static let badHeadingPattern = #"(^|\n)#{1,2}[^#]"#
    static let emptyHeadingPattern = #"###\s*($|\n)"#
    static let tablePattern = #"\|.+\|.+\|"#
    static let emojiPattern = #"[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]"#
    static let thirdPersonPattern = #"\bthe user\b"#
    static let casualListPattern = #"(^|\n)- "#
    static let boldPattern = #"\*\*([^*\n]{8,200}?)\*\*"#
    static let digitPattern = #"\b(\d+)\b"#
    /// A month-and-day assertion in the reply: "March 12", "on March 12, 2026".
    /// Capture group 1 is the whole date so `spans` can return it.
    ///
    /// Study III measured these more than doubling on the seeded arm once
    /// `{{date:N}}` made dating salient — 118 to 290, with 250 passing every
    /// check the suite had. Nothing scored them.
    static let assertedDatePattern =
        #"((?:January|February|March|April|May|June|July|August|September|October|November|December)"#
        + #"\s+\d{1,2}(?:,?\s+\d{4})?)"#

    /// `\x{201C}`, not `\u{201C}`. This is a Swift *raw* string, so backslash
    /// escapes reach ICU untouched, and ICU accepts `\uhhhh` and `\x{hhhh}` but
    /// rejects `\u{hhhh}`. With the old spelling `NSRegularExpression.init` threw,
    /// `spans` swallowed it, and this scorer returned no violations for every
    /// input it was ever given. The emoji pattern above is the in-file precedent
    /// for the working form. Do not "simplify" this back.
    static let fabricatedQuotePattern =
        #"(?<!\*)\*(?!\*)[\x{201C}"]?([^*\n]{12,200}?)[\x{201D}"]?(?<!\*)\*(?!\*)"#

    // MARK: - hall.*

    /// Every pattern this file compiles, so `ChatEvalScoringTests` can prove each
    /// one is valid. A scorer whose pattern does not compile returns no
    /// violations and reads as a pass — which is how `hall.fabricatedQuote` went
    /// undetected for its entire life (046 R1).
    static let regexPatterns: [String: String] = [
        "leak.placeholder": placeholderPattern,
        "leak.emptyBracket": emptyBracketPattern,
        "leak.promptTag": promptTagPattern,
        "rule.entryCount": entryCountPattern,
        "rule.badHeading": badHeadingPattern,
        "rule.table": tablePattern,
        "rule.emoji": emojiPattern,
        "rule.emptyHeading": emptyHeadingPattern,
        "rule.thirdPerson": thirdPersonPattern,
        "rule.casualList": casualListPattern,
        "hall.fabricatedQuote": fabricatedQuotePattern,
        "rule.boldNotTheirWords": boldPattern,
        "insight.digitDisagrees": digitPattern,
        "hall.unbackedDate": assertedDatePattern
    ]

    private static func spans(_ body: String, pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            // Unreachable once `ChatEvalScoringTests.test_everyPattern_compiles`
            // holds; kept as a guard rather than a crash so a scoring bug can
            // never take a long eval run down with it.
            return []
        }
        let ns = body as NSString
        return re.matches(in: body, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard m.numberOfRanges > 1 else { return nil }
            return fold(ns.substring(with: m.range(at: 1)))
                .trimmingCharacters(in: CharacterSet(charactersIn: " \"'.,;:-!?"))
        }
    }

    /// Italics reserved for an exact journal quote. `\x{201C}` / `\x{201D}` are
    /// the ICU forms; a Swift raw string does not process `\u{…}`, and ICU
    /// rejects that escape, which is why this check never compiled.
    ///
    /// `(?<!\*)\*(?!\*)` keeps **bold** spans out of this check.
    static let italicQuotePattern = #"(?<!\*)\*(?!\*)[\x{201C}"]?([^*\n]{12,200}?)[\x{201D}"]?(?<!\*)\*(?!\*)"#

    /// First person plus a perception verb. "I hear you" and "I'm here" stay legal.
    static let perceptionPattern = #"(?i)\bi (saw|heard|felt|noticed|smelled|remembered)\b"#

    /// Every regular expression this file compiles. `ChatEvalScoringTests`
    /// fails if any of them does not.
    static let compiledPatterns: [String] = [
        #"\[[A-Za-z][A-Za-z ]{1,20}\]"#,
        #"\[\s*[^\]\d]{0,6}\s*\]"#,
        #"\[Turn:|\[Shape:|\[Name:|\[Safety:"#,
        #"\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+entries\b"#,
        #"(^|\n)#{1,2}[^#]"#,
        #"###\s*($|\n)"#,
        #"\|.+\|.+\|"#,
        #"[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}]"#,
        #"\bthe user\b"#,
        #"(^|\n)- "#,
        italicQuotePattern,
        #"\*\*([^*\n]{8,200}?)\*\*"#,
        perceptionPattern,
        #"\b(\d+)\b"#,
        assertedDatePattern
    ]

    static let narrativeJoinPhrases = [
        "you keep tracing",
        "the pattern",
        "you're holding"
    ]

    static func fabricatedQuotes(_ body: String, index: QuoteIndex) -> [Violation] {
        if index.isEmpty {
            return emptyCorpusFabrications(body)
        }
        return spans(body, pattern: italicQuotePattern)
            .filter { $0.count >= 12 && !index.contains($0) }
            .map { .init(code: "hall.fabricatedQuote", detail: "\"\($0.prefix(60))\"") }
    }

    /// Empty archive: an italic span or a `###` heading is fabricated.
    /// Support is `quotedRefs`, the same matcher generation uses, not a second one.
    private static func emptyCorpusFabrications(_ body: String) -> [Violation] {
        let supported = FoundationModelsIntelligenceService.quotedRefs(
            in: body, retrieval: .empty
        )
        guard supported.isEmpty else { return [] }
        var violations: [Violation] = []
        for span in spans(body, pattern: italicQuotePattern) where span.count >= 12 {
            violations.append(.init(code: "hall.fabricatedQuote", detail: "\"\(span.prefix(60))\""))
        }
        if body.contains("###") {
            violations.append(.init(
                code: "hall.fabricatedQuote",
                detail: "### heading on an empty archive"
            ))
        }
        return violations
    }

    /// The model claims it perceived the person's scene. Report-only.
    static func firstPersonPerception(_ body: String) -> [Violation] {
        guard let re = try? NSRegularExpression(pattern: perceptionPattern, options: []) else {
            return []
        }
        let ns = body as NSString
        return re.matches(in: body, range: NSRange(location: 0, length: ns.length)).map { match in
            let verb = match.numberOfRanges > 1
                ? ns.substring(with: match.range(at: 1))
                : "perception"
            return .init(code: "hall.firstPersonPerception", detail: verb)
        }
    }

    /// Joins fragments the user did not supply. Silent when the phrase is already
    /// in the user turn. Report-only.
    static func narrativeJoin(_ body: String, userTurn: String) -> [Violation] {
        let foldedBody = fold(body)
        let foldedUser = fold(userTurn)
        return narrativeJoinPhrases.compactMap { phrase in
            let folded = fold(phrase)
            guard foldedBody.contains(folded), !foldedUser.contains(folded) else { return nil }
            return .init(code: "hall.narrativeJoin", detail: phrase)
        }
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

    /// A date the reply asserts that no cited entry carries.
    ///
    /// The third reference class, after quotes and counts. Spec 050 gave dates a
    /// marker and the renderer expands `{{date:N}}` from the entry's own
    /// timestamp, so a *marked* date is correct by construction. A date the
    /// model typed itself is not, and until now nothing looked.
    ///
    /// `AskCitation` already carries `entryDate`, so this needs no new plumbing —
    /// the same shape as `uncitedQuote`, which takes citations for the same
    /// reason. A date is backed when it names the same day as some cited entry;
    /// the year is optional in the reply, so a match on month and day is enough
    /// and a stated year must agree if present.
    ///
    /// Report-only on arrival (046 R1): measure first, threshold after two
    /// warehoused runs.
    static func unbackedDate(_ body: String, citations: [AskCitation],
                             calendar: Calendar = .current) -> [Violation] {
        let asserted = spans(body, pattern: assertedDatePattern)
        guard !asserted.isEmpty else { return [] }
        let backing = citations.map { calendar.dateComponents([.year, .month, .day], from: $0.entryDate) }
        return asserted.compactMap { span -> Violation? in
            guard let parsed = parseAssertedDate(span, calendar: calendar) else { return nil }
            let backed = backing.contains { cited in
                cited.month == parsed.month && cited.day == parsed.day
                    && (parsed.year == nil || cited.year == parsed.year)
            }
            guard !backed else { return nil }
            return .init(code: "hall.unbackedDate",
                         detail: "\"\(span.prefix(40))\" with \(citations.count) citation(s)")
        }
    }

    /// Month name, day, optional year. Deliberately its own parser rather than a
    /// `DateFormatter`: the reply's year is often absent, and a formatter would
    /// silently supply 2000 for a bare "March 12".
    ///
    /// The renderer has an equivalent in `ReplyRenderer+Strict.swift`
    /// (`RenderPass.parse`), but it is `private` and the test target's
    /// `@testable import` does not reach `private`. Keep the two adjacent in
    /// review: if one learns a new date shape, the other should.
    private static func parseAssertedDate(_ span: String,
                                          calendar: Calendar) -> (month: Int, day: Int, year: Int?)? {
        let months = ["january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
                      "july": 7, "august": 8, "september": 9, "october": 10, "november": 11,
                      "december": 12]
        let parts = span.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
        guard let first = parts.first, let month = months[first], parts.count >= 2,
              let day = Int(parts[1]), (1...31).contains(day) else { return nil }
        let year = parts.count >= 3 ? Int(parts[2]) : nil
        return (month, day, year)
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
        spans(body, pattern: boldPattern)
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

    // MARK: - insight.* (045 R5 / Session 12 — gated)

    /// Body states a digit that is not any attached fact's `n` or numeric value.
    /// Empty body (statistic short-circuit) cannot disagree.
    static func insightDigitDisagrees(body: String, facts: [InsightFact]) -> [Violation] {
        guard !facts.isEmpty, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let allowed = Set(facts.flatMap { fact -> [Int] in
            var nums = [fact.n]
            if let parsed = Int(fact.value) { nums.append(parsed) }
            return nums
        })
        guard let re = try? NSRegularExpression(pattern: digitPattern) else { return [] }
        let ns = body as NSString
        var flagged: [Violation] = []
        re.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            guard let n = Int(ns.substring(with: match.range(at: 1))) else { return }
            if n >= 1900 && n <= 2100 { return }
            if !allowed.contains(n) {
                flagged.append(.init(code: "insight.digitDisagrees",
                                     detail: "\(n) is not any fact n \(allowed.sorted())"))
            }
        }
        return flagged
    }

    /// Prose treats a low-confidence (`n < 4`) fact as a pattern, or names a
    /// fact the engine would have suppressed. Session 12 attaches `[Computed]`
    /// on notebook; suppressed facts must stay out of that block.
    static func insightContradictsSuppressed(body: String, facts: [InsightFact]) -> [Violation] {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let lower = body.lowercased()
        let suppressed = facts.filter(\.isLowConfidence)
        guard !suppressed.isEmpty else { return [] }
        if lower.contains("too few") { return [] }
        let claimsPattern = lower.contains("pattern") || lower.contains("always")
            || lower.contains("usually") || lower.contains("tends to")
        guard claimsPattern else { return [] }
        return suppressed.map {
            .init(code: "insight.contradictsSuppressed",
                  detail: "claimed a pattern for \"\($0.label)\" (n=\($0.n))")
        }
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
    /// Repaired and new hallucination checks stay report-only until two
    /// warehoused runs exist. Cold-arm hits are detection, not a regression.
    static let reportOnlyCodes: Set<String> = [
        "hall.fabricatedQuote",
        "hall.firstPersonPerception",
        "hall.narrativeJoin",
        "hall.unbackedDate"
    ]

    static func gating(_ violations: [Violation]) -> [Violation] {
        violations.filter { v in
            if v.code.hasPrefix("gen.") || reportOnlyCodes.contains(v.code) { return false }
            return v.code.hasPrefix("leak.") || v.code.hasPrefix("rule.")
                || v.code.hasPrefix("hall.") || v.code.hasPrefix("gold.")
                || v.code.hasPrefix("insight.")
        }
    }
}
