//
//  AccessibilityHelpers.swift
//  MeetMemento
//
//  Accessibility utilities for WCAG 2.1 AA compliance and VoiceOver support.
//

import SwiftUI

// MARK: - Accessibility Container Modifier

/// Groups child views into a single accessible element for VoiceOver.
/// Use this for complex components like cards, list items, and interactive groups.
public struct AccessibilityContainerModifier: ViewModifier {
    let label: String
    let hint: String?
    let traits: AccessibilityTraits

    public init(
        label: String,
        hint: String? = nil,
        traits: AccessibilityTraits = []
    ) {
        self.label = label
        self.hint = hint
        self.traits = traits
    }

    public func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(traits)
    }
}

public extension View {
    /// Combines child elements into a single VoiceOver-accessible container.
    /// - Parameters:
    ///   - label: The label to announce (e.g., "Journal entry from March 15")
    ///   - hint: Optional hint describing available actions
    ///   - traits: Accessibility traits (e.g., .isButton, .isHeader)
    func accessibilityContainer(
        label: String,
        hint: String? = nil,
        traits: AccessibilityTraits = []
    ) -> some View {
        modifier(AccessibilityContainerModifier(label: label, hint: hint, traits: traits))
    }
}

// MARK: - Custom Actions Modifier

/// Adds custom accessibility actions for VoiceOver users.
/// Use this to provide gesture shortcuts for complex interactions.
public struct AccessibilityActionsModifier: ViewModifier {
    let actions: [(name: String, action: () -> Void)]

    public func body(content: Content) -> some View {
        var modifiedContent = AnyView(content)
        for actionItem in actions {
            modifiedContent = AnyView(
                modifiedContent
                    .accessibilityAction(named: actionItem.name, actionItem.action)
            )
        }
        return modifiedContent
    }
}

public extension View {
    /// Adds custom VoiceOver actions for the element.
    /// - Parameter actions: Array of (name, action) tuples
    func accessibilityActions(_ actions: [(name: String, action: () -> Void)]) -> some View {
        modifier(AccessibilityActionsModifier(actions: actions))
    }
}

// MARK: - Card Accessibility

/// Provides standard accessibility configuration for card components.
public extension View {
    /// Configures a card for VoiceOver with standard interactions.
    /// - Parameters:
    ///   - title: Card title
    ///   - subtitle: Optional subtitle or date
    ///   - summary: Brief content summary
    ///   - onTap: Action when card is activated
    ///   - additionalActions: Extra actions (edit, delete, share)
    func accessibilityCard(
        title: String,
        subtitle: String? = nil,
        summary: String? = nil,
        onTap: (() -> Void)? = nil,
        additionalActions: [(name: String, action: () -> Void)] = []
    ) -> some View {
        let labelParts = [title, subtitle, summary].compactMap { $0 }.joined(separator: ", ")

        var allActions = additionalActions
        if let tapAction = onTap {
            allActions.insert((name: "Open", action: tapAction), at: 0)
        }

        return self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(labelParts)
            .accessibilityHint(onTap != nil ? "Double-tap to open" : "")
            .accessibilityAddTraits(onTap != nil ? [.isButton] : [])
            .modifier(AccessibilityActionsModifier(actions: allActions))
    }
}

// MARK: - Heading Level Support

/// Marks content as a heading for VoiceOver navigation.
public extension View {
    /// Marks this view as a heading for VoiceOver rotor navigation.
    func accessibilityHeading() -> some View {
        self.accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Focusable Elements

/// Environment key for tracking focus within accessibility context.
private struct AccessibilityFocusedKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

public extension EnvironmentValues {
    var accessibilityFocusedElement: String? {
        get { self[AccessibilityFocusedKey.self] }
        set { self[AccessibilityFocusedKey.self] = newValue }
    }
}

// MARK: - Minimum Touch Target

/// Ensures interactive elements meet the 44x44pt minimum touch target.
public struct MinimumTouchTargetModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

public extension View {
    /// Ensures the view meets Apple's 44x44pt minimum touch target requirement.
    func minimumTouchTarget() -> some View {
        modifier(MinimumTouchTargetModifier())
    }
}

// MARK: - Announcements

/// Utility for posting VoiceOver announcements.
public enum AccessibilityAnnouncement {
    /// Announces a message to VoiceOver users.
    /// - Parameter message: The message to announce
    public static func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// Announces a screen change to VoiceOver.
    /// - Parameter message: Optional message describing the new screen
    public static func screenChanged(_ message: String? = nil) {
        UIAccessibility.post(notification: .screenChanged, argument: message)
    }

    /// Announces a layout change to VoiceOver.
    /// - Parameter element: Optional element to focus after the change
    public static func layoutChanged(_ element: Any? = nil) {
        UIAccessibility.post(notification: .layoutChanged, argument: element)
    }
}
