import Foundation
@testable import withMemento

/// RT1 metrics: `TurnClassifier` vs cast gold fixture (report-only).
struct TurnKindCastMetrics: Equatable {
    let rowCount: Int
    let matchCount: Int
    let mismatchCount: Int
    var agreementRate: Double {
        rowCount == 0 ? 0 : Double(matchCount) / Double(rowCount)
    }
    var mismatchRate: Double {
        rowCount == 0 ? 0 : Double(mismatchCount) / Double(rowCount)
    }
    let predictedFollowupShare: Double
    let goldFollowupShare: Double
    let followupShareDeltaPoints: Double
    let predictedCounts: [String: Int]
    let goldCounts: [String: Int]
}

enum TurnKindCastReport {

    static func predicted(for row: TurnKindGoldFixture.Row) -> TurnType {
        TurnClassifier.classify(
            row.text,
            hasHistory: row.hasHistory,
            lastAssistantAskedQuestion: row.lastAssistantAskedQuestion
        )
    }

    static func metrics(rows: [TurnKindGoldFixture.Row]) -> TurnKindCastMetrics {
        var matchCount = 0
        var predictedCounts: [String: Int] = [:]
        var goldCounts: [String: Int] = [:]

        let valid = rows.compactMap { row -> (TurnKindGoldFixture.Row, TurnType)? in
            guard let goldType = TurnKindGoldFixture.goldTurnType(for: row) else { return nil }
            return (row, goldType)
        }

        for (row, goldType) in valid {
            let pred = predicted(for: row)
            goldCounts[goldType.rawValue, default: 0] += 1
            predictedCounts[pred.rawValue, default: 0] += 1
            if pred == goldType { matchCount += 1 }
        }

        let n = valid.count
        let mismatch = n - matchCount
        let predFollow = Double(predictedCounts["followup", default: 0]) / Double(max(n, 1))
        let goldFollow = Double(goldCounts["followup", default: 0]) / Double(max(n, 1))
        return TurnKindCastMetrics(
            rowCount: n,
            matchCount: matchCount,
            mismatchCount: mismatch,
            predictedFollowupShare: predFollow,
            goldFollowupShare: goldFollow,
            followupShareDeltaPoints: (predFollow - goldFollow) * 100,
            predictedCounts: predictedCounts,
            goldCounts: goldCounts
        )
    }

    static func violations(for row: TurnKindGoldFixture.Row) -> [ChatEvalScoring.Violation] {
        guard let gold = TurnKindGoldFixture.goldTurnType(for: row) else { return [] }
        let pred = predicted(for: row)
        return ChatEvalScoring.turnKindMismatch(predicted: pred, gold: gold)
    }

    static func renderMarkdown(_ metrics: TurnKindCastMetrics, fixture: TurnKindGoldFixture.File) -> String {
        var out = "# RT1 turn-kind cast gold (report-only)\n\n"
        out += "Source: `\(fixture.source)` — \(fixture.study)\n\n"
        out += "Rows: **\(metrics.rowCount)** · agreement **"
        out += String(format: "%.1f%%", metrics.agreementRate * 100)
        out += "** · mismatch rate **"
        out += String(format: "%.1f%%", metrics.mismatchRate * 100)
        out += "**\n\n"
        out += "| | Gold follow-up share | Classifier follow-up share | Δ (pp) |\n"
        out += "|---|---:|---:|---:|\n"
        out += String(format: "| followup | %.1f%% | %.1f%% | %+.1f |\n",
                      metrics.goldFollowupShare * 100,
                      metrics.predictedFollowupShare * 100,
                      metrics.followupShareDeltaPoints)
        out += "\n### Gold distribution\n\n"
        for (kind, count) in metrics.goldCounts.sorted(by: { $0.key < $1.key }) {
            out += "- `\(kind)`: \(count)\n"
        }
        out += "\n### Classifier distribution\n\n"
        for (kind, count) in metrics.predictedCounts.sorted(by: { $0.key < $1.key }) {
            out += "- `\(kind)`: \(count)\n"
        }
        out += "\n_Scoring code `route.turnKindMismatch` is report-only (not gating)._ \n"
        return out
    }
}
