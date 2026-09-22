//
//  CitationReconciliation.swift
//  MeetMemento
//
//  Citation reconciliation and reference-marker stripping, moved out of the
//  intelligence service. Behavior is unchanged. No Foundation Models import.
//

import Foundation

enum CitationReconciliation {

/// Removes `[ref 2]`, `(ref 2)`, `ref 2`, and bare `[2]` from a reply.
///
/// The prompt and the `body` @Guide both ban these, but the `[ref N]` labels
/// are sitting right there in the model's context as the naming convention
/// for entries, and a small on-device model leaks them into prose. Nothing
/// downstream strips markers — `RichTextParser` does not treat `[n]` as a link,
/// and bullets — so anything the model writes reaches the screen verbatim.
/// This is the backstop.
///
/// Inline citations return in a later release; this whole function goes
/// away then, along with the prompt bans.
/// Compiled once (spec 029 R3): these ran fresh on every streamed snapshot,
/// which multiplied ~6 regex compiles by the snapshot count of every reply.
/// Ordered: bracketed/parenthesised ref forms, then bare square-bracket
/// numbers, then a bare "ref 2". Each tolerates lists ("ref 1 and 2").
private static let markerRegexes: [NSRegularExpression] = {
    let numberList = #"\d+(?:\s*(?:,|and|&)\s*\d+)*"#
    let patterns = [
        // Schema field names written as prose. FIRST, because the model
        // emits `citedRefs:[1]` / `citedRefs: 1.` as a trailing line of the
        // body far more often than it emits a bare `[ref 1]` — measured
        // 2026-08-23, and the same behaviour that used to kill the turn
        // outright before `AskAnswer.citedRefs` became optional. The
        // `\brefs?` pattern below can never match inside `citedRefs`
        // (`d` and `R` are both word characters), so this is not redundant.
        #"\s*\bcitedRefs\b\s*:?\s*(?:\[[^\]]*\]|"# + numberList + #")?\.?"#,
        #"\s*\bheading[12]\b\s*:?\s*"#,
        #"\s*[\[(]\s*refs?\.?\s*#?"# + numberList + #"\s*[\])]"#,
        #"\s*\[\s*"# + numberList + #"\s*\]"#,
        #"\s*\brefs?\.?\s*#?"# + numberList + #"\b"#,
        // Bracket pairs the number-bearing patterns above cannot see:
        // `[,]`, `[]`, `[ref]`, `[-]`. Observed live as a trailing `[,]`.
        // Bounded to 6 inner characters and no digits so a real aside in
        // square brackets is left alone.
        #"\s*\[\s*[^\]\d]{0,6}\s*\]"#
    ]
    return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
}()

/// Tidy what removal left behind: a space before punctuation, doubled
/// spaces, and an emptied parenthesis pair.
private static let cleanupRegexes: [(regex: NSRegularExpression, template: String)] = {
    let cleanups: [(String, String)] = [
        (#"\s+([,.;:!?])"#, "$1"),
        (#"[ \t]{2,}"#, " "),
        (#"\(\s*\)"#, ""),
        // The square-bracket twin of the rule above — a removal can leave
        // `[]` behind the same way it leaves `()`.
        (#"\[\s*\]"#, ""),
        // Removing a trailing field name leaves the blank line it sat on.
        (#"\n{3,}"#, "\n\n")
    ]
    return cleanups.compactMap { pattern, template in
        (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
    }
}()

/// Artefacts of a generation that ran off the end of its reply, rather than
/// anything the model meant to say. All observed in the chat eval gate on
/// 2026-08-23 and all unambiguous, which is why removing them is safe:
///
/// - a `<ctrl46>` control token and everything after it — one reply spilled
///   2,122 characters this way, continuing past its closing question into
///   `**} <ctrl46>Memento leans into the quiet…`;
/// - a trailing `}` / `**}` where the structured object leaked into prose;
/// - a dangling heading the reply never filled in (`### July 19, 2026 *`
///   as the final line, the italic quote never arriving) — five replies
///   ended mid-notebook-moment like this;
/// - a lone trailing `###` on a turn that should carry no heading at all.
///
/// Deliberately conservative: it removes only trailing wreckage and never
/// rewrites the reply. Nothing here can add a closing question the model
/// failed to write — a reply that stops early is reported by the gate as
/// `rule.noOpen`, not quietly patched.
private static let truncationArtifactRegexes: [NSRegularExpression] = {
    let patterns = [
        #"<ctrl[\s\S]*$"#,                 // control token → end
        #"\*{0,2}\}\s*$"#,                 // leaked closing brace at the end
        // A heading the reply never filled in. The character class excludes
        // sentence punctuation and caps the run at 40, which is what keeps
        // this off a heading used *inline* mid-reply: replies are often a
        // single line ("…quiet shifts. ### August 2, 2026 *“…”* … What is
        // it you're holding onto right now?"), and an earlier version of
        // this pattern matched from `###` to end of string and deleted the
        // quote, the reflection and the closing question with it. Five
        // otherwise-clean replies lost their question that way before the
        // eval gate caught it.
        #"\n?#{3}[^\n?.!]{0,40}\*?[ \t]*$"#,
        #"\n?#{3}\s*$"#                    // bare trailing ###
    ]
    return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
}()

static func strippingReferenceMarkers(_ body: String) -> String {
    var out = body
    for regex in truncationArtifactRegexes {
        out = regex.stringByReplacingMatches(
            in: out,
            range: NSRange(out.startIndex..., in: out),
            withTemplate: ""
        )
    }
    for regex in markerRegexes {
        out = regex.stringByReplacingMatches(
            in: out,
            range: NSRange(out.startIndex..., in: out),
            withTemplate: ""
        )
    }
    for (regex, template) in cleanupRegexes {
        out = regex.stringByReplacingMatches(
            in: out,
            range: NSRange(out.startIndex..., in: out),
            withTemplate: template
        )
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Citation reconciliation (the anti-fabrication guard)

private static let maxCitations = 3

/// Which journal entries this reply may be attributed to.
///
/// Three sources, in priority order:
///
/// 1. **What the model said it used** (`refs`), filtered to refs that were
///    actually in the prompt — a hallucinated ref number cites nothing.
/// 2. **What the reply demonstrably quotes** (`quotedRefs(in:)`). Derived in
///    Swift from the body, so it cannot be fabricated and does not depend on
///    the model filling `citedRefs` — which it frequently does not, writing
///    the field into its prose instead (see `AskAnswer`). This is what makes
///    "the reply quoted an entry" and "the UI shows that entry" the same
///    statement rather than two independent guesses.
/// 3. **The top reviewed entries**, only for a real topical match, so
///    "Reviewed your journals" appears from the first delta and stays put.
///
/// Ambient retrieval (recent life handed over as background, no topical
/// match) used to return `[]` unconditionally. That was the bug behind
/// replies that quoted an entry verbatim while the citation UI showed
/// nothing: the entries were in the prompt and quotable, but uncitable.
/// Ambient results are now citable — but they get no top-N fallback, so an
/// ambient turn cites exactly what it used and nothing more.
///
/// `body` is nil on the pre-generation call that seeds the "Reviewed your
/// journals" link, where there is no reply text to check yet.
///
/// Gating citations on a `.noMatch` stance was tried on 2026-08-23 and
/// reverted with the context-block change above: too many turns that the
/// journal genuinely answers are labelled `.noMatch` by retrieval, so the
/// gate silently stripped citations from correct, grounded replies.
static func reconcileCitations(_ refs: [Int], retrieval: RetrievalResult,
                                       question: String, body: String? = nil) -> [AskCitation] {
    guard !retrieval.isEmpty else { return [] }
    let byRef = Dictionary(uniqueKeysWithValues: retrieval.entries.map { ($0.ref, $0) })

    var seen = Set<Int>()
    var chosenRefs = refs.filter { byRef[$0] != nil && seen.insert($0).inserted }

    if let body {
        for ref in quotedRefs(in: body, retrieval: retrieval) where seen.insert(ref).inserted {
            chosenRefs.append(ref)
        }
    }

    if chosenRefs.isEmpty, !retrieval.isAmbient {
        chosenRefs = retrieval.entries.prefix(maxCitations).map(\.ref)
    }

    return chosenRefs.prefix(maxCitations).compactMap { ref in
        guard let entry = byRef[ref] else { return nil }
        return AskCitation(
            entryId: entry.id,
            entryDate: entry.date,
            excerpt: Self.previewExcerpt(entry.text, query: question)
        )
    }
}

/// Refs whose entry text the reply reproduces verbatim.
///
/// Matching is on a normalised form — case, curly quotes, dashes and
/// whitespace all vary between what the model emits and what is stored, and
/// a quote that survives the model's typography is still a quote. The
/// 30-character window is long enough that ordinary shared phrasing ("I have
/// not felt") does not trip it, short enough to catch a clipped quote.
static func quotedRefs(in body: String, retrieval: RetrievalResult) -> [Int] {
    let needle = citationFold(body)
    guard needle.count >= quoteWindow else { return [] }
    let windows = Array(needle)
    return retrieval.entries.compactMap { entry -> Int? in
        let hay = citationFold(entry.text)
        guard hay.count >= quoteWindow else { return nil }
        for i in 0...(windows.count - quoteWindow) {
            if hay.contains(String(windows[i..<(i + quoteWindow)])) { return entry.ref }
        }
        return nil
    }
}

// MARK: - Rendered citations (spec 050 R5)

/// What the citation sheet shows for a rendered reply. The entries the body
/// quotes or dates lead, in the order it shows them — a quoted entry's
/// excerpt is the exact quote the body shows, so the chip mirrors the reply
/// (spec 050 R6). `reconcileCitations` (the model's citedRefs, verbatim
/// matches, the reviewed top-N) is the backstop. Only a matched pack cites:
/// an ambient or miss turn shows none, whatever the model put in citedRefs.
static func citations(
    for rendered: RenderedReply,
    pack: EvidencePack,
    citedRefs: [Int],
    retrieval: RetrievalResult,
    question: String
) -> [AskCitation] {
    guard pack.state == .matched else { return [] }
    let byId = Dictionary(retrieval.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let quoted = Dictionary(rendered.chips.map { ($0.entryId, $0.quoteText) }, uniquingKeysWith: { first, _ in first })
    var seen = Set<UUID>()
    var chosen: [AskCitation] = []
    for id in rendered.citations where seen.insert(id).inserted {
        guard let entry = byId[id] else { continue }
        chosen.append(AskCitation(
            entryId: id,
            entryDate: entry.date,
            excerpt: quoted[id] ?? previewExcerpt(entry.text, query: question)
        ))
    }
    let backstop = reconcileCitations(citedRefs, retrieval: retrieval, question: question, body: rendered.body)
    for citation in backstop where seen.insert(citation.entryId).inserted {
        chosen.append(citation)
    }
    return Array(chosen.prefix(maxCitations))
}

private static let quoteWindow = 30

private static func citationFold(_ s: String) -> String {
    var t = s.lowercased()
    for (from, to) in [("\u{2019}", "'"), ("\u{2018}", "'"),
                       ("\u{201C}", "\""), ("\u{201D}", "\""),
                       ("\u{2014}", "-"), ("\u{2013}", "-")] {
        t = t.replacingOccurrences(of: from, with: to)
    }
    return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private static func previewExcerpt(_ text: String, query: String, window: Int = 120) -> String {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count > window else { return clean }
    // Center on the first query-term hit, else take the start.
    let terms = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 }
    let lower = clean.lowercased()
    var start = clean.startIndex
    for term in terms {
        if let r = lower.range(of: term) {
            start = r.lowerBound
            break
        }
    }
    let from = clean.index(start, offsetBy: -min(30, clean.distance(from: clean.startIndex, to: start)), limitedBy: clean.startIndex) ?? clean.startIndex
    let to = clean.index(from, offsetBy: window, limitedBy: clean.endIndex) ?? clean.endIndex
    var excerpt = String(clean[from..<to])
    if from != clean.startIndex { excerpt = "…" + excerpt }
    if to != clean.endIndex { excerpt += "…" }
    return excerpt
}
}
