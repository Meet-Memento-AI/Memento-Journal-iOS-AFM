import XCTest
import FoundationModels
@testable import MeetMemento

/// TEMPORARY — Phase 0 of the AIChat repair plan. Delete once the mechanism is
/// confirmed and Phase 2 lands.
///
/// Hypothesis under test: `generationFailed("Failed to parse generated content.")`
/// is a *truncation* failure, not a malformed-emission failure. Two independent
/// levers are varied over the same follow-up turn:
///
///   schema — trailing `citedRefs` required (`[Int]`) vs tolerant (`[Int]?`)
///   cap    — `maximumResponseTokens` 128 (what `.thread` gets without RAG)
///            vs 512 (what `.notebook` gets)
///
/// Prediction: required+128 fails ~always; 512 recovers most; optional+128
/// recovers partially. If the grid does not look like that, the plan's Phase 2
/// is built on a wrong theory and must be re-derived.
final class Phase0DecodeProbe: XCTestCase {

    private static let reps = 5

    // MARK: - Schema twins (identical guides to AskAnswer, differing only in the trailing field)

    @Generable
    struct ProbeRequired {
        @Guide(description: "The complete spoken reply in second person. Sound like a person talking. End with one specific question; skip the question only on goodbye. Notebook, ###, and italic quotes only if this turn uses the journal; otherwise leave citedRefs empty. Markdown subset allowed when the journal is in play: one ### heading, paragraphs, - lists, 1. lists, **bold** on a short span of their wording, *italic* for an exact journal quote. No emoji, no reference markers such as [ref 2], (ref 2), ref 2, or [2]. Name an entry by its date or subject instead. Do not name their emotions, give advice, or state a count of entries.")
        let body: String
        @Guide(description: "Always empty on conversational Ask. Titles steal decode and delay the visible body.")
        let heading1: String?
        @Guide(description: "Always empty on conversational Ask.")
        let heading2: String?
        @Guide(description: "The [ref] numbers of the journal entries from the context block that were actually referenced. Empty if none. These belong here only — never in the body.")
        let citedRefs: [Int]
    }

    @Generable
    struct ProbeOptional {
        @Guide(description: "The complete spoken reply in second person. Sound like a person talking. End with one specific question; skip the question only on goodbye. Notebook, ###, and italic quotes only if this turn uses the journal; otherwise leave citedRefs empty. Markdown subset allowed when the journal is in play: one ### heading, paragraphs, - lists, 1. lists, **bold** on a short span of their wording, *italic* for an exact journal quote. No emoji, no reference markers such as [ref 2], (ref 2), ref 2, or [2]. Name an entry by its date or subject instead. Do not name their emotions, give advice, or state a count of entries.")
        let body: String
        @Guide(description: "Always empty on conversational Ask. Titles steal decode and delay the visible body.")
        let heading1: String?
        @Guide(description: "Always empty on conversational Ask.")
        let heading2: String?
        @Guide(description: "The [ref] numbers of the journal entries from the context block that were actually referenced. Empty if none. These belong here only — never in the body.")
        let citedRefs: [Int]?
    }

    // MARK: - The turn under test

    /// A follow-up: exactly the shape that failed 15/16 times in the QA pass.
    private static let history: [ChatTurn] = [
        ChatTurn(role: .user, text: "What did I write about the hike?"),
        ChatTurn(role: .assistant,
                 text: "You went up Mount Tamalpais with Maya, starting in fog before it broke open at the top.")
    ]
    private static let question = "Tell me more about that."

    /// Rebuilds production's session the way `makeSession(from:)` does — the
    /// instruction entry plus plain-prose history turns.
    private func makeSession() -> LanguageModelSession {
        let instructions = PromptRegistry.instructions(for: .ask).text
        var entries: [Transcript.Entry] = [
            .instructions(Transcript.Instructions(
                segments: [.text(Transcript.TextSegment(content: instructions))],
                toolDefinitions: []
            ))
        ]
        for turn in Self.history {
            switch turn.role {
            case .user:
                entries.append(.prompt(Transcript.Prompt(
                    segments: [.text(Transcript.TextSegment(content: turn.text))]
                )))
            case .assistant:
                entries.append(.response(Transcript.Response(
                    assetIDs: [],
                    segments: [.text(Transcript.TextSegment(content: turn.text))]
                )))
            }
        }
        return LanguageModelSession(transcript: Transcript(entries: entries))
    }

    /// The `[Turn: follow-up]` stance line plus the message, as `buildAskPrompt`
    /// assembles it for a thread turn with no evidence.
    private var prompt: String {
        [TurnStance.followupThread.promptLine,
         "The person's latest message: \(Self.question)"].joined(separator: "\n\n")
    }

    // MARK: - Grid

    private struct Cell {
        let schema: String
        let cap: Int
        var ok = 0
        var fail = 0
        var errors: [String] = []
        var lengths: [Int] = []
    }

    func test_decodeFailureGrid() async throws {
        guard case .available = SystemLanguageModel.default.availability else {
            throw XCTSkip("on-device model unavailable on this destination")
        }

        var cells: [Cell] = []

        for cap in [128, 512] {
            for schema in ["required", "optional"] {
                var cell = Cell(schema: schema, cap: cap)
                for _ in 1...Self.reps {
                    let session = makeSession()
                    let options = GenerationOptions(temperature: 0.9, maximumResponseTokens: cap)
                    do {
                        if schema == "required" {
                            let r = try await session.respond(to: prompt,
                                                              generating: ProbeRequired.self,
                                                              options: options)
                            cell.ok += 1
                            cell.lengths.append(r.content.body.count)
                        } else {
                            let r = try await session.respond(to: prompt,
                                                              generating: ProbeOptional.self,
                                                              options: options)
                            cell.ok += 1
                            cell.lengths.append(r.content.body.count)
                        }
                    } catch let e as LanguageModelSession.GenerationError {
                        cell.fail += 1
                        cell.errors.append(Self.label(e))
                    } catch {
                        cell.fail += 1
                        cell.errors.append("other: \(error)")
                    }
                }
                cells.append(cell)
            }
        }

        // Control: the unstructured path at the same 128-token cap. If this
        // succeeds where structured decoding fails, the schema is the problem,
        // not the model's ability to answer within the budget.
        var plainOK = 0, plainFail = 0
        var plainLengths: [Int] = []
        for _ in 1...Self.reps {
            let session = makeSession()
            do {
                let r = try await session.respond(
                    to: prompt,
                    options: GenerationOptions(temperature: 0.9, maximumResponseTokens: 128))
                plainOK += 1
                plainLengths.append(r.content.count)
            } catch {
                plainFail += 1
            }
        }

        var out = "# Phase 0 — decode failure grid\n\n"
        out += "turn: follow-up (`\(Self.question)`), 2 history turns, no evidence\n"
        out += "instructions: ask@14 (\(PromptRegistry.instructions(for: .ask).text.count) chars), \(Self.reps) reps per cell\n\n"
        out += "| schema | cap | ok | fail | mean body chars | errors |\n|---|---|---|---|---|---|\n"
        for c in cells {
            let mean = c.lengths.isEmpty ? 0 : c.lengths.reduce(0, +) / c.lengths.count
            let errs = Set(c.errors).sorted().joined(separator: ", ")
            out += "| \(c.schema) | \(c.cap) | \(c.ok) | \(c.fail) | \(mean) | \(errs) |\n"
        }
        let plainMean = plainLengths.isEmpty ? 0 : plainLengths.reduce(0, +) / plainLengths.count
        out += "| **unstructured** | 128 | \(plainOK) | \(plainFail) | \(plainMean) | — |\n"

        Phase0DecodeProbe.write(out)
        print(out)
    }

    /// The measurement that actually matters: the production `askStream` path,
    /// over the turn shapes that failed 15/16 times in the QA pass.
    func test_productionStreamAfterFix() async throws {
        guard case .available = SystemLanguageModel.default.availability else {
            throw XCTSkip("on-device model unavailable on this destination")
        }
        let service = FoundationModelsIntelligenceService.shared
        let corpus = ChatEvalCorpus.attributionCorpus
        let hist = Self.history

        let cases: [(String, String, [ChatTurn])] = [
            ("continuer + history", "Tell me more about that.", hist),
            ("other continuer + history", "Say more?", hist),
            ("full question + history", "What else did I write that week?", hist),
            ("advice bait", "What should I do about my job?", []),
            ("control / hike", "What did I write about the hike?", [])
        ]

        var out = "# Phase 0 verification — production askStream after the schema fix\n\n"
        var totalOK = 0, totalFail = 0
        for (name, q, history) in cases {
            var ok = 0, fail = 0
            var notes: [String] = []
            for trial in 1...4 {
                do {
                    var body = ""
                    var cites = 0
                    for try await event in service.askStream(q, history: history,
                                                             entries: corpus, images: []) {
                        if case .final(let r) = event { body = r.body; cites = r.citations.count }
                    }
                    if body.isEmpty {
                        fail += 1; notes.append("  - t\(trial) EMPTY body")
                    } else {
                        ok += 1
                        let leaked = body.lowercased().contains("citedrefs")
                        notes.append("  - t\(trial) OK \(body.count)ch \(cites)cit\(leaked ? " ⚠︎LEAK" : "")")
                    }
                } catch {
                    fail += 1; notes.append("  - t\(trial) FAIL \(error)")
                }
            }
            totalOK += ok; totalFail += fail
            out += "## \(name) — `\(q)` (history \(history.count))\n\nOK \(ok)/4\n"
                + notes.joined(separator: "\n") + "\n\n"
        }
        out = "**\(totalOK)/\(totalOK + totalFail) succeeded**\n\n" + out
        Phase0DecodeProbe.write(out, "phase0-verify.md")
        print(out)
    }

    private static func label(_ e: LanguageModelSession.GenerationError) -> String {
        switch e {
        case .decodingFailure: return "decodingFailure"
        case .exceededContextWindowSize: return "exceededContextWindowSize"
        case .guardrailViolation: return "guardrailViolation"
        case .unsupportedLanguageOrLocale: return "unsupportedLanguageOrLocale"
        case .assetsUnavailable: return "assetsUnavailable"
        case .rateLimited: return "rateLimited"
        case .concurrentRequests: return "concurrentRequests"
        case .refusal: return "refusal"
        default: return "other(\(e))"
        }
    }

    private static func write(_ text: String, _ file: String = "phase0.md") {
        let dir = ProcessInfo.processInfo.environment["PHASE0_OUT"]
            ?? "/private/tmp/claude-501/-Users-sebastianmendo-Swift-projects-Memento-AI-MeetMemento/1e8133b8-91db-49ba-aa83-437a99ca7eb2/scratchpad"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? text.write(toFile: "\(dir)/\(file)", atomically: true, encoding: .utf8)
    }
}
