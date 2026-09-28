import XCTest
@testable import withMemento

final class RegressionSmokeTests: XCTestCase {
    func test_testTarget_linkswithMemento() {
        let _: ChatServiceProtocol = ChatService.shared
    }
}
