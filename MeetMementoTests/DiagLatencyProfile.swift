import XCTest
@testable import MeetMemento

/// Diagnostic: where the wait actually goes on the streaming path AIChatView
/// uses — time-to-first-token vs total, per channel, with percentiles, plus
/// how TTFT scales with journal size and whether prewarm buys anything.
///
/// Run on a physical Apple Intelligence device (not the merge lane). Open Chat
/// first, or rely on the per-scenario `prewarmConversation` below so the
/// recipe pool is filled before TTFT is sampled.
///
/// Spec 029 R2 gates to read off the table:
/// - phatic/continuer: version `chat-light@4`, high speculative hit rate, TTFT p50 < 1.2 s
/// - companion/share: version `chat-companion@1`, TTFT down vs ask-core@16 prefill
/// - spoken companion / spoken no-RAG follow-up: `chat-companion@1`, 80 tok, LightAskAnswer
/// - notebook: version `ask-core@16`, 512 typed / 256 spoken; do not raise caps
///
/// Size sweep is empty / ~50 / fixture 262 / ~500+. Attribute
/// `retrieve` vs `ttft` vs `stream` from `LiveTurnClock.snapshot()`.
final class DiagLatencyProfile: XCTestCase {

    private static let reps = 5

    private struct Run {
        let ttft: Double
        let total: Double
        let deltas: Int
        let chars: Int
        let promptVersion: String
        let speculativeHit: Bool?
        let channel: String
        let retrieve: Double
        let ttftStage: Double
        let stream: Double
        let firstDeltaUnder1s: Bool
    }

    private func measure(_ q: String, history: [ChatTurn], entries: [Entry], spoken: Bool = false) async -> Run {
        let service = FoundationModelsIntelligenceService.shared
        LiveTurnClock.shared.resetForTesting()
        LiveTurnClock.shared.beginTurn()
        EntryRetriever.warmEmbeddings(entries, generation: 1)
        let clock = ContinuousClock()
        let started = clock.now
        var ttft: Double?
        var deltas = 0
        var body = ""
        do {
            for try await ev in service.askStream(q, history: history, entries: entries, images: [], spoken: spoken) {
                switch ev {
                case let .delta(soFar, _, _, _, _):
                    if ttft == nil { ttft = Diag.secs(clock.now - started) }
                    deltas += 1; body = soFar
                case let .final(r): body = r.body
                }
            }
        } catch { /* recorded as a zero-char run */ }
        let total = Diag.secs(clock.now - started)
        let stages = LiveTurnClock.shared.snapshot()
        LiveTurnClock.shared.resetForTesting()
        let perf = service.consumeLastTurnPerf()
        let retrieve = stages.duration(of: .prepRetrieve).map(Diag.secs) ?? 0
        let ttftStage = stages.duration(of: .modelFirstToken).map(Diag.secs) ?? (ttft ?? total)
        let stream = stages.duration(of: .modelStream).map(Diag.secs) ?? 0
        return Run(
            ttft: ttft ?? total,
            total: total,
            deltas: deltas,
            chars: body.count,
            promptVersion: perf?.promptVersion ?? "—",
            speculativeHit: perf?.speculativeHit,
            channel: perf?.channel ?? "—",
            retrieve: retrieve,
            ttftStage: ttftStage,
            stream: stream,
            firstDeltaUnder1s: (ttft ?? total) <= 1.0
        )
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
        let companionHistory = [
            ChatTurn(role: .user, text: "I had a rough day at work today"),
            ChatTurn(role: .assistant, text: "How did that feel?")
        ]
        let journalFollowHistory = [
            ChatTurn(role: .user, text: "What did I write about the hike?"),
            ChatTurn(role: .assistant, text: "You went up Mount Tamalpais with Maya.")
        ]
        let scenarios: [(String, String, [ChatTurn], [Entry], Bool)] = [
            ("phatic (chat-light@4, 80 tok)", "Hey", [], c, false),
            ("meta (chat-companion@1, 128 tok)", "What can you do?", [], c, false),
            ("companion / share (chat-companion@1, 128 tok)", "I had a rough day at work today", [], c, false),
            ("spoken companion (chat-companion@1, 80 tok)", "I had a rough day at work today", [], c, true),
            ("spoken no-RAG follow-up (companion, 80 tok)", "it was actually pretty heavy", companionHistory, c, true),
            ("notebook (ask-core@16, RAG, 512 tok)", "What have I been writing about lately?", [], c, false),
            ("thread / follow-up (journal-anchored)", "Tell me more about that.", journalFollowHistory, c, false)
        ]

        out += "\n## Per-channel distribution (n=\(Self.reps))\n\n"
        out += "| scenario | prompt | hit rate | TTFT p50 | TTFT p95 | total p50 | mean chars |\n"
        out += "|---|---|---|---|---|---|---|\n"

        var rawTTFT: [String: [Double]] = [:]
        for (label, q, hist, entries, spoken) in scenarios {
            FoundationModelsIntelligenceService.shared.prewarmConversation(history: hist)
            try? await Task.sleep(for: .seconds(2))
            var runs: [Run] = []
            for _ in 1...Self.reps {
                runs.append(await measure(q, history: hist, entries: entries, spoken: spoken))
                Diag.write(out, "03-latency.md")
            }
            let t = runs.map(\.ttft), tot = runs.map(\.total)
            rawTTFT[label] = t
            let meanChars = Double(runs.map(\.chars).reduce(0, +)) / Double(runs.count)
            let hits = runs.compactMap(\.speculativeHit)
            let hitRate = hits.isEmpty ? "—" : String(format: "%.0f%%", 100 * Double(hits.filter { $0 }.count) / Double(hits.count))
            let version = runs.last?.promptVersion ?? "—"
            out += "| \(label) | \(version) | \(hitRate) "
            out += "| \(String(format: "%.2f", Diag.pct(t, 0.5))) "
            out += "| \(String(format: "%.2f", Diag.pct(t, 0.95))) "
            out += "| \(String(format: "%.2f", Diag.pct(tot, 0.5))) "
            out += "| \(String(format: "%.0f", meanChars)) |\n"
            Diag.write(out, "03-latency.md")
        }

        // MARK: context scaling — empty / ~50 / fixture 262 / ~500+
        out += "\n## TTFT vs journal size (notebook turn, warm embeddings, n=3)\n\n"
        out += "| entries | retrieve p50 | ttft p50 | stream p50 | total p50 | first-delta ≤1s | version | hit |\n"
        out += "|---|---|---|---|---|---|---|---|\n"
        let sizes: [Int] = [0, 50, 262, 500]
        for n in sizes {
            let entries: [Entry]
            if n == 0 {
                entries = []
            } else if n >= 262, let persona = try? ChatEvalCorpus.personaCorpus().entries, !persona.isEmpty {
                entries = n <= persona.count
                    ? Array(persona.prefix(n))
                    : persona + Diag.scaled(n - persona.count)
            } else {
                entries = Diag.scaled(n)
            }
            var runs: [Run] = []
            for _ in 1...3 {
                runs.append(await measure("What have I been writing about lately?", history: [], entries: entries))
                Diag.write(out, "03-latency.md")
            }
            let t = runs.map(\.ttft), tot = runs.map(\.total)
            let retrieve = runs.map(\.retrieve), stream = runs.map(\.stream)
            let under1s = runs.filter(\.firstDeltaUnder1s).count
            let version = runs.last?.promptVersion ?? "—"
            let hits = runs.compactMap(\.speculativeHit)
            let hitRate = hits.isEmpty ? "—" : String(
                format: "%.0f%%", 100 * Double(hits.filter { $0 }.count) / Double(hits.count)
            )
            out += "| \(n) | \(String(format: "%.3f", Diag.pct(retrieve, 0.5))) "
            out += "| \(String(format: "%.2f", Diag.pct(t, 0.5))) "
            out += "| \(String(format: "%.2f", Diag.pct(stream, 0.5))) "
            out += "| \(String(format: "%.2f", Diag.pct(tot, 0.5))) "
            out += "| \(under1s)/\(runs.count) | \(version) | \(hitRate) |\n"
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
