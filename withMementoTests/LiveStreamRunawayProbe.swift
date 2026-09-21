import XCTest
@testable import withMemento

/// Throwaway probe: the empty-archive runaway (19s, `<ctrl…>` tokens, ~10
/// concatenated replies, invented journal quotes) appeared on `askStream` but
/// did NOT reproduce on the one-shot `ask`. This isolates the streaming path.
final class LiveStreamRunawayProbe: XCTestCase {

    /// Was an absolute path into one agent session's scratchpad on one
    /// machine; that directory does not exist here, so the final `try`
    /// write threw and failed this probe. Routed through `Diag.outDir`,
    /// which creates the directory and reports a failure instead of
    /// throwing (046 R1: no more silent or spurious output paths).
    static let outFile = "runaway.md"

    private static let reps = 4

    func test_streamRunaway() async throws {
        // These diagnostics call the live model and tabulate errors as data
        // rather than failing, so on the merge lane — where the simulator
        // reports the model available but cannot generate — they burned
        // wall-clock logging 100% errors and still reported green. Same gate
        // the rest of the live tests use (spec 025 / IntelligenceServiceTests).
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI_ONLINE"] == "1",
                      "live-model diagnostic: not for the merge lane")

        let service = FoundationModelsIntelligenceService.shared
        var out = "# Empty-archive runaway — streaming path (\(Self.reps)x)\n\n"
        out += "| rep | total | deltas | chars | ctrl tokens | citedRefs leak | invented ### |\n|---|---|---|---|---|---|---|\n"
        var bodies: [String] = []

        for rep in 1...Self.reps {
            let clock = ContinuousClock()
            let started = clock.now
            var body = ""
            var deltas = 0
            var err: String?
            do {
                for try await ev in service.askStream("What have I been writing about?",
                                                      history: [], entries: [], images: []) {
                    switch ev {
                    case let .delta(soFar, _, _, _, _): deltas += 1; body = soFar
                    case let .final(r): body = r.body
                    }
                }
            } catch { err = "\(error)" }
            let total = clock.now - started
            let s = Double(total.components.seconds) + Double(total.components.attoseconds) * 1e-18

            let ctrlCount = body.components(separatedBy: "<ctrl").count - 1
            let refLeak = body.contains("citedRefs")
            let invented = body.contains("###")
            out += "| \(rep) | \(String(format: "%.1fs", s)) | \(deltas) | \(body.count) "
            out += "| \(ctrlCount) | \(refLeak) | \(invented) |\n"
            bodies.append("### rep \(rep) (\(String(format: "%.1fs", s)), \(body.count) ch)"
                          + (err.map { "\nERROR: \($0)" } ?? "\n```\n\(body.prefix(1400))\n```"))
            Diag.write((out + "\n" + bodies.joined(separator: "\n\n")), Self.outFile)
        }
        Diag.write((out + "\n" + bodies.joined(separator: "\n\n")), Self.outFile)
        print(out)
    }
}
