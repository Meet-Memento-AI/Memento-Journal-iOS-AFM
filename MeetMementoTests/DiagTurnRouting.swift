import XCTest
@testable import MeetMemento

/// Diagnostic: TurnClassifier → ReplyChannel → generation recipe.
/// Pure Swift, no model calls, so it can sweep a wide utterance set.
/// A misroute here is expensive: a journal question landing on `phatic`
/// gets chat-light@4, no retrieval and an 80-token ceiling.
final class DiagTurnRouting: XCTestCase {

    struct Case {
        let text: String
        let hasHistory: Bool
        let expect: TurnType
        init(_ text: String, _ expect: TurnType, history: Bool = false) {
            self.text = text; self.expect = expect; self.hasHistory = history
        }
    }

    static let cases: [Case] = [
        // social
        Case("Hey", .social), Case("hi", .social), Case("hello there", .social),
        Case("good morning", .social), Case("thanks!", .social),
        Case("thank you so much", .social), Case("goodnight", .social),
        Case("how are you?", .social),

        // acknowledgement / continuer
        Case("yeah", .acknowledgement, history: true),
        Case("mm", .acknowledgement, history: true),
        Case("i guess", .acknowledgement, history: true),
        Case("haha", .acknowledgement, history: true),
        Case("ok", .acknowledgement, history: true),
        Case("right", .acknowledgement, history: true),

        // meta — about the app
        Case("What can you do?", .meta), Case("who are you?", .meta),
        Case("are you an AI?", .meta), Case("how do you work?", .meta),
        Case("can you read my journal?", .meta),

        // journalQuery
        Case("What have I been writing about lately?", .journalQuery),
        Case("What did I write about the hike?", .journalQuery),
        Case("How have I been sleeping?", .journalQuery),
        Case("Who is Maya?", .journalQuery),
        Case("what did I say about work last week?", .journalQuery),
        Case("have I mentioned Daniel before?", .journalQuery),
        Case("show me my entries about my mother", .journalQuery),
        Case("did I write anything yesterday?", .journalQuery),
        Case("what patterns do you see in my journal?", .journalQuery),
        Case("summarise my week", .journalQuery),

        // share
        Case("I had a rough day at work today", .share),
        Case("I finally finished the book", .share),
        Case("my sister is visiting next week", .share),
        Case("I'm exhausted", .share),

        // reflectiveQuestion
        Case("why do I keep doing this?", .reflectiveQuestion),
        Case("why am I always so tired?", .reflectiveQuestion),

        // followup
        Case("Tell me more about that.", .followup, history: true),
        Case("what do you mean?", .followup, history: true),
        Case("say more", .followup, history: true),

        // offdomain
        Case("what is the capital of France?", .offdomain),
        Case("how do I fix a flat tyre?", .offdomain),
        Case("who won the world cup in 2018?", .offdomain),
        Case("write me a python script", .offdomain)
    ]

    func test_routing() throws {
        var out = "# Turn routing diagnostic (pure, no model)\n\n"
        out += "TurnClassifier.classify → ReplyChannel.resolve → recipe\n\n"
        out += "| utterance | hist | expected | actual | match | channel | prompt | RAG | max tok | temp |\n"
        out += "|---|---|---|---|---|---|---|---|---|---|\n"

        var mismatches: [(Case, TurnType, ReplyChannel)] = []
        var byChannel: [ReplyChannel: Int] = [:]

        for c in Self.cases {
            let actual = TurnClassifier.classify(c.text, hasHistory: c.hasHistory)
            let channel = ReplyChannel.resolve(turn: actual, hasImages: false)
            let ok = actual == c.expect
            if !ok { mismatches.append((c, actual, channel)) }
            byChannel[channel, default: 0] += 1

            let rag = channel.allowsRetrieval
            let tok = channel.maximumResponseTokens(retrievalRan: rag)
            let temp = channel.temperature(retrievalRan: rag)
            let q = c.text.count > 42 ? String(c.text.prefix(42)) + "…" : c.text
            out += "| \(q) | \(c.hasHistory ? "y" : "n") | \(c.expect.rawValue) | \(actual.rawValue) "
            out += "| \(ok ? "ok" : "**MISS**") | \(channel.rawValue) "
            out += "| \(channel.usesLightPrompt ? "light@4" : "ask@14") | \(rag ? "yes" : "no") "
            out += "| \(tok) | \(String(format: "%.1f", temp)) |\n"
        }

        out += "\n**\(Self.cases.count - mismatches.count)/\(Self.cases.count) classified as expected.**\n"

        if !mismatches.isEmpty {
            out += "\n## Misroutes\n\n"
            for (c, actual, channel) in mismatches {
                let rag = channel.allowsRetrieval
                out += "- `\(c.text)`\n"
                out += "  expected **\(c.expect.rawValue)**, got **\(actual.rawValue)** → channel `\(channel.rawValue)`"
                out += " (\(channel.usesLightPrompt ? "chat-light@4" : "ask@14"), "
                out += "retrieval \(rag ? "on" : "OFF"), \(channel.maximumResponseTokens(retrievalRan: rag)) tok)\n"
                if c.expect == .journalQuery && !rag {
                    out += "  > journal question with retrieval OFF — cannot be grounded\n"
                }
            }
        }

        out += "\n## Recipe table (all channels)\n\n"
        out += "| channel | prompt | lens | retrieval | max tok (RAG) | max tok (no RAG) | temp |\n|---|---|---|---|---|---|---|\n"
        for ch in ReplyChannel.allCases {
            out += "| \(ch.rawValue) | \(ch.usesLightPrompt ? "chat-light@4" : "ask@14") "
            out += "| \(ch.omitsLens ? "omitted" : "included") | \(ch.allowsRetrieval ? "yes" : "no") "
            out += "| \(ch.maximumResponseTokens(retrievalRan: true)) | \(ch.maximumResponseTokens(retrievalRan: false)) "
            out += "| \(String(format: "%.1f", ch.temperature)) |\n"
        }

        out += "\n## Channel distribution over the sweep\n\n"
        for (ch, n) in byChannel.sorted(by: { $0.value > $1.value }) {
            out += "- `\(ch.rawValue)` × \(n)\n"
        }

        Diag.write(out, "01-routing.md")
        print(out)
    }
}
