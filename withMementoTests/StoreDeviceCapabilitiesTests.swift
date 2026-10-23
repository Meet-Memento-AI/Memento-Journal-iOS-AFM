//
//  StoreDeviceCapabilitiesTests.swift
//  withMementoTests
//
//  Guideline 2.3: UIRequiredDeviceCapabilities must not block iPad installs
//  when the app only optionally uses location, mic, or Apple Intelligence.
//

import XCTest

final class StoreDeviceCapabilitiesTests: XCTestCase {
    private static let forbiddenCapabilities: Set<String> = [
        "gps",
        "telephony",
        "sms",
        "healthkit",
        "location-services",
        "nfc",
        "iphone-performance-gaming-tier",
        "ipad-minimum-performance-m1",
        "armv7",
    ]

    func test_infoPlist_doesNotRequireHardwareThatBlocksWiFiIPad() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = repo.appendingPathComponent("withMemento/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL) else {
            XCTFail("withMemento/Info.plist must exist at \(plistURL.path)")
            return
        }

        let required = plist["UIRequiredDeviceCapabilities"] as? [String] ?? []
        let blocked = required.filter { Self.forbiddenCapabilities.contains($0) }
        XCTAssertTrue(
            blocked.isEmpty,
            "UIRequiredDeviceCapabilities must not list \(blocked); optional location and universal iPad support require an empty array."
        )
    }

    func test_project_doesNotSetRequiredCapabilitiesInBuildSettings() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pbxproj = try String(
            contentsOf: repo.appendingPathComponent("withMemento.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertFalse(
            pbxproj.contains("INFOPLIST_KEY_UIRequiredDeviceCapabilities"),
            "Define UIRequiredDeviceCapabilities only in Info.plist so CI can audit it."
        )
        XCTAssertTrue(
            pbxproj.contains("TARGETED_DEVICE_FAMILY = \"1,2\""),
            "App must remain a universal iPhone + iPad binary."
        )
    }
}
