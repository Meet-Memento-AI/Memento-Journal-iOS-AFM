import XCTest
@testable import withMemento

/// Long-form self-play conversation capture (the 200-conversation study).
///
/// `ChatEvalGate` measures one generation at a time and `AgenticEval` plays
/// short scripted probes. Neither answers what a *real session* looks like:
/// twenty to fifty messages, where every user turn is a reaction to what the
/// assistant actually just said, and where the history window
/// (`ChatService.historyMessageLimit`) closes over the start of the
/// conversation partway through. This harness produces that corpus.
///
/// Both sides run on the device model. The assistant side goes through
/// `askStream` — the path `AIChatView` uses, via `ChatService` — so retrieval,
/// stance, channel and citation reconciliation are all live. The person side is
/// a second, persona-briefed session through `evalRawGenerate`, which exists
/// only in DEBUG and deliberately bypasses the Memento persona.
///
/// Two arms, 100 conversations each:
///   * `empty` — no journal at all (a brand-new install)
///   * `cold`  — the 8-entry `Fixtures/cold-start` journal
///
/// This **reports**; it never gates. Scoring fields are recorded as data for
/// later analysis, not asserted on. The only assertion is that the run produced
/// output at all.
///
/// Run it:
/// ```
/// TEST_RUNNER_CONVO_SIM=1 TEST_RUNNER_CONVO_SIM_RUNS=3 TEST_RUNNER_CONVO_SIM_LABEL=pilot \
/// DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer \
/// xcodebuild test -scheme withMemento \
///   -destination 'platform=iOS Simulator,id=<iOS 27 device>' \
///   -parallel-testing-enabled NO \
///   -only-testing:withMementoTests/ConversationSimulation
/// ```
final class ConversationSimulation: XCTestCase {

    // MARK: - Configuration

    /// xcodebuild forwards host variables prefixed `TEST_RUNNER_` into the test
    /// process **with the prefix stripped**, which is why the run command says
    /// `TEST_RUNNER_CONVO_SIM_RUNS` and the code reads `CONVO_SIM_RUNS`. Same
    /// convention as `ChatEvalGate`'s `CHAT_EVAL`.
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    /// Conversations per arm. The full study is 100; the pilot overrides it.
    private static var runsPerArm: Int {
        Int(env["CONVO_SIM_RUNS"] ?? "") ?? 100
    }

    private static var label: String {
        env["CONVO_SIM_LABEL"].flatMap { $0.isEmpty ? nil : $0 } ?? "run"
    }

    /// Comma-separated subset, e.g. `CONVO_SIM_ARMS=cold`. Defaults to both.
    /// `sweep` is not a single arm: it expands to one arm per corpus size,
    /// `size-001` through `size-<CONVO_SIM_SWEEP_MAX>` (study V).
    private static var armNames: [String] {
        let raw = env["CONVO_SIM_ARMS"] ?? "empty,cold"
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Largest journal in the study V sweep. 100 arms x 2 runs = 200 sessions.
    private static var sweepMax: Int {
        Int(env["CONVO_SIM_SWEEP_MAX"] ?? "") ?? 100
    }

    /// Total messages per conversation, sampled per run inside this range.
    private static let minMessages = 20
    private static let maxMessages = 50

    /// A single generation that has not returned by now is treated as a failed
    /// turn and recorded as one. Without this a wedged model server stalls a
    /// twenty-hour run indefinitely.
    private static let turnTimeout: Duration = .seconds(180)

    // MARK: - Arm

    private struct Arm {
        let name: String
        let entries: [Entry]
        let fixtureIDs: [UUID: String]
        let quoteIndex: ChatEvalScoring.QuoteIndex

        /// A citation says which entry was used; only its date says whether the
        /// model reached for recent or old evidence.
        var createdAtByUUID: [UUID: Date] {
            Dictionary(entries.map { ($0.id, $0.createdAt) }, uniquingKeysWith: { first, _ in first })
        }

        /// Oldest and newest entry, for the manifest. The persona corpus is
        /// absolutely dated and cold-start is relative to `Date()`, so a reader
        /// cannot tell what world an arm was without it.
        var entryDateRange: [String] {
            guard let first = entries.first?.createdAt, let last = entries.last?.createdAt else { return [] }
            let iso = ISO8601DateFormatter()
            return [iso.string(from: min(first, last)), iso.string(from: max(first, last))]
        }
    }

    // MARK: - Test

    func testSimulateConversations() async throws {
        try XCTSkipUnless(Self.env["CONVO_SIM"] == "1",
                          "Set TEST_RUNNER_CONVO_SIM=1 to run the conversation study.")
        executionTimeAllowance = 60 * 60 * 48

        let service = FoundationModelsIntelligenceService.shared
        guard case .available = await service.availability() else {
            XCTFail("""
                The device model is not available on this simulator, so nothing here would \
                generate. Check Apple Intelligence on the host and re-run.
                """)
            return
        }

        let arms = try Self.buildArms()
        let started = Date()
        Self.writeManifest(arms: arms, started: started)

        var messagesWritten = 0
        for arm in arms {
            for runIndex in 0..<Self.runsPerArm {
                let runID = "\(Self.label)/\(arm.name)/\(String(format: "%03d", runIndex))"
                // Studies II-IV walk the 10x10 cast matrix in order, because
                // runsPerArm is 100 and the walk covers it exactly once. The
                // study V sweep runs 2 conversations per arm, so an in-order
                // walk would ask every journal size the same two questions and
                // any trend across sizes could just as well be a property of
                // those two. Drawing the cell from the run id instead
                // decorrelates question type from corpus size while staying
                // reproducible: the id is fixed, so the draw replays exactly.
                let cellIndex = Self.armNames.contains("sweep")
                    ? Int(Self.seed(for: runID) % UInt64(ConvoSimCast.matrix.count))
                    : runIndex % ConvoSimCast.matrix.count
                let cell = ConvoSimCast.matrix[cellIndex]
                messagesWritten += await runConversation(
                    runID: runID, arm: arm, persona: cell.persona, intent: cell.intent,
                    service: service
                )
                print("[convo-sim] finished \(runID) — \(messagesWritten) messages so far")
            }
        }

        Self.writeManifest(arms: arms, started: started, finished: Date(),
                           messages: messagesWritten)
        XCTAssertGreaterThan(messagesWritten, 0, "the run produced no messages at all")
    }

    // MARK: - One conversation

    /// Returns the number of messages recorded.
    private func runConversation(runID: String,
                                 arm: Arm,
                                 persona: ConvoSimCast.Persona,
                                 intent: ConvoSimCast.Intent,
                                 service: FoundationModelsIntelligenceService) async -> Int {
        var rng = SplitMix64(seed: Self.seed(for: runID))
        let plannedMessages = Self.evenLength(&rng)
        let exchanges = plannedMessages / 2
        let personaIndex = ConvoSimCast.personas.firstIndex { $0.id == persona.id } ?? 0
        let lifeContext = Self.lifeContext(arm: arm, personaIndex: personaIndex)

        var history: [ChatTurn] = []
        var messageIndex = 0
        var failedTurns = 0

        for exchange in 0..<exchanges {
            // --- the person's turn
            let userText: String
            var move: String?
            var userErrors: [String] = []
            if exchange == 0 {
                userText = intent.opener
            } else {
                let drawn = exchange == exchanges - 1
                    ? ConvoSimCast.closingMove
                    : ConvoSimCast.moves[Int(rng.next() % UInt64(ConvoSimCast.moves.count))]
                move = drawn
                // The *simulator's* own guardrail refuses some moves outright
                // ("ask it to do something it should not"), and an unanswered
                // user turn ends the conversation. That truncation is an
                // artefact of the harness, not a fact about the app, so retry
                // on a safer move and then fall back to a scripted line.
                var produced: String?
                for attempt in 0..<2 where produced == nil {
                    let attemptMove = attempt == 0 ? drawn : ConvoSimCast.safeMove
                    // Rendered before the concurrent closure: `history` is a var
                    // that later turns append to, and capturing it by reference
                    // is an error in the Swift 6 language mode.
                    let attemptPrompt = Self.userPrompt(history: history, move: attemptMove)
                    do {
                        produced = try await Self.withTimeout(Self.turnTimeout) {
                            try await service.evalRawGenerate(
                                instructions: Self.userInstructions(persona: persona,
                                                                    lifeContext: lifeContext),
                                prompt: attemptPrompt,
                                temperature: 1.0,
                                maximumResponseTokens: 90
                            )
                        }
                        if attempt == 1 { move = ConvoSimCast.safeMove }
                    } catch {
                        userErrors.append("\(error)")
                    }
                }
                if let produced, !Self.cleanUserTurn(produced).isEmpty {
                    userText = produced
                } else {
                    let pool = ConvoSimCast.fallbackLines
                    userText = pool[Int(rng.next() % UInt64(pool.count))]
                    move = "fallback"
                }
            }
            let cleanedUser = Self.cleanUserTurn(userText)
            guard !cleanedUser.isEmpty else { return messageIndex }

            var userRow = Self.row(runID: runID, arm: arm, persona: persona, intent: intent,
                                   plannedMessages: plannedMessages, index: messageIndex,
                                   role: "user", text: cleanedUser)
            if let move { userRow["move"] = move }
            if !userErrors.isEmpty { userRow["generation_errors"] = userErrors }
            Self.flush(userRow)
            messageIndex += 1

            // --- the assistant's turn, through the path AIChatView uses
            let capped = Array(history.suffix(ChatService.historyMessageLimit))
            let answeringLastQuestion = ConversationalMove.lastAssistantQuestion(in: capped) != nil
            let turnType = TurnClassifier.classify(
                cleanedUser,
                hasHistory: !capped.isEmpty,
                lastAssistantAskedQuestion: answeringLastQuestion
            )
            let evidence: EvidenceState = arm.entries.isEmpty ? .none : .matched
            let channel = ReplyChannel.resolve(turn: turnType, hasImages: false, evidence: evidence)
            let shape = QuestionShapeResolver.shape(of: cleanedUser, turn: turnType)
            let policy = ResponsePolicyResolver.policy(shape: shape, evidence: evidence)

            var result: AskResult?
            var failure: String?
            var failureFallback: String?
            var isDesignedRefusal = false
            let clock = ContinuousClock()
            let begun = clock.now
            do {
                result = try await Self.withTimeout(Self.turnTimeout) {
                    var final: AskResult?
                    for try await event in service.askStream(cleanedUser, history: capped,
                                                             entries: arm.entries, images: []) {
                        if case .final(let r) = event { final = r }
                    }
                    return final
                }
                if result == nil { failure = "stream ended without a final result" }
            } catch {
                failure = "\(error)"
                // `guardrailRefusal`, `crisisResource` and `safetyRefusal` are
                // *designed* states (spec 026), not crashes: the real bubble
                // shows `userMessage` and the conversation carries on. Ending
                // the run here would truncate exactly the conversations that
                // touch the safety stack, which is the opposite of what this
                // study wants to capture.
                failureFallback = (error as? IntelligenceError)?.errorDescription
                isDesignedRefusal = Self.isDesigned(error)
            }
            let elapsed = clock.now - begun
            let seconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18

            var row = Self.row(runID: runID, arm: arm, persona: persona, intent: intent,
                               plannedMessages: plannedMessages, index: messageIndex,
                               role: "assistant",
                               text: result?.body ?? failureFallback ?? "", error: failure)
            if failureFallback != nil { row["text_is_fallback"] = true }
            if failure != nil { row["designed_refusal"] = isDesignedRefusal }
            row["seconds"] = seconds
            row["turn_type"] = turnType.rawValue
            row["channel"] = channel.rawValue
            row["history_messages"] = capped.count
            row["history_truncated"] = capped.count < history.count
            // Recorded before generation, so a refused or timed-out turn still
            // says which way the pipeline sent it.
            row["evidence_state"] = evidence.rawValue
            row["question_shape"] = shape.rawValue
            row["response_policy"] = policy.rawValue

            if let result {
                row["prompt_version"] = result.promptVersion
                row["model_identifier"] = result.modelIdentifier
                row["was_degraded"] = result.wasDegraded
                row["tools_called"] = result.toolsCalled
                row["heading1"] = result.heading1 ?? ""
                row["heading2"] = result.heading2 ?? ""
                // No String raw value on TrustZone; the case name is what a
                // report wants.
                row["zone"] = String(describing: result.zoneUsed)
                row["model_seconds"] = Double(result.latency.components.seconds)
                    + Double(result.latency.components.attoseconds) / 1e18
                row["body_chars"] = result.body.count
                row["body_words"] = result.body.split(whereSeparator: { $0.isWhitespace }).count
                let createdAt = arm.createdAtByUUID
                let citationISO = ISO8601DateFormatter()
                row["citations"] = result.citations.map { citation -> [String: Any] in
                    var encoded: [String: Any] = [
                        "entry_uuid": citation.entryId.uuidString,
                        "fixture_id": arm.fixtureIDs[citation.entryId] ?? "",
                        "excerpt": citation.excerpt
                    ]
                    if let date = createdAt[citation.entryId] {
                        encoded["entry_created_at"] = citationISO.string(from: date)
                        encoded["entry_age_days"] = Date().timeIntervalSince(date) / 86_400
                    }
                    return encoded
                }
                row["facts"] = Self.encodeFacts(result.facts)
                row["render_version"] = ReplyRenderer.version
                row["chips"] = result.chips.count
                if let stats = result.renderStats {
                    row["evidence_pack"] = Self.encodeRenderStats(stats)
                }
                let isCasual = turnType == .social || turnType == .acknowledgement
                let cap = channel.maximumResponseTokens(retrievalRan: !result.citations.isEmpty)
                let bodyEmpty = result.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let openRequired = ResponsePolicyResolver.openRequired(
                    policy: policy, bodyIsEmpty: bodyEmpty || result.promptVersion == "insight-fact@1"
                )
                let violations =
                    ChatEvalScoring.leaks(result.body)
                    + ChatEvalScoring.ruleBreaks(
                        result.body, isCasual: isCasual, index: arm.quoteIndex, openRequired: openRequired
                    )
                    + ChatEvalScoring.fabricatedQuotes(result.body, index: arm.quoteIndex)
                    + ChatEvalScoring.uncitedQuote(result.body, citations: result.citations,
                                                   index: arm.quoteIndex)
                    + ChatEvalScoring.unbackedDate(result.body, citations: result.citations)
                    + ChatEvalScoring.boldNotTheirWords(result.body, index: arm.quoteIndex)
                    + ChatEvalScoring.runaway(result.body, capTokens: cap)
                    + ChatEvalScoring.insightDigitDisagrees(body: result.body, facts: result.facts)
                    + ChatEvalScoring.insightContradictsSuppressed(body: result.body, facts: result.facts)
                row["violations"] = violations.map { ["code": $0.code, "detail": $0.detail] }
            }
            Self.flush(row)
            messageIndex += 1

            history.append(ChatTurn(role: .user, text: cleanedUser))
            if let result, failure == nil {
                history.append(ChatTurn(role: .assistant, text: result.body))
            } else {
                // A designed refusal is the app working as specified, and a
                // conversation that draws four of them is a finding worth
                // having in full — only *undesigned* failures (an unavailable
                // model, a timeout) suggest a wedged runtime worth bailing on.
                if !isDesignedRefusal { failedTurns += 1 }
                guard failedTurns < 4, let fallback = failureFallback else { return messageIndex }
                history.append(ChatTurn(role: .assistant, text: fallback))
            }
        }

        return messageIndex
    }

    /// `guardrailRefusal`, `crisisResource` and `safetyRefusal` are states the
    /// app is specified to reach (spec 026); everything else is a runtime fault.
    private static func isDesigned(_ error: Error) -> Bool {
        switch error as? IntelligenceError {
        case .guardrailRefusal, .crisisResource, .safetyRefusal: return true
        default: return false
        }
    }

    // MARK: - The person's side

    private static func userInstructions(persona: ConvoSimCast.Persona,
                                         lifeContext: String) -> String {
        """
        You are role-playing a person using a private journalling app. You are the PERSON, \
        never the assistant. You write the next message the person would type.

        Your life right now: \(lifeContext)

        Your manner: \(persona.brief)

        Rules, all of them absolute:
        - Output only the message text. No quotation marks, no name label, no stage \
        directions, no explanation of what you are doing.
        - One message. Never write the assistant's reply.
        - Never repeat a phrase, image or detail you have already used in this \
        conversation. Every message brings something the conversation has not had yet.
        - Do not paraphrase the assistant back at it. You are a person with a life; your \
        next message comes from that life, not from the last thing on screen.
        - Do not be endlessly agreeable. Drop a thread, push back, or go quiet when that \
        is what this person would do.
        """
    }

    private static func userPrompt(history: [ChatTurn], move: String) -> String {
        // The person can see the whole conversation on screen, but the window has
        // to stay bounded or a 50-message run overflows the context. The last ten
        // messages is roughly what a person has in their head.
        let recent = history.suffix(10)
        var lines = ["The conversation so far:", ""]
        for turn in recent {
            lines.append(turn.role == .user ? "You: \(turn.text)" : "Assistant: \(turn.text)")
        }
        // Naming what has already been said is what actually stops the loop —
        // the instruction alone does not survive twenty turns.
        let used = history.filter { $0.role == .user }.suffix(6).map { turn in
            "- " + turn.text.replacingOccurrences(of: "\n", with: " ").prefix(60)
        }
        if !used.isEmpty {
            lines.append("")
            lines.append("You have already said these things. Do not say them again:")
            lines.append(contentsOf: used)
        }
        lines.append("")
        lines.append("Write your next message. This turn: \(move)")
        return lines.joined(separator: "\n")
    }

    /// What is going on in this person's life.
    ///
    /// For the seeded arm this is built from the journal itself, so the person
    /// and their entries agree — a person whose journal is about pottery and a
    /// bad argument should not be talking about a PhD.
    private static func lifeContext(arm: Arm, personaIndex: Int) -> String {
        guard !arm.entries.isEmpty else {
            return ConvoSimCast.lifeContexts[personaIndex % ConvoSimCast.lifeContexts.count]
        }
        let threads = arm.entries.suffix(8).map { entry in
            entry.text.split(separator: "\n").first.map(String.init) ?? entry.title
        }
        return "These are the things you have been living through and writing down lately: "
            + threads.map { String($0.prefix(110)) }.joined(separator: " / ")
    }

    /// The model occasionally wraps its line in quotes or prefixes a speaker
    /// label despite the instructions. Strip both — the harness records what a
    /// person would have typed, and a stray `You:` would change how
    /// `TurnClassifier` routes the turn.
    private static func cleanUserTurn(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["You:", "User:", "Person:", "Me:"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        if text.count > 1, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Arms

    private static func buildArms() throws -> [Arm] {
        // Loaded once, outside the map: `QuoteIndex` hashes every 30-char gram,
        // which on the 262-entry persona journal is not free enough to repeat.
        let cold = armNames.contains("cold") ? try ChatEvalCorpus.coldStartCorpus() : nil
        let wantsPersonaCorpus = armNames.contains("persona") || armNames.contains("sweep")
        let persona = wantsPersonaCorpus ? try ChatEvalCorpus.personaCorpus() : nil
        let arms: [Arm] = armNames.compactMap { name in
            switch name {
            case "empty":
                return Arm(name: "empty", entries: [], fixtureIDs: [:],
                           quoteIndex: ChatEvalScoring.QuoteIndex([]))
            case "cold":
                guard let cold else { return nil }
                return Arm(name: "cold", entries: cold.entries, fixtureIDs: cold.idByUUID,
                           quoteIndex: ChatEvalScoring.QuoteIndex(cold.entries))
            // The 262-entry, nine-month journal. Study II's seeded arm; kept
            // identical here so the only variable between the two runs is the
            // pipeline.
            case "persona":
                guard let persona else { return nil }
                return Arm(name: "persona", entries: persona.entries, fixtureIDs: persona.idByUUID,
                           quoteIndex: ChatEvalScoring.QuoteIndex(persona.entries))
            default:
                return nil
            }
        }
        return arms + sweepArms(persona: persona)
    }

    /// Study V. One arm per journal size n, holding everything else fixed.
    ///
    /// The n entries are the **most recent** n of the persona corpus, not a
    /// random sample and not the oldest n. A person with seven entries wrote
    /// them over the last few weeks and the newest is today's; taking the
    /// oldest seven would instead model someone who journalled for a fortnight
    /// nine months ago and then stopped, which is a different question. The
    /// cost of this choice is that a small arm also has a short date span, so
    /// size and recency move together — `entry_date_range` is written per arm
    /// so the confound is measurable rather than hidden.
    private static func sweepArms(
        persona: (entries: [Entry], idByUUID: [UUID: String])?
    ) -> [Arm] {
        guard armNames.contains("sweep"), let persona else { return [] }
        let available = persona.entries.count
        return (1...max(1, min(sweepMax, available))).map { n in
            let slice = Array(persona.entries.suffix(n))
            let ids = Dictionary(uniqueKeysWithValues: slice.compactMap { entry in
                persona.idByUUID[entry.id].map { (entry.id, $0) }
            })
            return Arm(name: String(format: "size-%03d", n),
                       entries: slice,
                       fixtureIDs: ids,
                       quoteIndex: ChatEvalScoring.QuoteIndex(slice))
        }
    }

    // MARK: - Determinism

    /// FNV-1a over the run id. The same run id always draws the same length, so
    /// any conversation in the corpus can be replayed.
    private static func seed(for runID: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in runID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    private static func evenLength(_ rng: inout SplitMix64) -> Int {
        let span = maxMessages - minMessages
        let raw = minMessages + Int(rng.next() % UInt64(span + 1))
        return raw - (raw % 2)
    }

    private struct SplitMix64 {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &+ 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
    }

    // MARK: - Timeout

    private struct TurnTimedOut: Error, CustomStringConvertible {
        var description: String { "turn exceeded the time allowance" }
    }

    private static func withTimeout<T: Sendable>(
        _ duration: Duration,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TurnTimedOut()
            }
            guard let first = try await group.next() else { throw TurnTimedOut() }
            group.cancelAll()
            return first
        }
    }

    // MARK: - Rows

    private static func row(runID: String, arm: Arm,
                            persona: ConvoSimCast.Persona, intent: ConvoSimCast.Intent,
                            plannedMessages: Int, index: Int,
                            role: String, text: String, error: String? = nil) -> [String: Any] {
        var row: [String: Any] = [
            "run_id": runID,
            "arm": arm.name,
            "arm_entry_count": arm.entries.count,
            "persona_id": persona.id,
            "intent_id": intent.id,
            "planned_messages": plannedMessages,
            "turn_index": index,
            "role": role,
            "text": text,
            "recorded_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let error { row["error"] = error }
        return row
    }

    private static func encodeFacts(_ facts: [InsightFact]) -> [Any] {
        guard !facts.isEmpty,
              let data = try? JSONEncoder().encode(facts),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return decoded
    }

    /// Spec 050 R7: lets the analyzer split `hall.fabricatedQuote` by channel ×
    /// citation × pack state, and read how often the model placed markers
    /// versus wrote text the renderer had to adopt or drop.
    private static func encodeRenderStats(_ stats: ReplyRenderStats) -> [String: Any] {
        [
            "state": stats.packState.rawValue,
            "slots": stats.slotCount,
            "expanded_quotes": stats.expandedQuoteSlots,
            "expanded_dates": stats.expandedDateSlots,
            "adopted_quotes": stats.adoptedQuoteCount,
            "dropped_markers": stats.droppedMarkerCount,
            "duplicate_quotes": stats.droppedDuplicateQuoteCount,
            "stripped_italics": stats.strippedItalicCount,
            "dropped_quotations": stats.droppedQuotationCount,
            "unwrapped_bold": stats.unwrappedBoldCount,
            "stripped_dates": stats.strippedDateCount,
            "dropped_headings": stats.droppedHeadingCount,
            "stripped_scaffold": stats.strippedScaffoldCount,
            "fallback": stats.usedFallback
        ]
    }

    // MARK: - Sink

    /// Appended per message, not per run: a study that takes the better part of
    /// a day must survive being killed at hour fourteen. Same reasoning as
    /// `AgenticEval.flush`.
    private static func flush(_ row: [String: Any]) {
        let dir = outputDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(label).jsonl")
        guard let data = try? JSONSerialization.data(withJSONObject: row),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func outputDirectory() -> URL {
        if let path = env["CONVO_SIM_OUT"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return repo.appendingPathComponent(".eval-runs/convo-sim")
    }

    private static func writeManifest(arms: [Arm], started: Date,
                                      finished: Date? = nil, messages: Int? = nil) {
        let dir = outputDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        var manifest: [String: Any] = [
            "label": label,
            "started_at": iso.string(from: started),
            "runs_per_arm": runsPerArm,
            "min_messages": minMessages,
            "max_messages": maxMessages,
            "history_message_limit": ChatService.historyMessageLimit,
            "scorers": [
                "leaks", "ruleBreaks", "fabricatedQuotes", "uncitedQuote", "unbackedDate",
                "boldNotTheirWords", "runaway", "insightDigitDisagrees",
                "insightContradictsSuppressed"
            ],
            "arms": arms.map { ["name": $0.name, "entry_count": $0.entries.count,
                                "entry_date_range": $0.entryDateRange,
                                "fixture_ids": $0.fixtureIDs.values.sorted()] },
            "personas": ConvoSimCast.personas.map { ["id": $0.id, "brief": $0.brief] },
            "intents": ConvoSimCast.intents.map { ["id": $0.id, "opener": $0.opener] },
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        if armNames.contains("sweep") {
            manifest["sweep"] = [
                "max": sweepMax,
                "entry_selection": "most-recent-n of the persona corpus (suffix)",
                "cell_draw": "FNV-1a(run_id) % 100 — decorrelates question type from size",
                "sessions": min(sweepMax, 262) * runsPerArm
            ]
        }
        // A test process on a simulator has no git, so build identity is passed
        // in. Without it an archived run cannot be tied to the code that made it.
        for (key, variable) in [("git_sha", "CONVO_SIM_GIT_SHA"),
                                ("git_branch", "CONVO_SIM_GIT_BRANCH"),
                                ("git_dirty", "CONVO_SIM_GIT_DIRTY"),
                                ("notes", "CONVO_SIM_NOTES")] {
            if let value = env[variable], !value.isEmpty { manifest[key] = value }
        }
        if let finished { manifest["finished_at"] = iso.string(from: finished) }
        if let messages { manifest["messages_recorded"] = messages }
        if let data = try? JSONSerialization.data(withJSONObject: manifest,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("\(label).manifest.json"))
        }
    }
}
