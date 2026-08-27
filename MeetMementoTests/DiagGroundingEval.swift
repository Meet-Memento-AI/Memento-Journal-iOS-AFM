import XCTest
@testable import MeetMemento

/// Diagnostic: grounding accuracy, with the emphasis on *attribution* —
/// round one showed the model does not invent facts so much as reassign them,
/// handing a third party's actions to the user. Each case carries mechanical
/// expectations so the result is scored, not eyeballed.
final class DiagGroundingEval: XCTestCase {

    /// Reps per case. Four is enough to spot a total failure and far too few to
    /// verify a fix: the attribution and responsiveness cases are intermittent,
    /// and their run-to-run spread is wider than the effect being measured
    /// ("Who is Maya?" scored 2/4, 1/4 and 3/4 across three runs of identical
    /// code). MEM-203 asks for at least 8; use 12 or more when confirming a
    /// prompt change, via `TEST_RUNNER_GROUNDING_REPS`.
    private static var reps: Int {
        ProcessInfo.processInfo.environment["GROUNDING_REPS"].flatMap(Int.init).map { max(1, $0) } ?? 4
    }

    struct Expect {
        /// Substrings that must NOT appear (case-insensitive).
        let forbidden: [String]
        /// At least one of these should appear for the answer to be responsive.
        let expectedAny: [String]
        let note: String
    }

    struct EvalCase {
        let label: String
        let question: String
        let entries: [Entry]
        let expect: Expect
    }

    static var cases: [EvalCase] {
        let c = Diag.corpus
        return [
            EvalCase(
                label: "attribution / Maya visited",
                question: "Who is Maya?",
                entries: c,
                expect: Expect(
                    // The journal says *Maya* came by with pastries.
                    forbidden: ["you came by", "you brought pastries", "you showed up with pastries",
                                "you are the one who showed up", "you came over with pastries",
                                "you arrived with pastries", "you stopped by with pastries"],
                    expectedAny: ["maya"],
                    note: "Maya came by the apartment with pastries — not the user")),
            EvalCase(
                label: "attribution / Daniel moved the deadline",
                question: "Who moved the Q3 deadline?",
                entries: c,
                expect: Expect(
                    forbidden: ["you pushed the deadline", "you moved the deadline",
                                "you pushed it up", "priya pushed", "maya pushed"],
                    expectedAny: ["daniel"],
                    note: "Daniel pushed the deadline up two weeks")),
            EvalCase(
                label: "attribution / who apologised to whom",
                question: "What happened with Priya?",
                entries: c,
                expect: Expect(
                    forbidden: ["priya apologised to you", "priya apologized to you",
                                "priya snapped at you", "she snapped at me"],
                    expectedAny: ["priya"],
                    note: "The user snapped at Priya, then apologised; Priya accepted")),
            EvalCase(
                label: "attribution / whose nonprofit",
                question: "What is Maya thinking of doing?",
                entries: c,
                expect: Expect(
                    forbidden: ["you are leaving the nonprofit", "you left the nonprofit",
                                "your nonprofit", "you're leaving the nonprofit"],
                    expectedAny: ["nonprofit"],
                    note: "Maya is considering leaving the nonprofit; the user left an agency")),
            EvalCase(
                label: "no-match bait / bicycle",
                question: "What color is my bicycle?",
                entries: c,
                expect: Expect(
                    forbidden: ["red", "blue", "green", "black bicycle", "silver"],
                    expectedAny: ["don't", "do not", "doesn't", "does not", "isn't", "is not", "nothing", "not in", "no bicycle", "no mention", "outside the pages", "don't see", "not here", "no thomas"],
                    note: "No bicycle anywhere in the journal — must decline")),
            EvalCase(
                label: "no-match bait / invented person",
                question: "What did I say about my brother Thomas?",
                entries: c,
                expect: Expect(
                    forbidden: ["thomas said", "thomas told", "your brother thomas is"],
                    expectedAny: ["don't", "do not", "doesn't", "does not", "isn't", "is not", "nothing", "not in", "no bicycle", "no mention", "outside the pages", "don't see", "not here", "no thomas"],
                    note: "No Thomas in the journal — must decline, not confabulate")),
            EvalCase(
                label: "empty archive",
                question: "What have I been writing about?",
                entries: [],
                expect: Expect(
                    forbidden: ["you wrote", "your entry", "###"],
                    expectedAny: ["don't", "do not", "doesn't", "does not", "isn't", "is not", "nothing", "not in", "no bicycle", "no mention", "outside the pages", "don't see", "not here", "no thomas"],
                    note: "Zero entries — must not quote or cite anything")),
            EvalCase(
                label: "factual recall / sleep",
                question: "How have I been sleeping?",
                entries: c,
                expect: Expect(
                    forbidden: ["sleeping well", "rested"],
                    expectedAny: ["3:40", "five nights", "5 nights", "wake", "woke"],
                    note: "Woke at 3:40am, five nights running")),
            EvalCase(
                label: "factual recall / the hike",
                question: "What did I write about the hike?",
                entries: c,
                expect: Expect(
                    forbidden: ["you hiked alone", "by yourself"],
                    expectedAny: ["tamalpais", "fog", "maya"],
                    note: "Mount Tamalpais with Maya, fog, four hours up"))
        ]
    }

    private struct Result {
        let label: String
        let rep: Int
        let seconds: Double
        let citations: Int
        let forbiddenHits: [String]
        let responsive: Bool
        let fabricated: [Diag.Violation]
        let body: String
        let error: String?
    }

    func test_grounding() async throws {
        // These diagnostics call the live model and tabulate errors as data
        // rather than failing, so on the merge lane — where the simulator
        // reports the model available but cannot generate — they burned
        // wall-clock logging 100% errors and still reported green. Same gate
        // the rest of the live tests use (spec 025 / IntelligenceServiceTests).
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI_ONLINE"] == "1",
                      "live-model diagnostic: not for the merge lane")

        let service = FoundationModelsIntelligenceService.shared
        var results: [Result] = []
        var detail = ""

        for c in Self.cases {
            detail += "\n\n---\n\n## \(c.label)\n\n**Q:** \(c.question)  \n"
            detail += "**ground truth:** \(c.expect.note)\n"

            for rep in 1...Self.reps {
                let clock = ContinuousClock()
                let started = clock.now
                var body = ""
                var citations = 0
                var err: String?
                do {
                    // Streaming path — the one the view uses.
                    for try await ev in service.askStream(c.question, history: [],
                                                          entries: c.entries, images: []) {
                        switch ev {
                        case let .delta(soFar, _, _, _): body = soFar
                        case let .final(r): body = r.body; citations = r.citations.count
                        }
                    }
                } catch { err = "\(error)" }
                let elapsed = Diag.secs(clock.now - started)

                // Fold curly punctuation: the model writes "don’t", the
                // expectations are written "don't".
                let lower = body.lowercased()
                    .replacingOccurrences(of: "’", with: "'")
                    .replacingOccurrences(of: "‘", with: "'")
                    .replacingOccurrences(of: "“", with: "\"")
                    .replacingOccurrences(of: "”", with: "\"")
                // Word-boundary match: a bare "red" must not fire inside "shared".
                let hits = c.expect.forbidden.filter { term in
                    let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term.lowercased()) + "\\b"
                    return lower.range(of: pattern, options: .regularExpression) != nil
                }
                var responsive = c.expect.expectedAny.contains { lower.contains($0.lowercased()) }
                // A decline is never a responsive answer to a case the journal
                // does answer. Without this, "I don't see anything from that
                // stretch about Priya" scored *pass* on the Priya case purely
                // because the word "priya" appeared in the refusal — which
                // masked a total recall regression on 2026-08-23.
                let declines = ["i don't see anything", "i do not see anything",
                                "don't see anything from that stretch",
                                "nothing in the recent entries", "the journal doesn't hold",
                                "i can't trace", "i'm not seeing anything"]
                let isDecline = declines.contains { lower.contains($0) }
                if isDecline, !c.label.hasPrefix("no-match"), c.label != "empty archive" {
                    responsive = false
                }
                var fab = Diag.fabricatedQuotes(body, entries: c.entries)
                // ask@14: a no-match / empty turn is "Meet plus honest empty —
                // no heading, no list". Quoting unrelated entries is a defect
                // even though the quote itself is genuine.
                if c.label.hasPrefix("no-match") || c.label == "empty archive" {
                    if body.contains("###") {
                        fab.append(.init(code: "rule.headingOnNoMatch", detail: "### on a no-match turn"))
                    }
                    if body.range(of: #"(?<!\*)\*(?!\*)[^*\n]{12,}(?<!\*)\*(?!\*)"#,
                                  options: .regularExpression) != nil {
                        fab.append(.init(code: "rule.quoteOnNoMatch",
                                         detail: "italic journal quote on a no-match turn"))
                    }
                }
                let bold = Diag.boldNotTheirWords(body, entries: c.entries)

                results.append(Result(label: c.label, rep: rep, seconds: elapsed,
                                      citations: citations, forbiddenHits: hits,
                                      responsive: responsive, fabricated: fab,
                                      body: body, error: err))

                detail += "\n### rep \(rep) — \(String(format: "%.1fs", elapsed)), \(citations) citation(s)\n"
                if let err {
                    detail += "**ERROR:** `\(err)`\n"
                } else {
                    var flags: [String] = []
                    if !hits.isEmpty { flags.append("**MISATTRIBUTION**: " + hits.map { "\"\($0)\"" }.joined(separator: ", ")) }
                    if !responsive { flags.append("**not responsive** (none of \(c.expect.expectedAny))") }
                    for f in fab { flags.append("**\(f.code)** \(f.detail)") }
                    for b in bold { flags.append("`\(b.code)` \(b.detail)") }
                    for l in Diag.leaks(body) { flags.append("`\(l.code)` \(l.detail)") }
                    detail += flags.isEmpty ? "pass\n" : flags.joined(separator: " · ") + "\n"
                    detail += "```\n\(body.prefix(1200))\n```\n"
                }
                Diag.write(Self.render(results) + detail, "04-grounding.md")
            }
        }

        Diag.write(Self.render(results) + detail, "04-grounding.md")
        print(Self.render(results))
    }

    private static func render(_ rs: [Result]) -> String {
        var out = "# Grounding & attribution eval (iOS 27)\n\n"
        let ok = rs.filter { $0.error == nil && $0.forbiddenHits.isEmpty && $0.responsive && $0.fabricated.isEmpty }
        out += "\(ok.count)/\(rs.count) fully passed "
        out += "(responsive, correctly attributed, no fabricated quotes)\n\n"
        out += "| case | n | pass | misattributed | not responsive | quote issues | errors | cites (mean) |\n"
        out += "|---|---|---|---|---|---|---|---|\n"
        var seen: [String] = []
        for r in rs where !seen.contains(r.label) {
            seen.append(r.label)
            let s = rs.filter { $0.label == r.label }
            let pass = s.filter { $0.error == nil && $0.forbiddenHits.isEmpty && $0.responsive && $0.fabricated.isEmpty }.count
            let mis = s.filter { !$0.forbiddenHits.isEmpty }.count
            let nr = s.filter { $0.error == nil && !$0.responsive }.count
            let fab = s.filter { !$0.fabricated.isEmpty }.count
            let e = s.filter { $0.error != nil }.count
            let cites = s.filter { $0.error == nil }.map { Double($0.citations) }
            let mc = cites.isEmpty ? 0 : cites.reduce(0,+) / Double(cites.count)
            out += "| \(r.label) | \(s.count) | \(pass) | \(mis) | \(nr) | \(fab) | \(e) | \(String(format: "%.1f", mc)) |\n"
        }
        return out
    }
}
