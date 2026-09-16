import UserNotifications
import XCTest
@testable import MeetMemento

@MainActor
final class MockNotificationScheduling: NotificationScheduling {
    var status: UNAuthorizationStatus = .notDetermined
    var grantNextRequest = true
    private(set) var added: [UNNotificationRequest] = []
    private(set) var removedIdentifiers: [String] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        status = grantNextRequest ? .authorized : .denied
        return grantNextRequest
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func add(_ request: UNNotificationRequest) async throws {
        added.removeAll { $0.identifier == request.identifier }
        added.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
        added.removeAll { identifiers.contains($0.identifier) }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        added
    }
}

@MainActor
final class NotificationServiceTests: XCTestCase {
    private var mock: MockNotificationScheduling!

    override func setUp() async throws {
        mock = MockNotificationScheduling()
        NotificationService.shared.useClientForTesting(mock)
        PreferencesService.shared.dailyReminderEnabled = false
        PreferencesService.shared.weeklyReadyEnabled = false
        PreferencesService.shared.dailyReminderHour = 20
        PreferencesService.shared.dailyReminderMinute = 0
        mock.added.removeAll()
        mock.removedIdentifiers.removeAll()
    }

    override func tearDown() async throws {
        PreferencesService.shared.dailyReminderEnabled = false
        PreferencesService.shared.weeklyReadyEnabled = false
        NotificationService.shared.resetClientForTesting()
        WeeklyReflectionStore.clear()
        mock = nil
    }

    func test_exactlyTwoIdentifiers() {
        XCTAssertEqual(NotificationService.allIdentifiers.count, 2)
        XCTAssertEqual(
            Set(NotificationService.allIdentifiers),
            [NotificationService.dailyIdentifier, NotificationService.weeklyIdentifier]
        )
    }

    func test_dailyOff_doesNotLeavePendingRequest() async {
        mock.status = .authorized
        PreferencesService.shared.dailyReminderEnabled = false
        await NotificationService.shared.syncDailyReminder()
        XCTAssertFalse(mock.added.contains { $0.identifier == NotificationService.dailyIdentifier })
        XCTAssertTrue(mock.removedIdentifiers.contains(NotificationService.dailyIdentifier))
    }

    func test_dailyOn_schedulesCalendarTriggerAtStoredHour() async {
        mock.status = .authorized
        mock.grantNextRequest = true
        PreferencesService.shared.dailyReminderHour = 20
        PreferencesService.shared.dailyReminderMinute = 15
        PreferencesService.shared.dailyReminderEnabled = true
        await NotificationService.shared.requestAuthorization()
        await NotificationService.shared.syncDailyReminder()
        let request = mock.added.first { $0.identifier == NotificationService.dailyIdentifier }
        XCTAssertNotNil(request)
        let trigger = request?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.hour, 20)
        XCTAssertEqual(trigger?.dateComponents.minute, 15)
        XCTAssertEqual(trigger?.repeats, true)
        XCTAssertEqual(request?.content.userInfo[NotificationService.kindKey] as? String, NotificationService.dailyKind)
    }

    func test_resetToDefaults_cancelsReminders() async {
        mock.status = .authorized
        _ = await NotificationService.shared.requestAuthorization()
        PreferencesService.shared.dailyReminderEnabled = true
        await NotificationService.shared.syncDailyReminder()
        XCTAssertTrue(mock.added.contains { $0.identifier == NotificationService.dailyIdentifier })
        PreferencesService.shared.resetToDefaults()
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(mock.removedIdentifiers.contains(NotificationService.dailyIdentifier))
        XCTAssertTrue(mock.removedIdentifiers.contains(NotificationService.weeklyIdentifier))
        XCTAssertFalse(PreferencesService.shared.dailyReminderEnabled)
        XCTAssertFalse(PreferencesService.shared.weeklyReadyEnabled)
        XCTAssertEqual(PreferencesService.shared.dailyReminderHour, 20)
    }

    func test_weeklyReady_gatedByPreference() async {
        mock.status = .authorized
        _ = await NotificationService.shared.requestAuthorization()
        PreferencesService.shared.weeklyReadyEnabled = false
        await NotificationService.shared.notifyWeeklyReadyIfEnabled()
        XCTAssertFalse(mock.added.contains { $0.identifier == NotificationService.weeklyIdentifier })

        PreferencesService.shared.weeklyReadyEnabled = true
        await NotificationService.shared.notifyWeeklyReadyIfEnabled()
        let request = mock.added.first { $0.identifier == NotificationService.weeklyIdentifier }
        XCTAssertNotNil(request)
        XCTAssertEqual(
            request?.content.userInfo[NotificationService.kindKey] as? String,
            NotificationService.weeklyKind
        )
        XCTAssertFalse(request?.trigger is UNCalendarNotificationTrigger)
    }

    func test_persist_speakableBody_schedulesWeeklyWhenEnabled() async {
        mock.status = .authorized
        _ = await NotificationService.shared.requestAuthorization()
        PreferencesService.shared.weeklyReadyEnabled = false
        let result = PeriodReflectionResult(
            body: "This week felt quieter than the last one.",
            observation: "A slower pace.",
            groundedEntryIDs: [],
            hasNothingToSay: false
        )
        WeeklyReflectionCoordinator.persist(
            result, weekStart: Date(), zone: .z0Device, entries: []
        )
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(mock.added.contains { $0.identifier == NotificationService.weeklyIdentifier })

        PreferencesService.shared.weeklyReadyEnabled = true
        WeeklyReflectionCoordinator.persist(
            result, weekStart: Date(), zone: .z0Device, entries: []
        )
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(mock.added.contains { $0.identifier == NotificationService.weeklyIdentifier })
    }

    func test_persistQuiet_doesNotScheduleWeekly() async {
        mock.status = .authorized
        _ = await NotificationService.shared.requestAuthorization()
        PreferencesService.shared.weeklyReadyEnabled = true
        WeeklyReflectionCoordinator.persistQuiet(weekStart: Date())
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(mock.added.contains { $0.identifier == NotificationService.weeklyIdentifier })
    }
}
