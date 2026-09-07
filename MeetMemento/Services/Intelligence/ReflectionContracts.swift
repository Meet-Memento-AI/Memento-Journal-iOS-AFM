//
//  ReflectionContracts.swift
//  MeetMemento
//
//  Public entry / weekly reflection types (045 R3–R4 / 017 R5). No
//  `import FoundationModels` — `@Generable` twins live in the single importer.
//

import Foundation

/// Closed mood vocabulary (technology/01). Versioned so a retag can migrate.
enum MoodLabel: String, Sendable, Codable, CaseIterable {
    case anxious, calm, frustrated, hopeful, tired, energized
    case lonely, connected, grieving, content, restless, focused

    static let vocabularyVersion = "mood@1"

    var valenceHint: Double {
        switch self {
        case .anxious, .frustrated, .lonely, .grieving, .restless, .tired:
            return -0.6
        case .calm, .content, .focused:
            return 0.4
        case .hopeful, .energized, .connected:
            return 0.7
        }
    }
}

/// Closed life-topic vocabulary (ThemeCatalog families + everyday journal topics).
enum TopicLabel: String, Sendable, Codable, CaseIterable {
    case work, rest, family, friends, health, creativity
    case growth, home, money, travel, school, community

    static let vocabularyVersion = "topic@1"
}

enum ReflectionVocabulary {
    static let version = "\(MoodLabel.vocabularyVersion)+\(TopicLabel.vocabularyVersion)"
}

/// Salience below this writes tags but no observation line (045 R3).
enum EntryReflectionPolicy {
    static let observationSalienceThreshold = 0.4

    static func shouldWriteObservation(salience: Double) -> Bool {
        salience >= observationSalienceThreshold
    }
}

/// 017 R5 fields without `@Generable` — the protocol / persist / UI shape.
struct EntryReflectionResult: Sendable, Equatable {
    var title: String
    var summary: String
    var valence: Double
    var moods: [MoodLabel]
    var topics: [TopicLabel]
    var salience: Double
    var vocabularyVersion: String
    var promptVersion: String

    init(
        title: String,
        summary: String,
        valence: Double,
        moods: [MoodLabel],
        topics: [TopicLabel],
        salience: Double,
        vocabularyVersion: String = ReflectionVocabulary.version,
        promptVersion: String = "entry-reflect@1"
    ) {
        self.title = title
        self.summary = summary
        self.valence = min(1, max(-1, valence))
        self.moods = Array(moods.prefix(3)) // budget-exempt: closed-vocab cap, not a model payload
        self.topics = Array(topics.prefix(4)) // budget-exempt: closed-vocab cap, not a model payload
        self.salience = min(1, max(0, salience))
        self.vocabularyVersion = vocabularyVersion
        self.promptVersion = promptVersion
    }
}

/// 017 R5 period reflection without `@Generable`.
struct PeriodReflectionResult: Sendable, Equatable {
    var body: String
    var observation: String
    var groundedEntryIDs: [UUID]
    var hasNothingToSay: Bool
    var promptVersion: String

    init(
        body: String,
        observation: String,
        groundedEntryIDs: [UUID],
        hasNothingToSay: Bool,
        promptVersion: String = "weekly@1"
    ) {
        self.body = body
        self.observation = observation
        self.groundedEntryIDs = groundedEntryIDs
        self.hasNothingToSay = hasNothingToSay
        self.promptVersion = promptVersion
    }
}

enum FactMagnitude {
    /// Prompt-facing sample-size words. Never digits (045 R4).
    static func word(for n: Int) -> String {
        switch n {
        case 0: return "none"
        case 1: return "one"
        case 2, 3: return "a few"
        default: return "several"
        }
    }
}
