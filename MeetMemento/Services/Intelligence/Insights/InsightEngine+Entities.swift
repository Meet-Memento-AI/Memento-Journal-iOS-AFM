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
        entries: [Entry], now: Date, calendar: Calendar
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
        let window = DateInterval(
            start: entries.map(\.createdAt).min() ?? now,
            end: now.addingTimeInterval(1)
        )
        let personFacts = people
            .sorted { $0.value.count > $1.value.count }
            .prefix(8)
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
            .sorted { $0.value.count > $1.value.count }
            .prefix(8)
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

    static func namedEntityValue(_ hits: [Entry]) -> String {
        let dates = hits.map(\.createdAt).sorted()
        guard let first = dates.first, let last = dates.last else { return "\(hits.count)" }
        if first == last {
            return "\(hits.count) · \(EntryRetriever.formattedDate(first))"
        }
        return "\(hits.count) · \(EntryRetriever.formattedDate(first))–\(EntryRetriever.formattedDate(last))"
    }
}
