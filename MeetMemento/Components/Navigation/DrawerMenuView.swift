//
//  DrawerMenuView.swift
//  MeetMemento
//
//  Slide-out drawer menu panel with navigation options.
//  Displays logo, menu items for editing profile/goals, and settings button.
//

import SwiftUI

/// The slide-out drawer menu panel.
public struct DrawerMenuView: View {
    let onAboutYourselfTapped: () -> Void
    let onJournalGoalsTapped: () -> Void
    let onSettingsTapped: () -> Void
    let onClose: () -> Void
    /// Called when user swipes left to close (passes drag offset for interactive animation)
    var onSwipeClose: ((CGFloat) -> Void)?
    /// Called when swipe gesture ends (passes velocity for threshold detection)
    var onSwipeEnd: ((CGFloat) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme

    /// Width of the drawer
    static let drawerWidth: CGFloat = 280

    @State private var dragOffset: CGFloat = 0

    public init(
        onAboutYourselfTapped: @escaping () -> Void,
        onJournalGoalsTapped: @escaping () -> Void,
        onSettingsTapped: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onSwipeClose: ((CGFloat) -> Void)? = nil,
        onSwipeEnd: ((CGFloat) -> Void)? = nil
    ) {
        self.onAboutYourselfTapped = onAboutYourselfTapped
        self.onJournalGoalsTapped = onJournalGoalsTapped
        self.onSettingsTapped = onSettingsTapped
        self.onClose = onClose
        self.onSwipeClose = onSwipeClose
        self.onSwipeEnd = onSwipeEnd
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo section
            logoSection
                .padding(.top, safeAreaTop + 24)
                .padding(.horizontal, 20)

            Spacer().frame(height: 40)

            // Menu items
            VStack(spacing: 0) {
                DrawerMenuItem(
                    icon: "person",
                    title: "About yourself",
                    onTap: {
                        onAboutYourselfTapped()
                    }
                )

                DrawerMenuItem(
                    icon: "slider.horizontal.3",
                    title: "Your journal goals",
                    onTap: {
                        onJournalGoalsTapped()
                    }
                )
            }

            Spacer()

            // Settings button at bottom
            settingsButton
                .padding(.horizontal, 20)
                .padding(.bottom, safeAreaBottom + 24)
        }
        .frame(width: DrawerMenuView.drawerWidth)
        .frame(maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .ignoresSafeArea()
        .gesture(swipeToCloseGesture)
    }

    // MARK: - Swipe to Close Gesture

    private var swipeToCloseGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Only respond to left swipes
                if value.translation.width < 0 {
                    let offset = value.translation.width
                    dragOffset = offset
                    onSwipeClose?(offset)
                }
            }
            .onEnded { value in
                let threshold = DrawerMenuView.drawerWidth * 0.3
                let velocity = value.velocity.width

                // Close if dragged past threshold or fast swipe
                if dragOffset < -threshold || velocity < -500 {
                    onSwipeEnd?(velocity)
                } else {
                    // Reset
                    onSwipeClose?(0)
                }
                dragOffset = 0
            }
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        Image("Memento-Logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 32)
    }

    // MARK: - Settings Button

    private var settingsButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onClose()
            onSettingsTapped()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gear")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.foreground)

                Text("Settings")
                    .font(type.body1)
                    .foregroundStyle(theme.foreground)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(settingsButtonBackground)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var settingsButtonBackground: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .mementoGlassEffect(.regular, in: Capsule())
        } else {
            Capsule()
                .fill(theme.secondary) // Use semantic token for light/dark support
        }
    }

    // MARK: - Safe Area Helpers

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }

    private var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }
}

// MARK: - Previews

#Preview("DrawerMenuView • Light") {
    ZStack(alignment: .leading) {
        Color.gray.opacity(0.3).ignoresSafeArea()

        DrawerMenuView(
            onAboutYourselfTapped: { print("About yourself") },
            onJournalGoalsTapped: { print("Journal goals") },
            onSettingsTapped: { print("Settings") },
            onClose: {}
        )
    }
    .useTheme()
    .useTypography()
}

#Preview("DrawerMenuView • Dark") {
    ZStack(alignment: .leading) {
        Color.black.ignoresSafeArea()

        DrawerMenuView(
            onAboutYourselfTapped: { print("About yourself") },
            onJournalGoalsTapped: { print("Journal goals") },
            onSettingsTapped: { print("Settings") },
            onClose: {}
        )
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
