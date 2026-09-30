import XCTest
@testable import withMemento

/// Loads MEM-326 probe corpora and checks routing expectations (no model).
final class ProbeCorpusTests: XCTestCase {

    func test_q9BenignCorpus_meetsMinimumCount() throws {
        let probes = try ChatEvalCorpus.q9BenignHardTopicProbes()
        XCTAssertGreaterThanOrEqual(probes.count, 60)
    }

    func test_q9BenignCorpus_doesNotCrisisRoute() throws {
        let probes = try ChatEvalCorpus.q9BenignHardTopicProbes()
        let falsePositives = probes.filter { probe in
            switch SafetyRouter.decide(probe.prompt).action {
            case .showCrisisCard, .hardRefuse:
                return true
            case .continue, .continueConstrained:
                return false
            }
        }
        XCTAssertEqual(falsePositives.count, 0,
                       "benign hard-topic prompts must not crisis-route: \(falsePositives.prefix(3).map(\.id))")
    }

    func test_regulatedCorpus_routesConstrained() throws {
        let probes = try ChatEvalCorpus.regulatedProbes()
            .filter { $0.category != "everyday-should" }
        XCTAssertGreaterThanOrEqual(probes.count, 8)
        for probe in probes {
            let action = SafetyRouter.decide(probe.prompt).action
            XCTAssertEqual(action, .continueConstrained, "\(probe.id) expected constrained, got \(action)")
        }
    }

    func test_multilingualCrisisCorpus_coversLocales() throws {
        let probes = try ChatEvalCorpus.multilingualCrisisProbes()
        let locales = Set(probes.compactMap(\.locale))
        let required = ["es", "fr", "de", "pt-BR", "it", "ja", "zh-Hans", "ko"]
        for loc in required {
            XCTAssertTrue(locales.contains(loc), "missing locale \(loc)")
        }
        for probe in probes {
            guard let expect = probe.expect,
                  let want = ChatEvalScoring.expectedSafetyAction(for: expect) else {
                XCTFail("probe \(probe.id) missing expect")
                continue
            }
            XCTAssertEqual(SafetyRouter.decide(probe.prompt).action, want, probe.id)
        }
    }

    func test_injectionCorpus_loadsEntryScenario() throws {
        let (entries, scenarios) = try ChatEvalCorpus.injectionCorpus()
        XCTAssertGreaterThan(entries.count, ChatEvalCorpus.attributionCorpus.count)
        XCTAssertEqual(scenarios.count, 1)
        XCTAssertTrue(scenarios[0].text.contains("PINEAPPLE"))
    }

    func test_userJailbreaks_hardRefuse() throws {
        let jailbreaks = try ChatEvalCorpus.injectionCorpusFile().userJailbreaks
        for probe in jailbreaks {
            XCTAssertEqual(SafetyRouter.decide(probe.prompt).action, .hardRefuse, probe.id)
        }
    }
}
