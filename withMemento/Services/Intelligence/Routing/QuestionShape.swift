//
//  QuestionShape.swift
//  withMemento
//
//  What the person is asking, decided from their words before the model runs.
//

import Foundation

enum QuestionShape: String, Sendable, Equatable {
    case inventory
    case temporal
    case entity
    case advice
    case list
    case venting
    case goodbye
    case correction
    case interpretationCut
    case specific
}

enum QuestionShapeResolver {

    static func shape(of message: String, turn: TurnType) -> QuestionShape {
        let q = message.lowercased()
        if isGoodbye(q) || (turn == .social && isGoodbye(q)) { return .goodbye }
        if isInterpretationCut(q) { return .interpretationCut }
        if isCorrection(q) || turn == .correction { return .correction }
        if isAdvice(q) { return .advice }
        if isList(q) { return .list }
        if EvidenceLadder.isInventory(q) { return .inventory }
        if isTemporal(q) { return .temporal }
        if isEntity(q) { return .entity }
        if turn == .share || turn == .reflectiveQuestion { return .venting }
        return .specific
    }

    private static func isGoodbye(_ q: String) -> Bool {
        let cues = ["bye", "goodbye", "goodnight", "good night", "see you", "talk soon"]
        return cues.contains { q == $0 || q.hasPrefix($0 + " ") || q.hasPrefix($0 + ",") }
    }

    private static func isCorrection(_ q: String) -> Bool {
        let cues = [
            "that's not what happened", "thats not what happened",
            "you got that wrong", "you got this wrong", "you got it wrong",
            "that's wrong", "thats wrong", "you're wrong", "you are wrong"
        ]
        return cues.contains { q.contains($0) }
    }

    private static func isInterpretationCut(_ q: String) -> Bool {
        let cues = [
            "reading too much", "too vague", "too soft", "you keep calling"
        ]
        return cues.contains { q.contains($0) }
    }

    private static func isAdvice(_ q: String) -> Bool {
        let cues = [
            "what should i do", "what would you do", "what are my options",
            "give me a plan", "give me some options"
        ]
        return cues.contains { q.contains($0) }
    }

    private static func isList(_ q: String) -> Bool {
        q.contains("next-step") || q.contains("next step") || q.contains("give me a list")
            || q.contains("a list of")
    }

    private static func isTemporal(_ q: String) -> Bool {
        q.contains("last tuesday") || q.contains("before the ") || q.contains("yesterday")
            || q.contains("last week") || q.contains("last month")
    }

    private static func isEntity(_ q: String) -> Bool {
        q.hasPrefix("who is ") || q.hasPrefix("who's ") || q.contains("who is ")
    }
}
