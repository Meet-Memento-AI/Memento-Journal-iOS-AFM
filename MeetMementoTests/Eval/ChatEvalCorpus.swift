import Foundation
@testable import MeetMemento

/// Fixture access for the chat evaluation gate (spec 022 R1/R2).
///
/// The repo's `Fixtures/` directory — 262 entries across nine monthly files and
/// a 45-question gold set — is deliberately not a member of any target, so it
/// has to be read from the host filesystem. Two resolution paths, in order:
///
///   1. `TEST_RUNNER_CHAT_EVAL_FIXTURES` (the mechanism `ios-device-eval.yml`
///      already uses for `TEST_RUNNER_SPIKE_A_FIXTURES`);
///   2. `#filePath`-relative, the way `PersonaGateTests.goldFixtureURL()`
///      resolves `adversarial.json` — works for any local checkout.
enum ChatEvalCorpus {

    // MARK: - Fixture schemas

    /// Mirrors `Fixtures/corpus/entries-YYYY-MM.json`.
    struct FixtureEntry: Decodable {
        let id: String
        let createdAt: String
        let source: String
        let transcript: String
        let seedMoods: [String]?
        let seedTopics: [String]?
    }

    struct GoldQuestion: Decodable {
        let id: String
        let category: String
        let query: String
        let expectedEntryIDs: [String]
        /// "all" | "any" | "none"
        let match: String
    }

    private struct GoldFile: Decodable {
        let questions: [GoldQuestion]
    }

    // MARK: - Location

    enum FixtureError: Error, CustomStringConvertible {
        case notFound

        var description: String {
            "Fixtures/ not found. Set TEST_RUNNER_CHAT_EVAL_FIXTURES to the repo's "
            + "Fixtures directory, or run from a checkout where it sits beside MeetMementoTests/."
        }
    }

    static func fixturesURL() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        if let path = env["CHAT_EVAL_FIXTURES"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        // MeetMementoTests/Eval/ChatEvalCorpus.swift → repo root
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Eval
            .deletingLastPathComponent()   // MeetMementoTests
            .deletingLastPathComponent()   // repo
        let fixtures = repo.appendingPathComponent("Fixtures")
        guard FileManager.default.fileExists(atPath: fixtures.path) else {
            throw FixtureError.notFound
        }
        return fixtures
    }

    // MARK: - Loading

    /// The full 262-entry persona corpus, oldest first, mapped onto `Entry`.
    ///
    /// Fixture ids are strings (`e-2026-01-12-1`), not UUIDs, so the mapping
    /// mints a deterministic UUID per fixture id — the same id always yields
    /// the same UUID within a run, which is what lets a citation be traced back
    /// to an `expectedEntryIDs` value.
    static func personaCorpus() throws -> (entries: [Entry], idByUUID: [UUID: String]) {
        let dir = try fixturesURL().appendingPathComponent("corpus")
        let files = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let iso = ISO8601DateFormatter()
        var entries: [Entry] = []
        var map: [UUID: String] = [:]

        for file in files {
            let decoded = try JSONDecoder().decode([FixtureEntry].self, from: Data(contentsOf: file))
            for fixture in decoded {
                let uuid = deterministicUUID(for: fixture.id)
                let date = iso.date(from: fixture.createdAt) ?? Date()
                // The corpus has no separate title; the shipping editor derives
                // one the same way — first line, capped.
                let firstLine = fixture.transcript
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .first.map(String.init) ?? fixture.id
                entries.append(Entry(
                    id: uuid,
                    title: String(firstLine.prefix(80)),
                    text: fixture.transcript,
                    createdAt: date
                ))
                map[uuid] = fixture.id
            }
        }
        return (entries.sorted { $0.createdAt < $1.createdAt }, map)
    }

    /// The 45-question gold set, **resolved**.
    ///
    /// `questions.resolved.json`, not `questions.json`. Four of the 45 (q-38..q-41)
    /// are *derived* questions — "how do I usually feel on overcast Mondays",
    /// "which were my hardest weeks" — whose `expectedEntryIDs` are empty in the
    /// authored file and materialised by `Fixtures/validate_corpus.py` from the
    /// corpus (14, 10, 14 and 16 entries respectively). Scoring citations against
    /// the authored file therefore judged those four against an empty expected
    /// set, where no answer can ever be correct.
    ///
    /// The resolved file is a build artefact regenerated on every validator run,
    /// and CI already fails on it being stale (`spec-gates.yml`, `fixture-corpus`),
    /// so reading it here cannot drift from the corpus.
    static func goldQuestions() throws -> [GoldQuestion] {
        let url = try fixturesURL().appendingPathComponent("gold/questions.resolved.json")
        return try JSONDecoder().decode(GoldFile.self, from: Data(contentsOf: url)).questions
    }

    /// FNV-1a over the fixture id, widened to 16 bytes. Stable across runs and
    /// processes, so a citation's `entryId` maps back to a fixture id.
    static func deterministicUUID(for fixtureID: String) -> UUID {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in fixtureID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        var second: UInt64 = 0x9e3779b97f4a7c15 ^ hash
        second = second &* 0xff51afd7ed558ccd
        var bytes = [UInt8]()
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((hash >> UInt64(shift)) & 0xff)) }
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((second >> UInt64(shift)) & 0xff)) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: - Conversational corpus

    /// A small, hand-written corpus where third parties act in the entries, so
    /// a reply that swaps the subject is mechanically detectable. Kept
    /// alongside the persona corpus because the fixture entries are all
    /// first-person and cannot catch an attribution error.
    ///
    /// Dates are relative so "lately" and "this week" mean what they say.
    static let attributionCorpus: [Entry] = [
        Entry(title: "Hiking Mount Tamalpais",
              text: "Drove out to Mount Tamalpais on Saturday with Maya. We started at 6am and the fog was so thick we could barely see the trailhead. Four hours up, and at the top it broke open completely. Maya said it was the first time she had felt calm in weeks. I have not felt that light in a long time. My knees hurt on the way down.",
              createdAt: daysAgo(21)),
        Entry(title: "The Q3 deadline is crushing me",
              text: "Third late night this week on the Q3 launch. Daniel pushed the deadline up two weeks without telling anyone and now the whole team is scrambling. I snapped at Priya in standup today over a staging bug that was not her fault. I need to apologise tomorrow. I keep telling myself this is temporary but I said the same thing in April.",
              createdAt: daysAgo(14)),
        Entry(title: "Coffee with Maya",
              text: "Maya came by the apartment with pastries. We talked for three hours about her leaving the nonprofit. She is scared she will regret it. I told her about how I felt before I left the agency. It is strange being the person with advice now. I want to be a better friend to her than I was last year.",
              createdAt: daysAgo(9)),
        Entry(title: "Sleep is falling apart",
              text: "Woke up at 3:40am again. That is five nights running. I checked my phone which I know makes it worse. Tried the breathing thing for ten minutes and it did nothing. I think it is the work stress but part of me thinks it started before the deadline moved. Going to try no screens after nine.",
              createdAt: daysAgo(4)),
        Entry(title: "Small good day",
              text: "Nothing dramatic today. Made eggs properly for once. Finished the Le Guin book on the balcony. Called my mother and we did not argue about the house, which is new. Priya accepted my apology and even made a joke about it. I want to remember that ordinary days like this count too.",
              createdAt: daysAgo(1))
    ]

    static func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
    }
}
