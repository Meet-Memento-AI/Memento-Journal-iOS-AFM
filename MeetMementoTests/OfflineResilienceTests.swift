import XCTest
@testable import MeetMemento

// MARK: - NetworkMonitoring mock

@MainActor
final class MockNetworkMonitor: NetworkMonitoring {
    var isConnected: Bool

    init(isConnected: Bool = true) {
        self.isConnected = isConnected
    }
}

@MainActor
final class NetworkMonitoringProtocolTests: XCTestCase {
    func test_mockNetworkMonitor_reflectsAssignedState() {
        let mock = MockNetworkMonitor(isConnected: true)
        let seam: NetworkMonitoring = mock
        XCTAssertTrue(seam.isConnected)

        mock.isConnected = false
        XCTAssertFalse(seam.isConnected)
    }
}
