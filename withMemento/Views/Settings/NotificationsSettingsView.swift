//
//  NotificationsSettingsView.swift
//  withMemento
//
//  ATTACH-08: daily reminder + weekly-ready. Off by default. 019 R8.
//

import SwiftUI

struct NotificationsSettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var preferences = PreferencesService.shared
    @ObservedObject private var notifications = NotificationService.shared
    @State private var reminderTime = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if notifications.isDenied {
                    deniedSection
                }

                dailySection
                #if MEMENTO_AI
                weeklySection
                #endif

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reminderTime = dateFromPreferences()
            Task { await notifications.refreshAuthorizationStatus() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await notifications.refreshAuthorizationStatus() }
            }
        }
        .onChange(of: reminderTime) { _, date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            preferences.dailyReminderHour = components.hour ?? 20
            preferences.dailyReminderMinute = components.minute ?? 0
        }
    }

    private var deniedSection: some View {
        SettingsSection(title: "Permission") {
            SettingsInfoRow(
                icon: "bell.slash.fill",
                title: "Notifications are off for Memento",
                description: "iOS is blocking reminders. You can turn them back on in system Settings."
            )
            SettingsRowDivider()
            SettingsRow(
                icon: "gear",
                title: "Open iOS Settings",
                subtitle: "Notifications → Memento",
                showChevron: true,
                accessibilityIdentifier: "settings.notifications.openSystem",
                action: openSystemSettings
            )
        }
    }

    private var dailySection: some View {
        SettingsSection(title: "Daily reminder") {
            SettingsToggleRow(
                icon: "bell.fill",
                title: "Daily reminder",
                subtitle: "A nudge to write once a day.",
                isOn: dailyBinding,
                accessibilityIdentifier: "settings.notifications.daily",
                accessibilityHint: "Schedules a once-a-day reminder to journal"
            )

            if preferences.dailyReminderEnabled {
                SettingsRowDivider()
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "clock")
                        .font(.system(size: 20)) // icon-size: not user text
                        .foregroundStyle(theme.foreground)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
                    Text("Time")
                        .font(type.body1Bold)
                        .foregroundStyle(theme.foreground)
                    Spacer()
                    DatePicker(
                        "Time",
                        selection: $reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .accessibilityIdentifier("settings.notifications.dailyTime")
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
        }
    }

    #if MEMENTO_AI
    private var weeklySection: some View {
        SettingsSection(title: "Weekly reflection") {
            SettingsToggleRow(
                icon: "calendar",
                title: "Weekly reflection",
                subtitle: "When a new weekly note is ready.",
                isOn: weeklyBinding,
                accessibilityIdentifier: "settings.notifications.weekly",
                accessibilityHint: "Notifies you when a weekly reflection is saved"
            )
        }
    }
    #endif

    private var dailyBinding: Binding<Bool> {
        Binding(
            get: { preferences.dailyReminderEnabled },
            set: { wanted in
                Task { await notifications.applyDailyEnabled(wanted) }
            }
        )
    }

    #if MEMENTO_AI
    private var weeklyBinding: Binding<Bool> {
        Binding(
            get: { preferences.weeklyReadyEnabled },
            set: { wanted in
                Task { await notifications.applyWeeklyEnabled(wanted) }
            }
        )
    }
    #endif

    private func dateFromPreferences() -> Date {
        var components = DateComponents()
        components.hour = preferences.dailyReminderHour
        components.minute = preferences.dailyReminderMinute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
