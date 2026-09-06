//
//  InsightEngine+Clusters.swift
//  MeetMemento
//
//  Embedding clusters labeled with TF-IDF. No FoundationModels.
//

import Foundation

private struct EmbeddedEntry {
    let entry: Entry
    let vector: [Double]
    let norm: Double
}

extension InsightEngine {
    /// Greedy groups over cached whole-entry vectors. Empty when NLEmbedding
    /// is unavailable (CI).
    static func clusterFacts(
        entries: [Entry], now: Date, calendar _: Calendar
    ) -> [InsightFact] {
        let service = EmbeddingService.shared
        var vectors: [EmbeddedEntry] = []
        for entry in entries {
            let hash = EmbeddingService.contentHash(title: entry.title, text: entry.text)
            if let cached = service.cachedEntryVector(id: entry.id, contentHash: hash) {
                vectors.append(EmbeddedEntry(entry: entry, vector: cached.vector, norm: cached.norm))
            }
        }
        guard vectors.count >= 3 else { return [] }

        var clusters: [[EmbeddedEntry]] = []
        for item in vectors {
            var best = -1
            var bestCosine = 0.82
            for (index, cluster) in clusters.enumerated() {
                let mean = averageCosine(item, cluster: cluster)
                if mean > bestCosine {
                    bestCosine = mean
                    best = index
                }
            }
            if best >= 0 {
                clusters[best].append(item)
            } else {
                clusters.append([item])
            }
        }

        let window = DateInterval(
            start: entries.map(\.createdAt).min() ?? now,
            end: now.addingTimeInterval(1)
        )
        let corpusTokens = vectors.map { tokens($0.entry.title + " " + $0.entry.text) }
        let documentFrequency = idfDocumentFrequency(corpusTokens)
        let corpusSize = Double(max(corpusTokens.count, 1))
        return clusters
            .filter { $0.count >= 2 }
            .sorted { $0.count > $1.count }
            .prefix(6) // budget-exempt: Patterns cluster cap, not a model payload
            .map { cluster in
                let members = cluster.map(\.entry)
                let label = clusterLabel(
                    members, documentFrequency: documentFrequency, corpusSize: corpusSize
                )
                return InsightFact(
                    kind: .cluster,
                    label: label,
                    value: "\(members.count)",
                    n: members.count,
                    window: window,
                    supportingEntryIDs: members.map(\.id)
                )
            }
    }

    private static func averageCosine(
        _ item: EmbeddedEntry,
        cluster: [EmbeddedEntry]
    ) -> Double {
        let sum = cluster.reduce(0.0) { partial, other in
            partial + EmbeddingService.cosineSimilarity(
                item.vector, normA: item.norm, other.vector, normB: other.norm
            )
        }
        return sum / Double(cluster.count)
    }

    static func idfDocumentFrequency(_ corpusTokens: [[String]]) -> [String: Int] {
        var documentFrequency: [String: Int] = [:]
        for entryTokens in corpusTokens {
            for token in Set(entryTokens) {
                documentFrequency[token, default: 0] += 1
            }
        }
        return documentFrequency
    }

    static func clusterLabel(
        _ entries: [Entry],
        documentFrequency: [String: Int],
        corpusSize: Double
    ) -> String {
        var termFrequency: [String: Int] = [:]
        for entry in entries {
            for token in tokens(entry.title + " " + entry.text) {
                termFrequency[token, default: 0] += 1
            }
        }
        let ranked = termFrequency.map { token, count -> (String, Double) in
            let frequency = Double(documentFrequency[token] ?? 1)
            let idf = log((corpusSize + 1) / (frequency + 1)) + 1
            return (token, Double(count) * idf)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(2) // budget-exempt: cluster label terms, not a model payload
        .map(\.0)
        return ranked.isEmpty ? "Related entries" : ranked.joined(separator: " · ")
    }
}
