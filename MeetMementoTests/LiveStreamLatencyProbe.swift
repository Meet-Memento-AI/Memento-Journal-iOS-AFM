import XCTest
@testable import MeetMemento

/// Throwaway probe (not a regression test): measures the latency the user
/// actually feels in AIChatView — time-to-first-token on the streaming path —
/// separately from total completion time.
///
/// `LiveChatQualityProbe` measures the one-shot `ask`; the real view uses
/// `askStream`, so total time there is not what the user waits for.
final class LiveStreamLatencyProbe: XCTestCase {

    static let outPath = "/private/tmp/claude-501/-Users-sebastianmendo-Swift-projects-Memento-AI-MeetMemento/094f3be1-69b0-4026-bb20-1aad71a89c42/scratchpad/latency.md"

    private static func ms(_ d: Duration) -> String {
        let s = Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
        return String(format: "%.0f ms", s * 1000)
    }

    struct Sample {
        let label: String
        let question: String
        let corpus: [Entry]
        let history: [ChatTurn]
    }

    func test_streamLatency() async throws {
        // These diagnostics call the live model and tabulate errors as data
        // rather than failing, so on the merge lane — where the simulator
        // reports the model available but cannot generate — they burned
        // wall-clock logging 100% errors and still reported green. Same gate
        // the rest of the live tests use (spec 025 / IntelligenceServiceTests).
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI_ONLINE"] == "1",
                      "live-model diagnostic: not for the merge lane")

        let service = FoundationModelsIntelligenceService.shared
        let corpus = Diag.corpus
        var out = "# Streaming latency probe (AIChatView path)\n\n"
        out += "availability: \(String(describing: await service.availability()))\n\n"
        out += "| turn | grounded | TTFT | total | deltas | chars | chars/s after first |\n"
        out += "|---|---|---|---|---|---|---|\n"

        let samples: [Sample] = [
            Sample(label: "cold / casual", question: "Hey", corpus: corpus, history: []),
            Sample(label: "warm / casual", question: "Hi there", corpus: corpus, history: []),
            Sample(label: "grounded / broad", question: "What have I been writing about lately?",
                   corpus: corpus, history: []),
            Sample(label: "grounded / entity", question: "Who is Maya?", corpus: corpus, history: []),
            Sample(label: "grounded / single entry", question: "What did I write about work?",
                   corpus: [corpus[1]], history: []),
            Sample(label: "no-match bait", question: "What color is my bicycle?",
                   corpus: corpus, history: []),
            Sample(label: "follow-up (2 turns history)", question: "Tell me more about that.",
                   corpus: corpus,
                   history: [ChatTurn(role: .user, text: "What did I write about the hike?"),
                             ChatTurn(role: .assistant, text: "You went up Mount Tamalpais with Maya.")]),
            Sample(label: "empty archive", question: "What have I been writing about?",
                   corpus: [], history: [])
        ]

        var details = "\n---\n\n## Per-turn detail\n"

        for sample in samples {
            let clock = ContinuousClock()
            let started = clock.now
            var ttft: Duration?
            var deltaCount = 0
            var finalChars = 0
            var body = ""
            var errorText: String?
            var grounded = "—"

            do {
                for try await event in service.askStream(sample.question, history: sample.history,
                                                         entries: sample.corpus, images: []) {
                    switch event {
                    case let .delta(bodySoFar, _, _, reviewed):
                        if ttft == nil {
                            ttft = clock.now - started
                            grounded = reviewed.isEmpty ? "no" : "yes(\(reviewed.count))"
                        }
                        deltaCount += 1
                        body = bodySoFar
                    case let .final(result):
                        body = result.body
                        finalChars = result.body.count
                        grounded = result.citations.isEmpty ? grounded : "yes(\(result.citations.count))"
                    }
                }
            } catch {
                errorText = "\(error)"
            }

            let total = clock.now - started
            if finalChars == 0 { finalChars = body.count }
            let ttftD = ttft ?? total
            let tailSeconds = max(0.001, seconds(total) - seconds(ttftD))
            let rate = Double(finalChars) / tailSeconds

            out += "| \(sample.label) | \(grounded) | \(Self.ms(ttftD)) | \(Self.ms(total)) "
            out += "| \(deltaCount) | \(finalChars) | \(String(format: "%.0f", rate)) |\n"

            details += "\n### \(sample.label)\n**Q:** \(sample.question)  \n"
            details += "TTFT \(Self.ms(ttftD)) · total \(Self.ms(total)) · \(deltaCount) deltas · \(finalChars) chars\n\n"
            if let errorText {
                details += "**ERROR:** `\(errorText)`\n"
            } else {
                details += "```\n\(body)\n```\n"
            }

            try? (out + details).write(toFile: Self.outPath, atomically: true, encoding: .utf8)
        }

        try (out + details).write(toFile: Self.outPath, atomically: true, encoding: .utf8)
        print(out + details)
    }

    private func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
    }
}
