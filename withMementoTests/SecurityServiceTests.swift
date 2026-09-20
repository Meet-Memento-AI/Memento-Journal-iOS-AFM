import XCTest
@testable import MeetMemento

final class SecurityServiceTests: XCTestCase {
    private func makeService(now: @escaping () -> Date = Date.init) -> SecurityService {
        SecurityService(keychain: InMemoryKeychainStore(), now: now)
    }

    func test_savePIN_thenGetPIN_returnsSameValue() {
        let service = makeService()
        XCTAssertTrue(service.savePIN("1234"))
        XCTAssertEqual(service.getPIN(), "1234")
    }

    func test_savePIN_overwritesPreviousPIN() {
        let service = makeService()
        service.savePIN("1234")
        service.savePIN("5678")
        XCTAssertEqual(service.getPIN(), "5678")
    }

    func test_validatePIN_trueForCorrect_falseForWrong() {
        let service = makeService()
        service.savePIN("1234")

        XCTAssertTrue(service.validatePIN("1234"))
        XCTAssertFalse(service.validatePIN("0000"))
        XCTAssertFalse(service.validatePIN("12345")) // different length
    }

    func test_validatePIN_falseWhenNoPINStored() {
        let service = makeService()
        XCTAssertFalse(service.validatePIN("1234"))
    }

    func test_deletePIN_removesStoredPIN() {
        let service = makeService()
        service.savePIN("1234")
        service.deletePIN()
        XCTAssertNil(service.getPIN())
        XCTAssertFalse(service.validatePIN("1234"))
    }

    // MARK: - Auto-logout (injected clock)

    func test_shouldAutoLogout_falseWhenNoActivityRecorded() {
        let service = makeService()
        service.clearActivityTimestamp()
        XCTAssertFalse(service.shouldAutoLogout())
    }

    func test_shouldAutoLogout_falseJustUnderFourteenDays() {
        var current = Date(timeIntervalSince1970: 1_700_000_000)
        let service = makeService(now: { current })

        service.updateActivityTimestamp() // stamps "current"
        current = current.addingTimeInterval(13.9 * 24 * 60 * 60)

        XCTAssertFalse(service.shouldAutoLogout())
    }

    func test_shouldAutoLogout_trueAtOrOverFourteenDays() {
        var current = Date(timeIntervalSince1970: 1_700_000_000)
        let service = makeService(now: { current })

        service.updateActivityTimestamp()
        current = current.addingTimeInterval(14.1 * 24 * 60 * 60)

        XCTAssertTrue(service.shouldAutoLogout())
    }

    func test_clearActivityTimestamp_resetsLastActivity() {
        let service = makeService()
        service.updateActivityTimestamp()
        XCTAssertNotNil(service.lastActivityTimestamp)

        service.clearActivityTimestamp()
        XCTAssertNil(service.lastActivityTimestamp)
    }

    // MARK: - Security mode

    func test_securityMode_defaultsToNone() {
        let service = makeService()
        // Reset in case a previous run (against the shared UserDefaults key)
        // left a mode set — securityMode isn't behind the keychain mock.
        service.setSecurityMode(.none)
        XCTAssertEqual(service.currentMode, .none)
    }

    func test_setSecurityMode_persistsAndReads() {
        let service = makeService()
        service.setSecurityMode(.pin)
        XCTAssertEqual(service.currentMode, .pin)

        service.setSecurityMode(.faceID)
        XCTAssertEqual(service.currentMode, .faceID)

        service.setSecurityMode(.none) // leave clean for other tests
    }
}
