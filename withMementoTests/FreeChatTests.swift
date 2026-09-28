import XCTest
@testable import withMemento

/// Spec 021 R4 `REQ-MON-006`: the free chat's scope, daily limit, and the
/// free/Pro split.
@MainActor
final class FreeChatTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "FreeChatTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func allowance(limit: Int? = nil, now: @escaping () -> Date = Date.init) -> FreeChatAllowance {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return FreeChatAllowance(defaults: defaults, calendar: calendar, now: now, limitProvider: { limit })
    }

    // MARK: - Allowance

    func testDefaultLimitIsTen() {
        XCTAssertEqual(allowance().dailyLimit, 10)
        XCTAssertEqual(allowance(limit: 0).dailyLimit, 10, "a non-positive override falls back")
    }

    func testOfferingMetadataOverridesTheLimit() {
        XCTAssertEqual(allowance(limit: 3).dailyLimit, 3)
    }

    func testCountsUntilExhausted() {
        let a = allowance(limit: 2)
        XCTAssertFalse(a.isExhausted)
        a.recordMessage()
        XCTAssertEqual(a.usedToday, 1)
        a.recordMessage()
        XCTAssertTrue(a.isExhausted)
    }

    func testResetsAtLocalMidnight() {
        var clock = ISO8601DateFormatter().date(from: "2026-09-26T23:30:00-05:00")!
        let a = allowance(limit: 1, now: { clock })
        a.recordMessage()
        XCTAssertTrue(a.isExhausted)
        clock = ISO8601DateFormatter().date(from: "2026-09-27T00:05:00-05:00")!
        XCTAssertFalse(a.isExhausted, "a new local day starts fresh")
        XCTAssertEqual(a.usedToday, 0)
    }

    // MARK: - Scope

    func testLatestEntryScopeKeepsOnlyTheNewestEntry() {
        let older = Entry(title: "old", createdAt: Date(timeIntervalSince1970: 1_000))
        let newest = Entry(title: "new", createdAt: Date(timeIntervalSince1970: 3_000))
        let middle = Entry(title: "mid", createdAt: Date(timeIntervalSince1970: 2_000))
        let all = [older, newest, middle]
        XCTAssertEqual(ChatRetrievalScope.latestEntry.apply(to: all).map(\.title), ["new"])
        XCTAssertEqual(ChatRetrievalScope.wholeJournal.apply(to: all).count, 3)
        XCTAssertTrue(ChatRetrievalScope.latestEntry.apply(to: []).isEmpty)
    }

    // MARK: - Tier

    func testTierFollowsTheProDecision() {
        XCTAssertEqual(ChatTier(.showPaywall), .free)
        XCTAssertEqual(ChatTier(.unlocked), .pro)
        // No Apple Intelligence: the chat shows its own unavailable state and
        // never any purchase UI (DEC-001).
        XCTAssertEqual(ChatTier(.unavailableDevice), .pro)
    }

    // MARK: - View model

    private func freeViewModel(limit: Int) -> (ChatViewModel, MockChatService) {
        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in
            ChatResponse(reply: "ok", heading1: nil, heading2: nil,
                         citedEntryIds: nil, sources: [], sessionId: UUID().uuidString)
        }
        let vm = ChatViewModel(chatService: mock, allowance: allowance(limit: limit))
        vm.setTier(.free)
        return (vm, mock)
    }

    private func settle(_ vm: ChatViewModel) async {
        let deadline = Date().addingTimeInterval(3)
        while vm.isLoading, Date() < deadline {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    func testFreeLimitHoldsTheNextMessageBack() async {
        let (vm, _) = freeViewModel(limit: 1)
        XCTAssertTrue(vm.sendMessage(prompt: "first"))
        await settle(vm)
        XCTAssertFalse(vm.sendMessage(prompt: "second"))
        XCTAssertTrue(vm.dailyLimitReached)
        XCTAssertFalse(vm.messages.contains { $0.content == "second" }, "a held message never enters the transcript")
    }

    /// 026 R4 amendment: crisis-adjacent text is never behind the limit.
    func testCrisisMessageAlwaysGoesThrough() async {
        let (vm, _) = freeViewModel(limit: 1)
        XCTAssertTrue(vm.sendMessage(prompt: "first"))
        await settle(vm)
        XCTAssertTrue(vm.sendMessage(prompt: "I want to kill myself."))
    }

    func testProIsNeverLimited() async {
        let (vm, _) = freeViewModel(limit: 1)
        vm.setTier(.pro)
        XCTAssertTrue(vm.sendMessage(prompt: "first"))
        await settle(vm)
        XCTAssertTrue(vm.sendMessage(prompt: "second"))
        XCTAssertFalse(vm.dailyLimitReached)
    }
}
