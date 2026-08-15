//
//  OutputSafetyScanner.swift
//  MeetMemento
//
//  Post-generation scan of assistant text (spec 026 R7). Hits replace the
//  reply with crisis card or hard refuse — unsafe body must not persist.
//

import Foundation

struct OutputSafetyHit: Sendable, Equatable {
    let category: SafetyCategory
    let action: SafetyAction
}

enum OutputSafetyScanner {

    /// Scan model output for policy leaks (methods, weapons how-to, diagnosis,
    /// crisis counseling voice, etc.).
    static func scan(_ text: String) -> OutputSafetyHit? {
        let normalized = SafetyClassifier.normalize(text)
        guard !normalized.isEmpty else { return nil }

        if SafetyClassifier.matches(normalized, any: selfHarmMethodPatterns)
            || SafetyClassifier.matches(normalized, any: crisisCounselingPatterns) {
            return OutputSafetyHit(category: .selfHarmCrisis, action: .showCrisisCard)
        }
        if SafetyClassifier.matches(normalized, any: weaponInstructionPatterns)
            || SafetyClassifier.matches(normalized, any: violenceAssistPatterns) {
            return OutputSafetyHit(category: .violenceOthers, action: .hardRefuse)
        }
        if SafetyClassifier.matches(normalized, any: terrorismAssistPatterns) {
            return OutputSafetyHit(category: .terrorismMassViolence, action: .hardRefuse)
        }
        if SafetyClassifier.matches(normalized, any: diagnosisPatterns) {
            return OutputSafetyHit(category: .regulatedAdvice, action: .hardRefuse)
        }
        return nil
    }

    // MARK: - Output-side packs

    static let selfHarmMethodPatterns: [String] = [
        #"\b(here('s| is) how (you|to)|steps to)\b.{0,40}\b(end your life|kill yourself|suicide)\b"#,
        #"\b(lethal|fatal)\b.{0,20}\b(dose|method|means)\b"#
    ]

    static let crisisCounselingPatterns: [String] = [
        #"\b(as your (therapist|counselor)|i('m| am) (here to )?treat|coping protocol)\b"#,
        #"\b(try these (breathing|grounding) exercises|follow this safety plan)\b"#
    ]

    static let weaponInstructionPatterns: [String] = [
        #"\b(how to (build|make|assemble)|instructions for)\b.{0,40}\b(bomb|explosive|firearm|silencer)\b"#,
        #"\b(mix|combine)\b.{0,30}\b(explosive|fertilizer bomb)\b"#
    ]

    static let violenceAssistPatterns: [String] = [
        #"\b(here('s| is) how (you|to) (kill|murder|poison|stab))\b"#,
        #"\byou should (kill|attack|hurt)\b"#
    ]

    static let terrorismAssistPatterns: [String] = [
        #"\b(plan|carry out)\b.{0,30}\b(terror(ist)? attack|mass shooting)\b"#
    ]

    static let diagnosisPatterns: [String] = [
        #"\byou (have|likely have|probably have|meet the criteria for)\b.{0,40}\b(depression|bipolar|adhd|ptsd|schizophrenia|anxiety disorder)\b"#,
        #"\b(my diagnosis|clinical diagnosis)\b.{0,20}\b(is|would be)\b"#
    ]
}
