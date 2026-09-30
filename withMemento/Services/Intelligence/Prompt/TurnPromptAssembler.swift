//
//  TurnPromptAssembler.swift
//  withMemento
//
//  Pure Ask user-prompt assembly (spec 017 / MT1). No `import FoundationModels`.
//  `FoundationModelsIntelligenceService.buildAskPrompt` forwards here so FMIS
//  stays the single SDK adapter.
//
//  SwiftLint: same carve-out as `FoundationModelsIntelligenceService.swift`
//  (`.swiftlint.yml` + `scripts/ci/lint_changed_swift.sh`). Monolithic until
//  CQ4–CQ7 split this further.
// swiftlint:disable function_body_length cyclomatic_complexity function_parameter_count line_length control_statement multiline_arguments

import Foundation

/// Typed plan for one Ask user prompt. `parts` join with `\n\n` for the model.
// periphery:ignore - golden-test metadata; FMIS reads channel/stance/pack for parity (MEM-329)
struct TurnPromptPlan: Equatable, Sendable {
    // periphery:ignore - joined by `prompt`; asserted in TurnPromptGoldenSnapshotTests (MEM-329)
    let parts: [String]
    // periphery:ignore - plan metadata read in FMIS and golden tests (MEM-329)
    let channel: ReplyChannel
    // periphery:ignore - plan metadata read in FMIS and golden tests (MEM-329)
    let effectiveStance: TurnStance?
    // periphery:ignore - plan metadata read in FMIS and golden tests (MEM-329)
    let evidencePack: EvidencePack?

    // periphery:ignore - primary production surface via FMIS.buildAskPrompt (MEM-329)
    var prompt: String { parts.joined(separator: "\n\n") }
}

enum TurnPromptAssembler {

    /// Same format as `EntryRetriever.formattedDate` plus the weekday, so the
    /// model can compare this line against `[ref N | March 12, 2026]` directly
    /// and resolve a weekday name without arithmetic it cannot do.
    static func todayLine(now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return "Today is \(formatter.string(from: now))."
    }

    static func stanceMatchingEvidence(
        _ stance: TurnStance, hasEvidenceBlock: Bool, archiveEmpty: Bool = false
    ) -> TurnStance {
        if archiveEmpty { return stance }
        switch stance {
        case .nearbyOnly where !hasEvidenceBlock: return .noMatch
        default: return stance
        }
    }

    static func plan(
        question: String,
        history: [ChatTurn],
        retrieval: RetrievalResult,
        stance: TurnStance,
        shape: RecallTurnShape,
        archiveEmpty: Bool,
        safetyConstrained: Bool = false,
        imageCount: Int = 0,
        historyImageCount: Int = 0,
        canSeeImages: Bool = false,
        visionBlock: String? = nil,
        channel: ReplyChannel = .companion,
        move: ConversationalMove? = nil,
        personalization: PromptPersonalization = .none,
        spoken: Bool = false,
        computedFacts: [InsightFact] = [],
        policy: ResponsePolicy? = nil,
        retracted: [String] = [],
        interpretationCut: Bool = false,
        evidencePack: EvidencePack? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TurnPromptPlan {
        if channel.usesShortAssembler {
            let fallbackMove: ConversationalMove = channel.usesLightPrompt
                ? .greetAndAsk : .reflectAndAsk
            let cue = move?.cueLine ?? fallbackMove.cueLine
            var light: [String] = [cue, todayLine(now: now, calendar: calendar)]
            if safetyConstrained {
                light.insert(SafetyRouter.constrainedStanceLine, at: 0)
            }
            let usedNameLastTurn = personalization.lastAssistantTurnContainsName(history)
            let skipName = move?.avoidsName == true || usedNameLastTurn
            if channel.omitsLens {
                if !skipName, let name = personalization.nameCueLine {
                    light.append(name)
                }
                if skipName, personalization.spokenName != nil {
                    light.append(PromptPersonalization.nameSkipLine)
                }
            }
            if spoken, channel == .continuer || channel.usesCompanionPrompt,
               let answering = ConversationalMove.answeringLastQuestionLine(from: history) {
                light.append(answering)
            }
            if let anti = ConversationalMove.antiRepeatLine(from: history) {
                light.append(anti)
            }
            light.append("The person's latest message: \(question)")
            if let policy {
                light.append(PromptRegistry.policySuffix(policy, interpretationCut: interpretationCut))
            }
            if let retractedLine = RetractedClaims.promptLine(
                claims: retracted, interpretationCut: interpretationCut
            ) {
                light.append(retractedLine)
            }
            return TurnPromptPlan(
                parts: light, channel: channel, effectiveStance: nil, evidencePack: nil
            )
        }

        let pack = evidencePack ?? EvidencePackBuilder.build(
            retrieval: retrieval, stance: stance, channel: channel, archiveEmpty: archiveEmpty
        )
        let hasEvidenceBlock = pack.carriesEvidence
        let effectiveStance = stanceMatchingEvidence(
            stance, hasEvidenceBlock: hasEvidenceBlock, archiveEmpty: archiveEmpty
        )
        var parts: [String] = [effectiveStance.promptLine, todayLine(now: now, calendar: calendar)]
        if NoMatchLead.applies(to: effectiveStance, channel: channel) {
            parts.append(NoMatchLead.promptLine)
        }
        if channel == .notebook || channel == .thread {
            let shipped = hasEvidenceBlock ? retrieval : .empty
            let rung = EvidenceLadder.rung(stance: effectiveStance, retrieval: shipped, question: question)
            parts.append(EvidenceLadder.promptLine(rung, retrieval: shipped, pack: pack))
        }
        let grounded = effectiveStance.isGrounded(retrieval: retrieval)
        if let overlay = TurnShapeCadence.overlayLine(
            shape: shape,
            stance: effectiveStance,
            isGrounded: grounded
        ) {
            parts.append(overlay)
        }
        if spoken {
            parts.append(PromptRegistry.spokenTurnShapeLine)
            if let answering = ConversationalMove.answeringLastQuestionLine(from: history) {
                parts.append(answering)
            }
            if let anti = ConversationalMove.antiRepeatLine(from: history) {
                parts.append(anti)
            }
        }
        if safetyConstrained {
            parts.insert(SafetyRouter.constrainedStanceLine, at: 0)
        }
        let usedNameLastTurn = personalization.lastAssistantTurnContainsName(history)
        let skipName = move?.avoidsName == true || usedNameLastTurn
        if channel.omitsLens, !skipName, let name = personalization.nameCueLine {
            parts.append(name)
        }
        if channel == .notebook, let computed = ComputedFactsBlock.render(computedFacts) {
            parts.append(computed)
        }
        if hasEvidenceBlock {
            let framing = "Journal entries for this turn (use only what this turn needs; do not summarize all of them):\n"
            parts.append(framing + EvidencePack.promptContextBlock(retrieval.contextBlock))
        } else if effectiveStance == .noMatch || grounded {
            if archiveEmpty {
                parts.append("There are no journal entries yet.")
            } else {
                parts.append("No journal entries matched this topic.")
            }
        }
        if let legend = pack.promptLegend(channel: channel) {
            parts.append(legend)
        }
        if !history.isEmpty {
            parts.append(
                "Do not reuse openings, questions, or entry summaries you already used "
                    + "earlier in this conversation. Do not reopen an entry you already used "
                    + "in this thread."
            )
        }
        if skipName, personalization.spokenName != nil {
            parts.append(PromptPersonalization.nameSkipLine)
        }
        if imageCount > 0 || historyImageCount > 0 {
            if canSeeImages {
                var vision: [String] = []
                if historyImageCount > 0 {
                    vision.append(
                        "Earlier messages in this conversation included photos, labeled earlier-turn-N-photo-M. If they ask about those photos, look at them."
                    )
                }
                if imageCount > 0 {
                    vision.append(
                        "The person attached \(imageCount) photo\(imageCount == 1 ? "" : "s") to this message, labeled this-message-photo-1… in order. Look at each image. Ground what you say in what is visibly there. Refer to them as \"this photo\" or \"the first photo\" when it helps. Do not invent details that are not visible."
                    )
                }
                parts.append(vision.joined(separator: " "))
            } else if let visionBlock, !visionBlock.isEmpty {
                parts.append(
                    "The person attached photo\(imageCount + historyImageCount == 1 ? "" : "s"). A visual reading of each follows. Treat it as what is in the images. Refer to them as \"this photo\" or \"the first photo\" when it helps. Do not invent details beyond this reading and what they wrote.\n\n"
                    + visionBlock
                )
            } else {
                parts.append(
                    "The person attached photo\(imageCount + historyImageCount == 1 ? "" : "s"). Image understanding is not available on this device, so you cannot see them. Acknowledge the attachment without describing what you cannot see."
                )
            }
        }
        parts.append("The person's latest message: \(question)")
        if let policy {
            parts.append(PromptRegistry.policySuffix(policy, interpretationCut: interpretationCut))
        }
        if let retractedLine = RetractedClaims.promptLine(
            claims: retracted, interpretationCut: interpretationCut
        ) {
            parts.append(retractedLine)
        }
        return TurnPromptPlan(
            parts: parts, channel: channel, effectiveStance: effectiveStance, evidencePack: pack
        )
    }
}
// swiftlint:enable function_body_length cyclomatic_complexity function_parameter_count line_length control_statement multiline_arguments
