//
//  ScrollOffsetPreferenceKey.swift
//  MeetMemento
//
//  Shared preference key for scroll offset tracking across views
//

import SwiftUI

/// Shared preference key for scroll offset tracking across views
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
