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
    var onMenuTapped: () -> Void
    var onActionTapped: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(
        selection: Binding<JournalTopTab>,
        hasActiveChat: Bool = false,
        onMenuTapped: @escaping () -> Void,
        onActionTapped: @escaping () -> Void
    ) {
        self._selection = selection
        self.hasActiveChat = hasActiveChat
        self.onMenuTapped = onMenuTapped
        self.onActionTapped = onActionTapped
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Hamburger menu (placeholder for future features)
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onMenuTapped()
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.foreground)
                    .frame(width: 44, height: 44)
                    .background(iconButtonBackground)
            }
            .accessibilityLabel("Menu")

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
        if #available(iOS 26.0, *) {
            // iOS 26: Liquid glass with interactive feedback
            Circle()
                .fill(Color.clear)
                .mementoGlassEffect(.regular.interactive(), in: Circle())
        } else {
            // iOS 18+: Ultra thin material fallback
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Action Button Styling

    /// Icon for the right action button (context-aware)
    private var actionButtonIcon: String {
        if selection == .yourEntries {
            return "magnifyingglass"
        } else if hasActiveChat {
            return "doc.text"
        } else {
            return "square.and.pencil"
        }
    }

    /// Foreground color for the right action button
    private var actionButtonForeground: Color {
        if selection == .digDeeper && hasActiveChat {
            return theme.primaryForeground
        } else {
            return theme.foreground
        }
    }

    /// Background for the right action button
    @ViewBuilder
    private var actionButtonBackground: some View {
        if selection == .digDeeper && hasActiveChat {
            // Active chat state: purple filled circle
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
            return "Summarize Chat"
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
                onMenuTapped: { print("Menu tapped") },
                onActionTapped: { print("Search tapped") }
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
                onMenuTapped: { print("Menu tapped") },
                onActionTapped: { print("New Entry tapped") }
            )
            .padding(.top, 60)

            Spacer()
        }
    }
    .environment(\.theme, Theme.light)
    .environment(\.typography, Typography())
}
