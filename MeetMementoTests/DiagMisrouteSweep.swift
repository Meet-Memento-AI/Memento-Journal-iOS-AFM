import XCTest
@testable import MeetMemento

/// Diagnostic: quantifies the two misroute classes the first routing sweep
/// exposed. Pure Swift, no model calls.
///
///  A. Off-domain questions phrased with "I"/"you"/"my" can never reach
///     `.offdomain` — rule 7 requires zero first/second person — so they fall
///     through to the rule-8 default and land on `notebook` (retrieval + 512 tok).
///  B. Journal requests phrased as an imperative ("summarise my week") are not
///     questions, so rule 8 sends them to `.share` → `companion`, where
///     retrieval is OFF and the journal cannot be read at all.
final class DiagMisrouteSweep: XCTestCase {

    /// Everyday off-domain asks. None are about the journal.
    static let offdomain: [String] = [
        "how do I fix a flat tyre?",
        "how do I make sourdough starter?",
        "can you write me a python script?",
        "what should I cook tonight?",
        "how do I get to the airport from here?",
        "what's a good gift for my mother?",
        "can you help me draft an email to my landlord?",
        "how do I convert celsius to fahrenheit?",
        "what's the best way for me to learn spanish?",
        "could you explain how mortgages work to me?",
        "what is the capital of France?",
        "who won the world cup in 2018?",
        "how tall is Everest?",
        "when did the Berlin wall fall?"
    ]

    /// Direct requests to read the journal, phrased as imperatives.
    static let journalImperatives: [String] = [
        "summarise my week",
        "summarize my month",
        "recap the last few days",
        "give me an overview of this month",
        "tell me about my week",
        "walk me through last week",
        "catch me up on how things have been",
        "remind me what's been going on",
        "show me what I wrote about the hike",
        "look back over the past few weeks with me",
        "what have I been writing about lately?",
        "what did I write about work?"
    ]

    private func row(_ text: String, history: Bool = false) -> (TurnType, ReplyChannel, Bool, Int) {
        let t = TurnClassifier.classify(text, hasHistory: history)
        let ch = ReplyChannel.resolve(turn: t, hasImages: false)
        let rag = ch.allowsRetrieval
        return (t, ch, rag, ch.maximumResponseTokens(retrievalRan: rag))
    }

    func test_misrouteSweep() throws {
        var out = "# Misroute sweep (pure, no model)\n\n"

        // MARK: A — off-domain
        out += "## A. Off-domain asks\n\n"
        out += "Rule 7 can only fire when the question contains **no** first/second person "
        out += "pronoun (`i, me, my, mine, myself, im, ive, id, you, your, we`). "
        out += "Anything phrased naturally with \"I\" or \"you\" falls through to the "
        out += "rule-8 default `isQuestion ? .journalQuery : .share`.\n\n"
        out += "| ask | has pronoun | turn | channel | retrieval | max tok |\n|---|---|---|---|---|---|\n"

        var offMisrouted = 0
        for q in Self.offdomain {
            let (t, ch, rag, tok) = row(q)
            let pronoun = q.lowercased().split { !$0.isLetter }.contains {
                ["i","me","my","mine","myself","im","ive","id","you","your","we"].contains(String($0))
            }
            let bad = t != .offdomain
            if bad { offMisrouted += 1 }
            out += "| \(q) | \(pronoun ? "yes" : "no") | \(bad ? "**\(t.rawValue)**" : t.rawValue) "
            out += "| \(ch.rawValue) | \(rag ? "**on**" : "off") | \(tok) |\n"
        }
        out += "\n**\(offMisrouted)/\(Self.offdomain.count) off-domain asks did not reach `.offdomain`.**\n"
        let withPronoun = Self.offdomain.filter { q in
            q.lowercased().split { !$0.isLetter }.contains {
                ["i","me","my","mine","myself","im","ive","id","you","your","we"].contains(String($0))
            }
        }
        let pronounMis = withPronoun.filter { TurnClassifier.classify($0, hasHistory: false) != .offdomain }
        out += "Of the \(withPronoun.count) phrased with a pronoun, **\(pronounMis.count)** misrouted; "
        let noPronoun = Self.offdomain.filter { !withPronoun.contains($0) }
        let noPronounMis = noPronoun.filter { TurnClassifier.classify($0, hasHistory: false) != .offdomain }
        out += "of the \(noPronoun.count) without one, \(noPronounMis.count) misrouted.\n"

        // MARK: B — journal imperatives
        out += "\n## B. Journal requests phrased as imperatives\n\n"
        out += "`.share` → `companion` has **retrieval off** and a 128-token ceiling, "
        out += "so these are answered without the journal being read at all.\n\n"
        out += "| ask | turn | channel | retrieval | max tok |\n|---|---|---|---|---|\n"

        var blind = 0
        for q in Self.journalImperatives {
            let (t, ch, rag, tok) = row(q)
            if !rag { blind += 1 }
            out += "| \(q) | \(t.rawValue) | \(ch.rawValue) | \(rag ? "on" : "**OFF**") | \(tok) |\n"
        }
        out += "\n**\(blind)/\(Self.journalImperatives.count) journal requests run with retrieval OFF.**\n"

        // MARK: C — lexicon over-trigger
        out += "\n## C. `journalWords` over-trigger\n\n"
        out += "Rule 5 matches a bare token against "
        out += "`journal, journals, entry, entries, wrote, written, write, logged, log, noted, notes, diary`. "
        out += "Generic uses of those words pull unrelated turns into the notebook channel:\n\n"
        out += "| ask | turn | channel | retrieval | max tok |\n|---|---|---|---|---|\n"
        for q in ["write me a python script",
                  "I need to log my hours for work",
                  "can you take notes on this?",
                  "write a haiku about rain",
                  "I forgot to log my run today",
                  "make a note to call the dentist"] {
            let (t, ch, rag, tok) = row(q)
            out += "| \(q) | \(t.rawValue) | \(ch.rawValue) | \(rag ? "**on**" : "off") | \(tok) |\n"
        }

        Diag.write(out, "05-misroute.md")
        print(out)
    }
}
