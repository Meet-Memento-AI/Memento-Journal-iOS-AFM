import XCTest
@testable import MeetMemento

/// Diagnostic: scores every reply for scaffolding leaks, ask@14 rule breaks,
/// fabricated quotes and runaway decode — across turn types, and A/B across
/// the streaming path (what AIChatView uses) vs the one-shot `ask`.
final class DiagOutputIntegrity: XCTestCase {

    private static let reps = 3

    struct Probe {
        let label: String
        let question: String
        let history: [ChatTurn]
        let entries: [Entry]
        let casual: Bool
    }

    static var probes: [Probe] {
        let c = Diag.corpus
        return [
            Probe(label: "phatic / greeting", question: "Hey", history: [], entries: c, casual: true),
            Probe(label: "meta / about app", question: "What can you do?", history: [], entries: c, casual: false),
            Probe(label: "notebook / broad", question: "What have I been writing about lately?",
                  history: [], entries: c, casual: false),
            Probe(label: "notebook / entity", question: "Who is Maya?", history: [], entries: c, casual: false),
            Probe(label: "notebook / topic", question: "What did I write about work?",
                  history: [], entries: c, casual: false),
            Probe(label: "notebook / no match", question: "What color is my bicycle?",
                  history: [], entries: c, casual: false),
            Probe(label: "notebook / empty archive", question: "What have I been writing about?",
                  history: [], entries: [], casual: false),
            Probe(label: "thread / follow-up", question: "Tell me more about that.",
                  history: [ChatTurn(role: .user, text: "What did I write about the hike?"),
                            ChatTurn(role: .assistant, text: "You went up Mount Tamalpais with Maya.")],
                  entries: c, casual: false),
            Probe(label: "share / statement", question: "I had a rough day at work today",
                  history: [], entries: c, casual: false),
            Probe(label: "offdomain / redirect", question: "What is the capital of France?",
                  history: [], entries: c, casual: false)
        ]
    }

    private struct Sample {
        let probe: String
        let path: String
        let rep: Int
        let seconds: Double
        let chars: Int
        let citations: Int
        let promptVersion: String
        let violations: [Diag.Violation]
        let body: String
        let error: String?
    }

    func test_integrityMatrix() async throws {
        // These diagnostics call the live model and tabulate errors as data
        // rather than failing, so on the merge lane — where the simulator
        // reports the model available but cannot generate — they burned
        // wall-clock logging 100% errors and still reported green. Same gate
        // the rest of the live tests use (spec 025 / IntelligenceServiceTests).
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI_ONLINE"] == "1",
                      "live-model diagnostic: not for the merge lane")

        let service = FoundationModelsIntelligenceService.shared
        var samples: [Sample] = []
        var detail = ""

        for probe in Self.probes {
            let turn = TurnClassifier.classify(probe.question, hasHistory: !probe.history.isEmpty)
            let channel = ReplyChannel.resolve(turn: turn, hasImages: false)
            let cap = channel.maximumResponseTokens(retrievalRan: channel.allowsRetrieval)
            let isNotebook = channel == .notebook

            detail += "\n\n---\n\n## \(probe.label)\n\n"
            detail += "**Q:** \(probe.question)  \n"
            detail += "route: `\(turn.rawValue)` → `\(channel.rawValue)` "
            detail += "(\(channel.usesLightPrompt ? "chat-light@4" : "ask@14"), cap \(cap) tok, "
            detail += "temp \(String(format: "%.1f", channel.temperature(retrievalRan: channel.allowsRetrieval))))\n"

            for path in ["stream", "oneshot"] {
                for rep in 1...Self.reps {
                    let clock = ContinuousClock()
                    let started = clock.now
                    var body = ""
                    var citations = 0
                    var version = "?"
                    var err: String?

                    do {
                        if path == "stream" {
                            for try await ev in service.askStream(probe.question, history: probe.history,
                                                                  entries: probe.entries, images: []) {
                                switch ev {
                                case let .delta(soFar, _, _, _): body = soFar
                                case let .final(r):
                                    body = r.body; citations = r.citations.count; version = r.promptVersion
                                }
                            }
                        } else {
                            let r = try await service.ask(probe.question, history: probe.history,
                                                          entries: probe.entries, images: [])
                            body = r.body; citations = r.citations.count; version = r.promptVersion
                        }
                    } catch {
                        err = "\(error)"
                    }

                    let elapsed = Diag.secs(clock.now - started)
                    var vs: [Diag.Violation] = []
                    if err == nil {
                        vs += Diag.leaks(body)
                        vs += Diag.ruleBreaks(body, isNotebookTurn: isNotebook, isCasual: probe.casual)
                        vs += Diag.fabricatedQuotes(body, entries: probe.entries)
                        vs += Diag.boldNotTheirWords(body, entries: probe.entries)
                        vs += Diag.runaway(body, capTokens: cap)
                    }

                    samples.append(Sample(probe: probe.label, path: path, rep: rep,
                                          seconds: elapsed, chars: body.count, citations: citations,
                                          promptVersion: version, violations: vs, body: body, error: err))

                    detail += "\n### \(path) rep \(rep) — \(String(format: "%.1fs", elapsed)), "
                    detail += "\(body.count) ch, \(citations) citation(s), `\(version)`\n"
                    if let err {
                        detail += "**ERROR:** `\(err)`\n"
                    } else {
                        detail += vs.isEmpty ? "clean\n"
                            : "**violations:** " + vs.map { "`\($0.code)` (\($0.detail))" }.joined(separator: ", ") + "\n"
                        detail += "```\n\(body.prefix(1500))\n```\n"
                    }
                    Diag.write(Self.render(samples) + detail, "02-integrity.md")
                }
            }
        }

        Diag.write(Self.render(samples) + detail, "02-integrity.md")
        print(Self.render(samples))
    }

    private static func render(_ samples: [Sample]) -> String {
        var out = "# Output integrity matrix (iOS 27)\n\n"
        let done = samples.count
        let errs = samples.filter { $0.error != nil }.count
        let dirty = samples.filter { !$0.violations.isEmpty }.count
        out += "\(done) generations · \(errs) hard errors · "
        out += "\(dirty) carrying at least one violation\n\n"

        // Stream vs one-shot
        out += "## Streaming vs one-shot\n\n| path | n | clean | violations | errors | mean s |\n|---|---|---|---|---|---|\n"
        for path in ["stream", "oneshot"] {
            let s = samples.filter { $0.path == path }
            guard !s.isEmpty else { continue }
            let clean = s.filter { $0.violations.isEmpty && $0.error == nil }.count
            let e = s.filter { $0.error != nil }.count
            let mean = s.map(\.seconds).reduce(0, +) / Double(s.count)
            out += "| \(path) | \(s.count) | \(clean) | \(s.count - clean - e) | \(e) | \(String(format: "%.1f", mean)) |\n"
        }

        // Violation frequency
        var freq: [String: Int] = [:]
        for s in samples { for v in s.violations { freq[v.code, default: 0] += 1 } }
        if !freq.isEmpty {
            out += "\n## Violations by code\n\n| code | count | share of generations |\n|---|---|---|\n"
            for (code, n) in freq.sorted(by: { $0.value > $1.value }) {
                out += "| `\(code)` | \(n) | \(String(format: "%.0f%%", Double(n) / Double(max(1, done)) * 100)) |\n"
            }
        }

        // Per probe
        out += "\n## By turn type\n\n| probe | n | clean | errors | citations (mean) | mean s | codes |\n|---|---|---|---|---|---|---|\n"
        for label in samples.map(\.probe).reduced() {
            let s = samples.filter { $0.probe == label }
            let clean = s.filter { $0.violations.isEmpty && $0.error == nil }.count
            let e = s.filter { $0.error != nil }.count
            let cites = s.filter { $0.error == nil }.map { Double($0.citations) }
            let meanCite = cites.isEmpty ? 0 : cites.reduce(0, +) / Double(cites.count)
            let mean = s.map(\.seconds).reduce(0, +) / Double(s.count)
            let codes = Set(s.flatMap { $0.violations.map(\.code) }).sorted().joined(separator: " ")
            out += "| \(label) | \(s.count) | \(clean) | \(e) | \(String(format: "%.1f", meanCite)) "
            out += "| \(String(format: "%.1f", mean)) | \(codes.isEmpty ? "—" : codes) |\n"
        }
        return out
    }
}

private extension Array where Element: Hashable {
    /// Distinct values, order preserved.
    func reduced() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
