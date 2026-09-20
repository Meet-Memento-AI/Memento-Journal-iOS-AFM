import XCTest
import AVFoundation
@testable import MeetMemento

/// Pure-function coverage of `VoicePlaybackService.bestVoiceIdentifier` —
/// the ranking that fixes the "generic compact voice" regression: quality
/// beats region, exact locale wins ties, novelty/Personal Voice excluded
/// (spec 018 R7/R8).
@MainActor
final class VoiceSelectionTests: XCTestCase {

    private typealias Candidate = VoicePlaybackService.VoiceCandidate

    private func candidate(
        _ identifier: String, _ language: String,
        _ quality: AVSpeechSynthesisVoiceQuality,
        novelty: Bool = false, personal: Bool = false
    ) -> Candidate {
        Candidate(identifier: identifier, language: language, quality: quality,
                  isNovelty: novelty, isPersonal: personal)
    }

    private func best(_ candidates: [Candidate], language: String = "en-US") -> String? {
        VoicePlaybackService.bestVoiceIdentifier(from: candidates, currentLanguage: language)
    }

    func test_prefixEnhancedBeatsExactCompact() {
        // The regression: en-US user, only en-GB Enhanced downloaded.
        let result = best([
            candidate("compact-us", "en-US", .default),
            candidate("enhanced-gb", "en-GB", .enhanced),
        ])
        XCTAssertEqual(result, "enhanced-gb")
    }

    func test_exactBeatsPrefixAtEqualQuality() {
        let result = best([
            candidate("enhanced-gb", "en-GB", .enhanced),
            candidate("enhanced-us", "en-US", .enhanced),
        ])
        XCTAssertEqual(result, "enhanced-us")
    }

    func test_premiumBeatsEnhanced() {
        let result = best([
            candidate("enhanced-us", "en-US", .enhanced),
            candidate("premium-us", "en-US", .premium),
        ])
        XCTAssertEqual(result, "premium-us")
    }

    func test_exactPremiumBeatsPrefixPremium() {
        let result = best([
            candidate("premium-gb", "en-GB", .premium),
            candidate("premium-us", "en-US", .premium),
        ])
        XCTAssertEqual(result, "premium-us")
    }

    func test_noveltyAndPersonalExcludedEvenAtPremium() {
        let result = best([
            candidate("novelty", "en-US", .premium, novelty: true),
            candidate("personal", "en-US", .premium, personal: true),
            candidate("compact-us", "en-US", .default),
        ])
        XCTAssertEqual(result, "compact-us")
    }

    func test_compactOnlyFallsBackToExactCompact() {
        let result = best([
            candidate("compact-gb", "en-GB", .default),
            candidate("compact-us", "en-US", .default),
        ])
        XCTAssertEqual(result, "compact-us")
    }

    func test_unrelatedLanguageNeverPicked() {
        let result = best([
            candidate("premium-fr", "fr-FR", .premium),
        ])
        XCTAssertNil(result)
    }

    func test_emptyListReturnsNil() {
        XCTAssertNil(best([]))
    }
}
