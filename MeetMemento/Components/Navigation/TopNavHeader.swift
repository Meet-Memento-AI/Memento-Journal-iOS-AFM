//
//  TopNavHeader.swift
//  MeetMemento
//
//  Custom floating header with hamburger menu, top nav pills, and context-aware action button.
//  Replaces the native toolbar for the top-level navigation when using TopTabNavContainer.
//

import SwiftUI

public struct TopNavHeader: View {
    @Binding var selection: JournalTopTab
    var hasActiveChat: Bool
    var userInitial: String?
    var onMenuTapped: () -> Void
    var onActionTapped: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(
        selection: Binding<JournalTopTab>,
        hasActiveChat: Bool = false,
        userInitial: String? = nil,
        onMenuTapped: @escaping () -> Void,
        onActionTapped: @escaping () -> Void
    ) {
        self._selection = selection
        self.hasActiveChat = hasActiveChat
        self.userInitial = userInitial
        self.onMenuTapped = onMenuTapped
        self.onActionTapped = onActionTapped
    }

    public var body: some View {
        // Liquid Glass removed — plain row (no GlassEffectContainer grouping).
        HStack(spacing: 12) {
            AvatarInitialButton(
                initial: userInitial,
                size: 44,
                enableHaptic: true,
                accessibilityLabel: "Menu",
                onTap: onMenuTapped
            )

            Spacer()

            // Center pills (synced with swipe gestures)
            TopNav(variant: .tabs, selection: $selection)

            Spacer()

            // Right action (context-aware: search for Journal, summarize/write for Insights)
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onActionTapped()
            }) {
                Image(systemName: actionButtonIcon)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(actionButtonForeground)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
                    .background(actionButtonBackground)
            }
            .accessibilityLabel(actionButtonAccessibilityLabel)
            .animation(.smooth(duration: 0.3), value: selection)
            .animation(.smooth(duration: 0.3), value: hasActiveChat)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Icon Button Background
    @ViewBuilder
    private var iconButtonBackground: some View {
        // Liquid Glass removed — flat #fafafa surface.
        Circle()
            .fill(theme.cardBackground)
    }

    // MARK: - Action Button Styling

    /// Icon for the right action button (context-aware)
    private var actionButtonIcon: String {
        if selection == .yourEntries {
            return "magnifyingglass"
        } else {
            // Both hasActiveChat and default use the same icon
            return "square.and.pencil"
        }
    }

    /// Foreground color for the right action button
    private var actionButtonForeground: Color {
        if selection == .digDeeper && hasActiveChat {
            return .white
        } else {
            return theme.foreground
        }
    }

    /// Background for the right action button
    @ViewBuilder
    private var actionButtonBackground: some View {
        if selection == .digDeeper && hasActiveChat {
            // Liquid Glass removed — brand color intentionally kept (prominent
            // active-chat action); flat purple fill, no glass.
            Circle()
                .fill(PrimaryScale.primary600)
        } else {
            iconButtonBackground
        }
    }

    /// Accessibility label for the right action button
    private var actionButtonAccessibilityLabel: String {
        if selection == .yourEntries {
            return "Search"
        } else if hasActiveChat {
            return "Save as Journal Entry"
        } else {
            return "New Entry"
        }
    }
}

// MARK: - Previews

#Preview("TopNavHeader - Journal Tab") {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()

        VStack {
            TopNavHeader(
                selection: .constant(.yourEntries),
                userInitial: "S",
                onMenuTapped: { AppLogger.log("Menu tapped") },
                onActionTapped: { AppLogger.log("Search tapped") }
            )
            .padding(.top, 60)

            Spacer()
        }
    }
    .environment(\.theme, Theme.light)
    .environment(\.typography, Typography())
}

#Preview("TopNavHeader - Insights Tab") {
    ZStack {
        Color.purple.opacity(0.3).ignoresSafeArea()

        VStack {
            TopNavHeader(
                selection: .constant(.digDeeper),
                userInitial: nil,
                onMenuTapped: { AppLogger.log("Menu tapped") },
                onActionTapped: { AppLogger.log("New Entry tapped") }
            )
            .padding(.top, 60)

            Spacer()
        }
    }
    .environment(\.theme, Theme.light)
    .environment(\.typography, Typography())
}
