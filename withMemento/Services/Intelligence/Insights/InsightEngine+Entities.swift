//
//  InsightEngine+Entities.swift
//  MeetMemento
//
//  NLTagger people / places. No FoundationModels.
//

import Foundation
import NaturalLanguage

extension InsightEngine {
    static func namedEntityFacts(
        entries: [Entry], now: Date, calendar _: Calendar
    ) -> [InsightFact] {
        var people: [String: [Entry]] = [:]
        var places: [String: [Entry]] = [:]
        let tagger = NLTagger(tagSchemes: [.nameType])
        for entry in entries {
            let blob = entry.title + " " + entry.text
            tagger.string = blob
            tagger.enumerateTags(
                in: blob.startIndex..<blob.endIndex,
                unit: .word,
                scheme: .nameType,
                options: [.omitWhitespace, .omitPunctuation, .joinNames]
            ) { tag, range in
                guard let tag else { return true }
                let name = String(blob[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.count >= 2 else { return true }
                switch tag {
                case .personalName:
                    people[name, default: []].append(entry)
                case .placeName:
                    places[name, default: []].append(entry)
                default:
                    break
                }
                return true
            }
        }
        let window = orderedInterval(
            start: entries.map(\.createdAt).min() ?? now,
            end: now.addingTimeInterval(1)
        )
        let personFacts = people
            .map { (name: $0.key, hits: uniquedEntries($0.value)) }
            .sorted { $0.hits.count > $1.hits.count }
            .prefix(8) // budget-exempt: Patterns people/places cap, not a model payload
            .map { name, hits in
                InsightFact(
                    kind: .person,
                    label: name,
                    value: namedEntityValue(hits),
                    n: hits.count,
                    window: window,
                    supportingEntryIDs: hits.map(\.id)
                )
            }
        let placeFacts = places
            .map { (name: $0.key, hits: uniquedEntries($0.value)) }
            .sorted { $0.hits.count > $1.hits.count }
            .prefix(8) // budget-exempt: Patterns people/places cap, not a model payload
            .map { name, hits in
                InsightFact(
                    kind: .place,
                    label: name,
                    value: namedEntityValue(hits),
                    n: hits.count,
                    window: window,
                    supportingEntryIDs: hits.map(\.id)
                )
            }
        return Array(personFacts) + Array(placeFacts)
    }

    /// n is unique entries, not mention count — "Dario" twice in one note is n=1.
    static func uniquedEntries(_ entries: [Entry]) -> [Entry] {
        var seen = Set<UUID>()
        return entries.filter { seen.insert($0.id).inserted }
    }

    static func namedEntityValue(_ hits: [Entry]) -> String {
        let dates = hits.map(\.createdAt).sorted()
        guard let first = dates.first, let last = dates.last else { return "\(hits.count)" }
        if first == last {
            return "\(hits.count) · \(EntryRetriever.formattedDate(first))"
        }
        return "\(hits.count) · \(EntryRetriever.formattedDate(first))–\(EntryRetriever.formattedDate(last))"
    }
}
