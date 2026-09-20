//
//  NotificationService.swift
//  MeetMemento
//
//  Spec 019 R8 / ATTACH-08: exactly two local notifications — an opt-in daily
//  reminder and a weekly-ready one-shot. No engagement nags.
//

import Foundation
import Combine
import UserNotifications

protocol NotificationScheduling: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func currentAuthorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}

extension UNUserNotificationCenter: NotificationScheduling {
    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// Spec 019 R8: greppable. Do not add a third identifier.
    static let dailyIdentifier = "memento.dailyReminder"
    static let weeklyIdentifier = "memento.weeklyReflectionReady"
    static let allIdentifiers = [dailyIdentifier, weeklyIdentifier]

    static let kindKey = "kind"
    static let dailyKind = "daily"
    static let weeklyKind = "weekly"

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var isDenied: Bool { authorizationStatus == .denied }

    private var client: NotificationScheduling
    private weak var navigation: AppNavigationState?
    private var queuedDeepLink: NotificationDeepLink?

    private override init() {
        self.client = UNUserNotificationCenter.current()
        super.init()
    }

    /// Tests replace the system center with a recording mock.
    func useClientForTesting(_ client: NotificationScheduling) {
        self.client = client
    }

    func resetClientForTesting() {
        self.client = UNUserNotificationCenter.current()
        authorizationStatus = .notDetermined
        queuedDeepLink = nil
        navigation = nil
    }

    func installAsDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func attach(navigation: AppNavigationState) {
        self.navigation = navigation
        if let queuedDeepLink {
            navigation.pendingNotification = queuedDeepLink
            self.queuedDeepLink = nil
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await client.currentAuthorizationStatus()
        if authorizationStatus == .denied {
            let prefs = PreferencesService.shared
            if prefs.dailyReminderEnabled { prefs.dailyReminderEnabled = false }
            if prefs.weeklyReadyEnabled { prefs.weeklyReadyEnabled = false }
            cancelAll()
        } else {
            await syncDailyReminder()
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await client.requestAuthorization(options: [.alert, .sound, .badge])
            authorizationStatus = granted ? .authorized : .denied
            return granted
        } catch {
            authorizationStatus = .denied
            return false
        }
    }

    func applyDailyEnabled(_ wanted: Bool) async {
        if wanted {
            let granted = await requestAuthorization()
            PreferencesService.shared.dailyReminderEnabled = granted
        } else {
            PreferencesService.shared.dailyReminderEnabled = false
        }
        await syncDailyReminder()
    }

    func applyWeeklyEnabled(_ wanted: Bool) async {
        if wanted {
            let granted = await requestAuthorization()
            PreferencesService.shared.weeklyReadyEnabled = granted
        } else {
            PreferencesService.shared.weeklyReadyEnabled = false
            cancelWeeklyReady()
        }
    }

    func syncDailyReminder() async {
        let prefs = PreferencesService.shared
        guard prefs.dailyReminderEnabled, authorizationStatus != .denied else {
            client.removePendingNotificationRequests(withIdentifiers: [Self.dailyIdentifier])
            return
        }
        if authorizationStatus == .notDetermined {
            let granted = await requestAuthorization()
            guard granted else {
                client.removePendingNotificationRequests(withIdentifiers: [Self.dailyIdentifier])
                return
            }
        }
        var components = DateComponents()
        components.hour = prefs.dailyReminderHour
        components.minute = prefs.dailyReminderMinute
        let content = UNMutableNotificationContent()
        content.title = "Time to write"
        content.body = "A quiet minute for your journal."
        content.sound = .default
        content.userInfo = [Self.kindKey: Self.dailyKind]
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.dailyIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            try await client.add(request)
        } catch {
            AppLogger.log("[Notifications] daily schedule failed: \(error.localizedDescription)")
        }
    }

    func notifyWeeklyReadyIfEnabled() async {
        let prefs = PreferencesService.shared
        guard prefs.weeklyReadyEnabled, authorizationStatus != .denied else { return }
        let content = UNMutableNotificationContent()
        content.title = "Your weekly reflection is ready"
        content.body = "A note from this past week is waiting."
        content.sound = .default
        content.userInfo = [Self.kindKey: Self.weeklyKind]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.weeklyIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            try await client.add(request)
        } catch {
            AppLogger.log("[Notifications] weekly-ready schedule failed: \(error.localizedDescription)")
        }
    }

    func cancelWeeklyReady() {
        client.removePendingNotificationRequests(withIdentifiers: [Self.weeklyIdentifier])
    }

    func cancelAll() {
        client.removePendingNotificationRequests(withIdentifiers: Self.allIdentifiers)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let kind = response.notification.request.content.userInfo[Self.kindKey] as? String
        Task { @MainActor in
            self.handleTap(kind: kind)
            completionHandler()
        }
    }

    private func handleTap(kind: String?) {
        let link: NotificationDeepLink?
        switch kind {
        case Self.dailyKind: link = .daily
        case Self.weeklyKind: link = .weekly
        default: link = nil
        }
        guard let link else { return }
        if let navigation {
            navigation.pendingNotification = link
        } else {
            queuedDeepLink = link
        }
    }
}
