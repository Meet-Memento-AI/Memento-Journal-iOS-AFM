//
//  JournalSchema.swift
//  MeetMemento
//
//  Spec 015 R1: SwiftData schema for the 2.0 store. UI still uses the
//  `Entry` value type; these `@Model` types are the mirrored records.
//  CloudKit deltas: every stored property is optional or defaulted, no
//  `@Attribute(.unique)`, relationships have inverses, enums are raw values.
//

import Foundation
import SwiftData

enum CaptureSource: String, Codable, Sendable {
    case voice, text, suggestion
}

enum IndexState: String, Codable, Sendable {
    case pending, indexed, excluded
}

enum ReflectionKind: String, Codable, Sendable {
    case entry, weekly, monthly
}

enum TurnRole: String, Codable, Sendable {
    case user, assistant
}

enum ReflectionRating: String, Codable, Sendable {
    case up, down
}

enum SleepBucket: String, Codable, Sendable {
    case underSix, sixToEight, overEight
}

struct HealthSnapshot: Codable, Sendable, Equatable {
    var sleepBucket: SleepBucket?
    var workoutOccurred: Bool?
    var stateOfMindValence: Double?

    var hasAnyValue: Bool {
        sleepBucket != nil || workoutOccurred != nil || stateOfMindValence != nil
    }

    var z0SummaryLine: String {
        var parts: [String] = []
        if let sleepBucket {
            parts.append("sleep \(sleepBucket.rawValue)")
        }
        if workoutOccurred == true {
            parts.append("moved today")
        }
        return parts.joined(separator: ", ")
    }
}

@Model
final class StoredEntry {
    var id: UUID = UUID()
    var title: String = ""
    var transcript: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sourceRaw: String = CaptureSource.text.rawValue
    var indexStateRaw: String = IndexState.pending.rawValue
    var excludedFromIndex: Bool = true
    var isFavorite: Bool = false
    var moodLabels: [String] = []
    var audioAssetID: String?
    var healthJSON: Data?
    @Relationship(deleteRule: .cascade, inverse: \StoredAttachment.entry)
    var attachments: [StoredAttachment]? = []
    @Relationship(inverse: \StoredReflection.entries)
    var reflections: [StoredReflection]? = []

    var source: CaptureSource {
        get { CaptureSource(rawValue: sourceRaw) ?? .text }
        set { sourceRaw = newValue.rawValue }
    }

    var indexState: IndexState {
        get { IndexState(rawValue: indexStateRaw) ?? .pending }
        set { indexStateRaw = newValue.rawValue }
    }

    init() {}
}

@Model
final class StoredAttachment {
    var id: UUID = UUID()
    var kind: String = "photo"
    var fileAssetID: String?
    var entry: StoredEntry?

    init() {}
}

@Model
final class StoredReflection {
    var id: UUID = UUID()
    var kindRaw: String = ReflectionKind.entry.rawValue
    var body: String = ""
    var createdAt: Date = Date()
    var zoneRaw: String = "z0Device"
    var audioAssetID: String?
    var ratingRaw: String?
    var entries: [StoredEntry]? = []
    @Relationship(deleteRule: .cascade, inverse: \StoredCitation.reflection)
    var citations: [StoredCitation]? = []

    var kind: ReflectionKind {
        get { ReflectionKind(rawValue: kindRaw) ?? .entry }
        set { kindRaw = newValue.rawValue }
    }

    init() {}
}

@Model
final class StoredCitation {
    var id: UUID = UUID()
    var entryID: UUID = UUID()
    var quotedSpan: String = ""
    var reflection: StoredReflection?
    var turn: StoredTurn?

    init() {}
}

@Model
final class StoredConversation {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \StoredTurn.conversation)
    var turns: [StoredTurn]? = []

    init() {}
}

@Model
final class StoredTurn {
    var id: UUID = UUID()
    var roleRaw: String = TurnRole.user.rawValue
    var text: String = ""
    var createdAt: Date = Date()
    var zoneRaw: String = "z0Device"
    var wasDegraded: Bool = false
    var conversation: StoredConversation?
    @Relationship(deleteRule: .cascade, inverse: \StoredCitation.turn)
    var citations: [StoredCitation]? = []

    var role: TurnRole {
        get { TurnRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }

    init() {}
}

enum JournalSchema {
    static let models: [any PersistentModel.Type] = [
        StoredEntry.self,
        StoredAttachment.self,
        StoredReflection.self,
        StoredCitation.self,
        StoredConversation.self,
        StoredTurn.self
    ]

    static var schema: Schema { Schema(models) }

    static let cloudKitContainerID = "iCloud.com.sebastianmendo.MeetMemento"
}
