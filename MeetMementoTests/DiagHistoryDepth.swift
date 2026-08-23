import XCTest
@testable import MeetMemento

/// Diagnostic: does a conversation degrade as it gets longer? Sweeps history
/// depth against a fixed follow-up and records latency, reply size, citation
/// count and violations at each depth.
final class DiagHistoryDepth: XCTestCase {

    private static let reps = 3

    /// A plausible thread that keeps circling the same journal material.
    private static func history(turns: Int) -> [ChatTurn] {
        let script: [(String, String)] = [
            ("What did I write about the hike?",
             "You went up Mount Tamalpais with Maya, starting in fog before it broke open at the top."),
            ("Tell me more about that.",
             "The climb took four hours, and Maya said it was the first time she had felt calm in weeks."),
            ("How was work around then?",
             "The Q3 launch had you on your third late night that week after the deadline moved."),
            ("Did I mention Priya?",
             "You snapped at her in standup over a staging bug that wasn't hers, and planned to apologise."),
            ("What happened after?",
             "Priya accepted the apology and made a joke about it on a quieter day."),
            ("And my sleep?",
             "You were waking at 3:40am, five nights running, and trying no screens after nine.")
        ]
        var out: [ChatTurn] = []
        for (u, a) in script.prefix(max(0, turns / 2)) {
            out.append(ChatTurn(role: .user, text: u))
            out.append(ChatTurn(role: .assistant, text: a))
        }
        return out
    }

    func test_historyDepth() async throws {
        // These diagnostics call the live model and tabulate errors as data
        // rather than failing, so on the merge lane — where the simulator
        // reports the model available but cannot generate — they burned
        // wall-clock logging 100% errors and still reported green. Same gate
        // the rest of the live tests use (spec 025 / IntelligenceServiceTests).
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI_ONLINE"] == "1",
                      "live-model diagnostic: not for the merge lane")

        let service = FoundationModelsIntelligenceService.shared
        let entries = Diag.corpus
        let question = "What keeps coming back across all of that?"

        var out = "# History depth (iOS 27, streaming path)\n\n"
        out += "Fixed follow-up: *\"\(question)\"* against a growing thread.\n\n"
        out += "| history turns | TTFT p50 | total p50 | mean chars | mean citations | violations |\n"
        out += "|---|---|---|---|---|---|\n"
        var detail = "\n---\n\n## Replies\n"

        for depth in [0, 2, 6, 12] {
            let hist = Self.history(turns: depth)
            var ttfts: [Double] = [], totals: [Double] = []
            var chars: [Double] = [], cites: [Double] = []
            var codes: Set<String> = []

            for rep in 1...Self.reps {
                let clock = ContinuousClock()
                let started = clock.now
                var ttft: Double?
                var body = ""
                var citations = 0
                var err: String?
                do {
                    for try await ev in service.askStream(question, history: hist,
                                                          entries: entries, images: []) {
                        switch ev {
                        case let .delta(soFar, _, _, _):
                            if ttft == nil { ttft = Diag.secs(clock.now - started) }
                            body = soFar
                        case let .final(r): body = r.body; citations = r.citations.count
                        }
                    }
                } catch { err = "\(error)" }
                let total = Diag.secs(clock.now - started)

                ttfts.append(ttft ?? total); totals.append(total)
                chars.append(Double(body.count)); cites.append(Double(citations))

                var vs = Diag.leaks(body)
                vs += Diag.ruleBreaks(body, isNotebookTurn: true, isCasual: false)
                vs += Diag.fabricatedQuotes(body, entries: entries)
                vs += Diag.boldNotTheirWords(body, entries: entries)
                for v in vs { codes.insert(v.code) }

                detail += "\n### depth \(depth), rep \(rep) — \(String(format: "%.1fs", total)), "
                detail += "\(body.count) ch, \(citations) cite(s)\n"
                if let err { detail += "**ERROR:** `\(err)`\n" }
                else {
                    detail += vs.isEmpty ? "clean\n" : "violations: " + vs.map { "`\($0.code)`" }.joined(separator: ", ") + "\n"
                    detail += "```\n\(body.prefix(900))\n```\n"
                }
                Diag.write(out + detail, "07-history.md")
            }

            out += "| \(depth) | \(String(format: "%.2f", Diag.pct(ttfts, 0.5))) "
            out += "| \(String(format: "%.2f", Diag.pct(totals, 0.5))) "
            out += "| \(String(format: "%.0f", chars.reduce(0,+) / Double(chars.count))) "
            out += "| \(String(format: "%.1f", cites.reduce(0,+) / Double(cites.count))) "
            out += "| \(codes.isEmpty ? "—" : codes.sorted().joined(separator: " ")) |\n"
            Diag.write(out + detail, "07-history.md")
        }

        Diag.write(out + detail, "07-history.md")
        print(out)
    }
}
