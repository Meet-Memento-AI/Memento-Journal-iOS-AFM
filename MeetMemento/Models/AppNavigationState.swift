//
//  AppNavigationState.swift
//  MeetMemento
//
//  Spec 040 R5: bindable section + settings path for a later iPad shell.
//  Compact UI still uses RootPager; this does not replace it.
//

import Foundation
import SwiftUI

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var primarySection: RootPage = .journal
    @Published var settingsPath = NavigationPath()
}
