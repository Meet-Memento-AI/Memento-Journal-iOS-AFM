import XCTest
@testable import MeetMemento

/// Diagnostic: where the wait actually goes on the streaming path AIChatView
/// uses — time-to-first-token vs total, per channel, with percentiles, plus
/// how TTFT scales with journal size and whether prewarm buys anything.
final class DiagLatencyProfile: XCTestCase {

    private static let reps = 5

    private struct Run {
        let ttft: Double
        let total: Double
        let deltas: Int
        let chars: Int
    }

    private func measure(_ q: String, history: [ChatTurn], entries: [Entry]) async -> Run {
        let service = FoundationModelsIntelligenceService.shared
        let clock = ContinuousClock()
        let started = clock.now
        var ttft: Double?
        var deltas = 0
        var body = ""
        do {
            for try await ev in service.askStream(q, history: history, entries: entries, images: []) {
                switch ev {
                case let .delta(soFar, _, _, _):
                    if ttft == nil { ttft = Diag.secs(clock.now - started) }
                    deltas += 1; body = soFar
                case let .final(r): body = r.body
                }
            }
        } catch { /* recorded as a zero-char run */ }
        let total = Diag.secs(clock.now - started)
        return Run(ttft: ttft ?? total, total: total, deltas: deltas, chars: body.count)
    }

    func test_latencyProfile() async throws {
        // These diagnostics call the live model and tabulate errors as data
        // rather than failing, so on the merge lane — where the simulator
        // reports the model available but cannot generate — they burned
        // wall-clock logging 100% errors and still reported green. Same gate
        // the rest of the live tests use (spec 025 / IntelligenceServiceTests).
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI_ONLINE"] == "1",
                      "live-model diagnostic: not for the merge lane")

        let c = Diag.corpus
        var out = "# Latency profile (iOS 27, streaming path)\n\n"

        // MARK: prewarm effect
        out += "## Prewarm\n\n"
        let coldRun = await measure("Hey", history: [], entries: c)
        FoundationModelsIntelligenceService.shared.prewarm()
        try? await Task.sleep(for: .seconds(2))
        let warmRun = await measure("Hi there", history: [], entries: c)
        out += "| condition | TTFT s | total s |\n|---|---|---|\n"
        out += "| first call of the process | \(String(format: "%.2f", coldRun.ttft)) | \(String(format: "%.2f", coldRun.total)) |\n"
        out += "| after prewarm() + 2s | \(String(format: "%.2f", warmRun.ttft)) | \(String(format: "%.2f", warmRun.total)) |\n"

        // MARK: per-channel distribution
        let scenarios: [(String, String, [ChatTurn], [Entry])] = [
            ("phatic (chat-light@4, 80 tok)", "Hey", [], c),
            ("meta (ask@14, 128 tok)", "What can you do?", [], c),
            ("companion / share (128 tok)", "I had a rough day at work today", [], c),
            ("notebook (ask@14, RAG, 512 tok)", "What have I been writing about lately?", [], c),
            ("thread / follow-up", "Tell me more about that.",
             [ChatTurn(role: .user, text: "What did I write about the hike?"),
              ChatTurn(role: .assistant, text: "You went up Mount Tamalpais with Maya.")], c)
        ]

        out += "\n## Per-channel distribution (n=\(Self.reps))\n\n"
        out += "| scenario | TTFT p50 | TTFT p95 | TTFT max | total p50 | total p95 | mean chars | chars/s |\n"
        out += "|---|---|---|---|---|---|---|---|\n"

        var rawTTFT: [String: [Double]] = [:]
        for (label, q, hist, entries) in scenarios {
            var runs: [Run] = []
            for _ in 1...Self.reps {
                runs.append(await measure(q, history: hist, entries: entries))
                Diag.write(out, "03-latency.md")
            }
            let t = runs.map(\.ttft), tot = runs.map(\.total)
            rawTTFT[label] = t
            let meanChars = Double(runs.map(\.chars).reduce(0, +)) / Double(runs.count)
            let tail = max(0.001, (tot.reduce(0,+) - t.reduce(0,+)) / Double(runs.count))
            out += "| \(label) | \(String(format: "%.2f", Diag.pct(t, 0.5))) "
            out += "| \(String(format: "%.2f", Diag.pct(t, 0.95))) | \(String(format: "%.2f", t.max() ?? 0)) "
            out += "| \(String(format: "%.2f", Diag.pct(tot, 0.5))) | \(String(format: "%.2f", Diag.pct(tot, 0.95))) "
            out += "| \(String(format: "%.0f", meanChars)) | \(String(format: "%.0f", meanChars / tail)) |\n"
            Diag.write(out, "03-latency.md")
        }

        // MARK: context scaling — does a bigger journal cost TTFT?
        out += "\n## TTFT vs journal size (notebook turn, n=3)\n\n"
        out += "| entries in store | TTFT p50 | total p50 | mean chars |\n|---|---|---|---|\n"
        for n in [1, 5, 20, 50] {
            let entries = Diag.scaled(n)
            var runs: [Run] = []
            for _ in 1...3 {
                runs.append(await measure("What have I been writing about lately?", history: [], entries: entries))
                Diag.write(out, "03-latency.md")
            }
            let t = runs.map(\.ttft), tot = runs.map(\.total)
            let meanChars = Double(runs.map(\.chars).reduce(0, +)) / Double(runs.count)
            out += "| \(n) | \(String(format: "%.2f", Diag.pct(t, 0.5))) "
            out += "| \(String(format: "%.2f", Diag.pct(tot, 0.5))) | \(String(format: "%.0f", meanChars)) |\n"
            Diag.write(out, "03-latency.md")
        }

        // MARK: raw samples
        out += "\n## Raw TTFT samples (seconds)\n\n"
        for (label, xs) in rawTTFT.sorted(by: { $0.key < $1.key }) {
            out += "- **\(label)** — " + xs.map { String(format: "%.2f", $0) }.joined(separator: ", ") + "\n"
        }

        Diag.write(out, "03-latency.md")
        print(out)
    }
}
