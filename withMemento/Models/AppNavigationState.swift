//
//  AppNavigationState.swift
//  withMemento
//
//  Spec 040 R5: bindable section + settings path for a later iPad shell.
//  Compact UI still uses RootPager; this does not replace it.
//

import Foundation
import SwiftUI

enum NotificationDeepLink: Equatable {
    case daily
    case weekly
}

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var primarySection: RootPage = .journal
    @Published var settingsPath = NavigationPath()
    /// Set by `NotificationService` when a reminder is tapped. ContentView
    /// consumes it after unlock so the PIN is never skipped.
    @Published var pendingNotification: NotificationDeepLink?
}
