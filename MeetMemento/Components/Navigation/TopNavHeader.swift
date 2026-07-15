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
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // iOS 26: Pure liquid glass with shadow
            Circle()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: Circle())
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        } else {
            fallbackIconButtonBackground
        }
        #else
        fallbackIconButtonBackground
        #endif
    }

    @ViewBuilder
    private var fallbackIconButtonBackground: some View {
        // iOS 18+: Ultra thin material fallback with shadow
        Circle()
            .fill(.thinMaterial)
            .overlay(
                Circle()
                    .strokeBorder(theme.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
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
            // Active chat state: gradient circle with glassy sheen and shadow
            ZStack {
                // Base gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [PrimaryScale.primary600, PrimaryScale.primary800],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Glassy sheen overlay
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.05),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Subtle inner border for glass edge
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
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
