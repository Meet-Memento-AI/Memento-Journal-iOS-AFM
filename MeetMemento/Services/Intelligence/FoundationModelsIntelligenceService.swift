//
//  FoundationModelsIntelligenceService.swift
//  MeetMemento
//
//  THE single Apple Foundation Models importer (architecture principle P3 /
//  REQ-INT-001, spec 017 R1). Nothing else in the app imports FoundationModels;
//  everything depends on the `IntelligenceService` protocol. If a second file
//  imports FoundationModels, the CI gate
//  (scripts/ci/check_single_intelligence_importer.sh) fails.
//
//  This pass: on-device (`SystemLanguageModel`, Z0) generation for Ask + Chat
//  summary, replacing the former server-side `chat` / `summarize-chat` functions.
//  The Private Cloud Compute (Z1) path is wired behind `if #available(iOS 27)`
//  + availability so it auto-upgrades once the app is approved (spec 017 R2).
//

import Foundation
import FoundationModels

// MARK: - Structured output (guided generation, no JSON parsing) — spec 017 R5

/// The Ask reply, produced by constrained decoding. `citedRefs` are the [ref]
/// numbers from the context block the model actually used — reconciled against
/// the provided set so a citation can never be fabricated.
@Generable
struct AskAnswer {
    @Guide(description: "Optional short heading for analytical, multi-part answers. Empty for casual replies.")
    let heading1: String?

    @Guide(description: "Optional rare subheading. Usually empty.")
    let heading2: String?

    @Guide(description: "The reply, in plain spoken prose — no markdown, no bullet points, no headings, no emoji. Second person. Three to ten sentences.")
    let body: String

    @Guide(description: "The [ref] numbers of the journal entries from the context block that were actually referenced. Empty if none.")
    let citedRefs: [Int]
}

/// Closed-vocab onboarding estimate. Theme ids are reconciled against ThemeCatalog in Swift.
@Generable
struct ProfileEstimateAnswer {
    @Guide(description: "3 to 4 primary theme ids from the provided catalog only.")
    let themeIds: [String]

    @Guide(description: "Up to 2 secondary theme ids from the catalog. May be empty.")
    let secondaryThemeIds: [String]

    @Guide(description: "1 to 3 short third-person sentences guiding tone and questions. Under 400 characters. No therapy language.")
    let promptLens: String
}

// MARK: - Service

final class FoundationModelsIntelligenceService: IntelligenceService, @unchecked Sendable {
    static let shared = FoundationModelsIntelligenceService()

    init() {}

    // MARK: Availability

    func availability() async -> IntelligenceAvailability {
        // On-device (Z0) only against the iOS 26 SDK. The Private Cloud Compute
        // (Z1) path — `PrivateCloudComputeLanguageModel`, reasoning levels, quota
        // governance (spec 017 R2/R3) — is an iOS-27-SDK type; it re-enables when
        // the app builds against Xcode 27 and is approved for PCC. On-device-first.
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available(.onDevice)
        case .unavailable(let reason):
            return .unavailable(Self.map(reason))
        @unknown default:
            return .unavailable(.other("Intelligence is unavailable on this device."))
        }
    }

    private static func map(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> IntelligenceUnavailableReason {
        switch reason {
        case .deviceNotEligible: return .deviceNotEligible
        case .appleIntelligenceNotEnabled: return .modelNotReady
        case .modelNotReady: return .modelNotReady
        @unknown default: return .other("On-device intelligence is unavailable right now.")
        }
    }

    // MARK: Ask

    func ask(_ question: String, history: [ChatTurn], entries: [Entry]) async throws -> AskResult {
        let availability = await availability()
        guard case .available(let zone) = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        // Conversational turn architecture: classify the current message,
        // decide retrieval by policy, then hand the model an explicit stance —
        // logic decides the stance, the prompt obeys it.
        let turn = TurnClassifier.classify(question, hasHistory: !history.isEmpty)
        let retrieval: RetrievalResult
        switch RetrievalPolicy.mode(for: turn) {
        case .none:
            retrieval = .empty
        case .reusePrevious:
            // Stateless re-derivation of the previous grounding: retrieval is
            // deterministic and entry vectors are cached, so re-querying with
            // the last substantive user turn reproduces it.
            if let anchor = RetrievalPolicy.followupAnchor(history: history) {
                retrieval = EntryRetriever.retrieve(RetrievalQuery(currentMessage: anchor), entries: entries)
            } else {
                retrieval = EntryRetriever.retrieve(
                    RetrievalQuery(currentMessage: question, historyContext: Self.historyContext(history)),
                    entries: entries
                )
            }
        case .currentOnly(let highBar):
            retrieval = EntryRetriever.retrieve(RetrievalQuery(currentMessage: question, highBar: highBar), entries: entries)
        case .currentWeighted:
            retrieval = EntryRetriever.retrieve(
                RetrievalQuery(currentMessage: question, historyContext: Self.historyContext(history)),
                entries: entries
            )
        }
        let stance = RetrievalPolicy.stance(turn: turn, retrieval: retrieval)
        let prompt = Self.buildAskPrompt(question: question, history: history, retrieval: retrieval, stance: stance)

        // On-device (Z0). PCC (Z1) uses the same call site with a different model;
        // for this pass we run on-device — a degraded prompt variant would be used
        // for the smaller model if we were falling back from a PCC prompt.
        let resolved = PromptRegistry.instructions(
            for: .ask,
            degraded: false,
            personalization: PromptPersonalization.fromLocalProfile()
        )
        let session = LanguageModelSession(instructions: resolved.text)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: AskAnswer.self,
                options: GenerationOptions(temperature: 0.7)
            )
            let answer = response.content
            let citations = Self.reconcileCitations(
                answer.citedRefs,
                retrieval: retrieval,
                question: question,
                grounded: stance.isGrounded
            )
            return AskResult(
                heading1: answer.heading1?.isEmpty == true ? nil : answer.heading1,
                heading2: answer.heading2?.isEmpty == true ? nil : answer.heading2,
                body: answer.body,
                citations: citations,
                zoneUsed: zone,
                wasDegraded: false,
                promptVersion: resolved.version,
                modelIdentifier: Self.modelIdentifier(for: zone)
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        } catch {
            throw IntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: Profile estimate (onboarding)

    func estimateProfile(reflection: String) async throws -> ProfileEstimateResult {
        let availability = await availability()
        guard case .available(let zone) = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        let trimmed = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IntelligenceError.generationFailed("Reflection text is empty.")
        }

        let resolved = PromptRegistry.instructions(for: .profileEstimate, degraded: false)
        let session = LanguageModelSession(instructions: resolved.text)
        let prompt = Self.buildProfileEstimatePrompt(reflection: trimmed)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: ProfileEstimateAnswer.self,
                options: GenerationOptions(temperature: 0.4)
            )
            let answer = response.content
            let primary = ThemeCatalog.validate(answer.themeIds, max: ThemeCatalog.defaultSuggestionCount)
            let secondary = ThemeCatalog.validate(answer.secondaryThemeIds, max: 2)
                .filter { !primary.contains($0) }
            var lens = answer.promptLens.trimmingCharacters(in: .whitespacesAndNewlines)
            if lens.count > PromptRegistry.maxPromptLensChars {
                lens = String(lens.prefix(PromptRegistry.maxPromptLensChars))
            }
            // If the model returned nothing usable, fall back to keyword overlap.
            let themes = primary.isEmpty
                ? ThemeCatalog.suggestFromKeywords(trimmed)
                : primary
            return ProfileEstimateResult(
                themeIds: themes,
                secondaryThemeIds: secondary,
                promptLens: lens,
                zoneUsed: zone,
                wasDegraded: false,
                promptVersion: resolved.version,
                modelIdentifier: Self.modelIdentifier(for: zone)
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        } catch {
            throw IntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    private static func buildProfileEstimatePrompt(reflection: String) -> String {
        // Compact catalog projection — id + display name only — to protect context.
        let catalogLines = ThemeCatalog.all
            .map { "\($0.id): \($0.displayName)" }
            .joined(separator: "\n")
        let cappedReflection = reflection.count > 800
            ? String(reflection.prefix(800)) + "…"
            : reflection
        return """
        Catalog (id: DisplayName) — choose only from these ids:
        \(catalogLines)

        Their reflection:
        \"\(cappedReflection)\"
        """
    }

    // MARK: Summarize

    func summarizeConversation(_ turns: [ChatTurn]) async throws -> String {
        let availability = await availability()
        guard case .available = availability else {
            if case .unavailable(let reason) = availability { throw IntelligenceError.unavailable(reason) }
            throw IntelligenceError.unavailable(.other("Intelligence is unavailable right now."))
        }

        let resolved = PromptRegistry.instructions(for: .summary)
        let session = LanguageModelSession(instructions: resolved.text)
        let conversation = turns.map { turn in
            (turn.role == .user ? "User: " : "Assistant: ") + turn.text
        }.joined(separator: "\n")
        let prompt = "Here is the conversation to summarize:\n\n\(conversation)"

        do {
            let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.7))
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        } catch {
            throw IntelligenceError.generationFailed(error.localizedDescription)
        }
    }

    // MARK: - Prompt assembly

    /// Recent history condensed for the retrieval assist vector (not the prompt).
    private static func historyContext(_ history: [ChatTurn]) -> String? {
        guard !history.isEmpty else { return nil }
        let condensed = history.suffix(4).map { String($0.text.prefix(300)) }.joined(separator: " ")
        return condensed.isEmpty ? nil : condensed
    }

    private static func buildAskPrompt(question: String, history: [ChatTurn], retrieval: RetrievalResult, stance: TurnStance) -> String {
        // The stance line is the first thing the model reads for this turn —
        // the deterministic instruction that stops it from grounding casual
        // conversation in journal entries.
        var parts: [String] = [stance.promptLine]
        if !retrieval.contextBlock.isEmpty {
            parts.append(retrieval.contextBlock)
        } else if stance == .noMatch || stance.isGrounded {
            parts.append("[No journal entries matched this topic]")
        }
        // Casual / about-app / outside-scope / sharing-without-context turns get
        // no journal block at all — the stance line already says how to reply.
        // The conversation so far, for continuity (recent turns, each trimmed to
        // protect the on-device context budget). More than a couple of turns so
        // the model holds the thread and doesn't re-greet.
        let recent = history.suffix(8)
        if !recent.isEmpty {
            let convo = recent
                .map { ($0.role == .user ? "You: " : "Memento: ") + String($0.text.prefix(400)) }
                .joined(separator: "\n")
            parts.append("Conversation so far (most recent last):\n\(convo)")
        }
        parts.append("The person's latest message: \(question)")
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Citation reconciliation (the anti-fabrication guard)

    private static let maxCitations = 3

    private static func reconcileCitations(_ refs: [Int], retrieval: RetrievalResult, question: String, grounded: Bool) -> [AskCitation] {
        guard !retrieval.isEmpty else { return [] }
        let byRef = Dictionary(uniqueKeysWithValues: retrieval.entries.map { ($0.ref, $0) })
        // Intersect the model's refs with the ones actually provided. The
        // cited-nothing → top-entries fallback only applies to grounded turns:
        // on casual/sharing turns empty citations are correct, and forcing
        // pills onto them was part of the "always grounded" feel.
        let chosenRefs: [Int]
        if refs.isEmpty {
            chosenRefs = grounded ? retrieval.entries.prefix(maxCitations).map(\.ref) : []
        } else {
            var seen = Set<Int>()
            chosenRefs = refs.filter { byRef[$0] != nil && seen.insert($0).inserted }
        }
        return chosenRefs.prefix(maxCitations).compactMap { ref in
            guard let entry = byRef[ref] else { return nil }
            return AskCitation(
                entryId: entry.id,
                entryDate: entry.date,
                excerpt: Self.previewExcerpt(entry.text, query: question)
            )
        }
    }

    private static func previewExcerpt(_ text: String, query: String, window: Int = 120) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > window else { return clean }
        // Center on the first query-term hit, else take the start.
        let terms = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 }
        let lower = clean.lowercased()
        var start = clean.startIndex
        for term in terms {
            if let r = lower.range(of: term) {
                start = r.lowerBound
                break
            }
        }
        let from = clean.index(start, offsetBy: -min(30, clean.distance(from: clean.startIndex, to: start)), limitedBy: clean.startIndex) ?? clean.startIndex
        let to = clean.index(from, offsetBy: window, limitedBy: clean.endIndex) ?? clean.endIndex
        var excerpt = String(clean[from..<to])
        if from != clean.startIndex { excerpt = "…" + excerpt }
        if to != clean.endIndex { excerpt += "…" }
        return excerpt
    }

    // MARK: - Errors & identifiers

    private static func mapGenerationError(_ error: LanguageModelSession.GenerationError) -> IntelligenceError {
        // Guardrail refusals are a *designed* empty state, not a failure.
        switch error {
        case .guardrailViolation:
            return .guardrailRefusal
        default:
            return .generationFailed(error.localizedDescription)
        }
    }

    private static func modelIdentifier(for zone: IntelligenceZone) -> String {
        switch zone {
        case .onDevice: return "apple.system.on-device"
        case .privateCloud: return "apple.pcc"
        }
    }
}
