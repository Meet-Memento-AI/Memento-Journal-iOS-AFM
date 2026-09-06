//
//  InsightEngine+Clusters.swift
//  MeetMemento
//
//  Embedding clusters labeled with TF-IDF. No FoundationModels.
//

import Foundation

extension InsightEngine {
    /// Greedy groups over cached whole-entry vectors. Empty when NLEmbedding
    /// is unavailable (CI).
    static func clusterFacts(
        entries: [Entry], now: Date, calendar _: Calendar
    ) -> [InsightFact] {
        let service = EmbeddingService.shared
        var vectors: [(Entry, [Double], Double)] = []
        for entry in entries {
            let hash = EmbeddingService.contentHash(title: entry.title, text: entry.text)
            if let cached = service.cachedEntryVector(id: entry.id, contentHash: hash) {
                vectors.append((entry, cached.vector, cached.norm))
            }
        }
        guard vectors.count >= 3 else { return [] }

        var clusters: [[(Entry, [Double], Double)]] = []
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
        let corpusTokens = vectors.map { tokens($0.0.title + " " + $0.0.text) }
        let documentFrequency = idfDocumentFrequency(corpusTokens)
        let corpusSize = Double(max(corpusTokens.count, 1))
        return clusters
            .filter { $0.count >= 2 }
            .sorted { $0.count > $1.count }
            .prefix(6)
            .map { cluster in
                let members = cluster.map(\.0)
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

    static func averageCosine(
        _ item: (Entry, [Double], Double),
        cluster: [(Entry, [Double], Double)]
    ) -> Double {
        let sum = cluster.reduce(0.0) { partial, other in
            partial + EmbeddingService.cosineSimilarity(
                item.1, normA: item.2, other.1, normB: other.2
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
        .prefix(2)
        .map(\.0)
        return ranked.isEmpty ? "Related entries" : ranked.joined(separator: " · ")
    }
}
