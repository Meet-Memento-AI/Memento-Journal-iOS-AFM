import XCTest
@testable import MeetMemento

/// Throwaway probe: re-runs the three highest-severity defects the streaming
/// latency probe surfaced, N times each, to separate a one-off sample from a
/// reproducible bug.
///
///  1. empty archive → runaway decode with `<ctrl…>` tokens + invented quotes
///  2. "Who is Maya?" → subject swap (Maya's action attributed to the user)
///  3. casual greeting → unfilled `[Name]` placeholder / invented name
final class LiveHallucinationRepeatProbe: XCTestCase {

    static let outPath = "/private/tmp/claude-501/-Users-sebastianmendo-Swift-projects-Memento-AI-MeetMemento/094f3be1-69b0-4026-bb20-1aad71a89c42/scratchpad/repeat.md"

    private static let reps = 3

    private func flags(_ body: String) -> [String] {
        var hits: [String] = []
        if body.contains("citedRefs") { hits.append("citedRefs-leak") }
        if body.contains("<ctrl") { hits.append("ctrl-token") }
        if body.range(of: #"\[[A-Z][a-z]+\]"#, options: .regularExpression) != nil { hits.append("name-placeholder") }
        if body.count > 1200 { hits.append("runaway(\(body.count)ch)") }
        if body.lowercased().hasPrefix("you wrote") { hits.append("banned-opener") }
        if body.contains("*italic*") { hits.append("literal-italic") }
        if !body.contains("?") { hits.append("no-Open-question") }
        return hits
    }

    func test_repeat() async throws {
        // These diagnostics call the live model and tabulate errors as data
        // rather than failing, so on the merge lane — where the simulator
        // reports the model available but cannot generate — they burned
        // wall-clock logging 100% errors and still reported green. Same gate
        // the rest of the live tests use (spec 025 / IntelligenceServiceTests).
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI_ONLINE"] == "1",
                      "live-model diagnostic: not for the merge lane")

        let service = FoundationModelsIntelligenceService.shared
        let corpus = Diag.corpus
        var out = "# Reproducibility probe (\(Self.reps)x each)\n\n"

        let cases: [(String, String, [Entry])] = [
            ("empty archive", "What have I been writing about?", []),
            ("entity recall", "Who is Maya?", corpus),
            ("casual greeting", "Hey", corpus)
        ]

        for (label, question, entries) in cases {
            out += "\n## \(label) — \"\(question)\"\n\n"
            for rep in 1...Self.reps {
                let clock = ContinuousClock()
                let started = clock.now
                var body = ""
                var err: String?
                do {
                    let r = try await service.ask(question, history: [], entries: entries, images: [])
                    body = r.body
                } catch { err = "\(error)" }
                let total = clock.now - started
                let s = Double(total.components.seconds) + Double(total.components.attoseconds) * 1e-18

                out += "### rep \(rep) — \(String(format: "%.1fs", s)), \(body.count) chars\n"
                if let err {
                    out += "ERROR: `\(err)`\n\n"
                } else {
                    let f = flags(body)
                    out += "flags: \(f.isEmpty ? "none" : f.joined(separator: ", "))\n\n"
                    out += "```\n\(body.prefix(900))\n```\n\n"
                }
                try? out.write(toFile: Self.outPath, atomically: true, encoding: .utf8)
            }
        }
        try out.write(toFile: Self.outPath, atomically: true, encoding: .utf8)
        print(out)
    }
}
