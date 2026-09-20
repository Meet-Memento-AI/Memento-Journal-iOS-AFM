import XCTest
@testable import MeetMemento

/// Where does each of the 1,000 sweep prompts get *routed*, before a single
/// token is generated?
///
/// The sweep showed 43 of 60 "what is this app" questions answering out of the
/// journal. `RetrievalPolicy.mode` returns `.none` for `.meta` and
/// `ReplyChannel.meta.allowsRetrieval` is false, so the retrieval plumbing
/// cannot be what put entries in those replies — the classifier has to be
/// handing them to a channel that retrieves. This pins that down.
///
/// No model, no simulator capability needed: `TurnClassifier`, `ReplyChannel`
/// and `RetrievalPolicy` are all pure Swift. Runs in milliseconds.
final class PromptSweepRouting: XCTestCase {

    func test_dumpRouting() throws {
        let prompts = PromptSweepCorpus.prompts()
        XCTAssertEqual(prompts.count, PromptSweepCorpus.targetCount)

        var rows: [[String: Any]] = []
        for prompt in prompts {
            let turn = TurnClassifier.classify(prompt.text, hasHistory: !prompt.history.isEmpty)
            let channel = ReplyChannel.resolve(turn: turn, hasImages: false)
            let mode = RetrievalPolicy.mode(for: turn, history: prompt.history)
            rows.append([
                "index": prompt.index,
                "category": prompt.category,
                "question": prompt.text,
                "turn": turn.rawValue,
                "channel": channel.rawValue,
                "retrieval": "\(mode)",
                "allowsRetrieval": channel.allowsRetrieval,
                "cap": channel.maximumResponseTokens(retrievalRan: channel.allowsRetrieval)
            ])
        }

        let dir = MementoPromptSweep.outputDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
        try data.write(to: dir.appendingPathComponent("routing.json"))
        print("[routing] wrote \(rows.count) rows to \(dir.path)/routing.json")
    }
}
