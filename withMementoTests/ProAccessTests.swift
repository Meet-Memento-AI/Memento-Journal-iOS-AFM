import XCTest
@testable import withMemento

/// Spec 021 R2/R4: the central Memento Pro gate.
final class ProAccessTests: XCTestCase {
    func testProIsUnlockedOnEveryDevice() {
        XCTAssertEqual(ProAccess.decide(isPro: true, availability: .available(.z0Device)), .unlocked)
        XCTAssertEqual(ProAccess.decide(isPro: true, availability: .unavailable(.deviceNotEligible)), .unlocked)
        XCTAssertEqual(ProAccess.decide(isPro: true, availability: .unavailable(.modelNotReady)), .unlocked)
    }

    /// R2: never a paywall on a device without Apple Intelligence.
    func testIneligibleDeviceNeverShowsPaywall() {
        XCTAssertEqual(
            ProAccess.decide(isPro: false, availability: .unavailable(.deviceNotEligible)),
            .unavailableDevice
        )
    }

    func testCapableDeviceWithoutProShowsPaywall() {
        XCTAssertEqual(ProAccess.decide(isPro: false, availability: .available(.z0Device)), .showPaywall)
        XCTAssertEqual(ProAccess.decide(isPro: false, availability: .unavailable(.modelNotReady)), .showPaywall)
    }

    /// No SDK → nothing can be sold → nothing is held back (and no crash).
    func testUnconfiguredPurchasesFailsOpen() {
        XCTAssertEqual(
            ProAccess.decide(isPro: false, availability: .available(.z0Device), purchasesConfigured: false),
            .unlocked
        )
    }
}

final class RevenueCatConfigTests: XCTestCase {
    func testMissingOrUnexpandedKeyIsNotConfigured() {
        XCTAssertNil(RevenueCatConfig.resolve(nil))
        XCTAssertNil(RevenueCatConfig.resolve(""))
        XCTAssertNil(RevenueCatConfig.resolve("   "))
        XCTAssertNil(RevenueCatConfig.resolve("$(REVENUECAT_API_KEY)"))
    }

    func testKeyIsTrimmed() {
        XCTAssertEqual(RevenueCatConfig.resolve(" appl_abc \n"), "appl_abc")
    }

    /// Spec 021 R3 / REQ-PRIV-001: RevenueCat receives the anonymous ID and
    /// receipts only. No identity, attribute, or attribution call may exist
    /// anywhere in the app.
    func testNoRevenueCatIdentityOrAttributeCalls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("withMemento")
        let forbidden = [
            "logIn(", "logOut(", "attribution.", "appUserID:",
            "setAttributes(", "setEmail(", "setDisplayName(", "setPhoneNumber(",
        ]
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        var sdkFiles = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            // Only files that can reach the SDK; `FileManager.setAttributes`
            // elsewhere is unrelated.
            guard text.contains("import RevenueCat") else { continue }
            sdkFiles += 1
            let code = text.split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            for token in forbidden {
                XCTAssertFalse(code.contains(token), "\(file.lastPathComponent) calls \(token)")
            }
        }
        XCTAssertGreaterThan(sdkFiles, 0, "scan found no RevenueCat call sites — path wrong?")
    }
}
