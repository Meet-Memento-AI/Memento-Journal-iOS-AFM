//
//  ProfileSheet.swift
//  MeetMemento
//
//  Profile and settings, opened from the Journal header's avatar.
//
//  Replaces the left drawer. The drawer's edge-swipe was attached to the whole
//  NavigationStack, so every horizontal drag in the app arbitrated against it —
//  impossible to reconcile with a root pager. A sheet has no edge gesture of its
//  own, so the pager gets the horizontal axis to itself.
//
//  "About yourself" and "Your journal themes" have no other entry point in the
//  app; losing them here would orphan EditAboutYourselfView and
//  EditJournalGoalsView.
//

import SwiftUI

struct ProfileSheet: View {
    /// The app's main navigation path, used only by the standalone fallback —
    /// rows normally push inside this sheet's own stack.
    var navigationPath: Binding<NavigationPath>

    @EnvironmentObject private var entryViewModel: EntryViewModel
    @EnvironmentObject private var appState: AppStateStore
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Its own stack, so rows push in place and you can swipe back without
        // losing the sheet — rather than dismissing and pushing full-width on
        // the main stack, which reads as a two-stage jump.
        NavigationStack {
            VStack(spacing: 0) {
                dragHandle
                header

                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        SettingsSection(title: "You") {
                            NavigationLink(value: DrawerRoute.aboutYourself) {
                                SettingsRow(
                                    icon: "person",
                                    title: "About yourself",
                                    subtitle: "What Memento knows about you",
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)

                            SettingsRowDivider()

                            NavigationLink(value: DrawerRoute.journalGoals) {
                                SettingsRow(
                                    icon: "slider.horizontal.3",
                                    title: "Your journal themes",
                                    subtitle: "What you want to reflect on",
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        SettingsSection(title: "App") {
                            NavigationLink(value: SettingsRoute.main) {
                                SettingsRow(
                                    icon: "gear",
                                    title: "Settings",
                                    subtitle: "Appearance, security, data and privacy",
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                            // Was `drawer.settings` — renamed with the drawer it
                            // named. The upgrade-migration UI test drives this row.
                            .accessibilityIdentifier("profile.settings")
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
                }
            }
            .background(theme.background.ignoresSafeArea())
            .navigationDestination(for: SettingsRoute.self) { route in
                settingsDestination(for: route)
            }
            .navigationDestination(for: DrawerRoute.self) { route in
                drawerDestination(for: route)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
    }

    // MARK: - Chrome

    /// Hand-drawn to the house spec (`ChatHistorySheet`, `CitationsBottomSheet`),
    /// which is why `.presentationDragIndicator` is hidden.
    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(theme.mutedForeground.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 20)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AvatarInitialButton(
                initial: appState.firstName?.first.map { String($0) },
                size: 44,
                accessibilityLabel: "Your profile"
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.firstName ?? "Your account")
                    .font(type.h5)
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
                Text("On this device only")
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Destinations
    // Mirrors ContentView's builders. SettingsView needs both environment
    // objects, and a sheet's own NavigationStack does not inherit them from the
    // presenting view's stack, so they are re-injected here.

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .main:
            SettingsView()
                .environmentObject(entryViewModel)
                .environmentObject(appState)
        case .profile:
            ProfileSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .voice:
            VoiceSettingsView()
        case .security:
            SecuritySettingsView()
                .environmentObject(entryViewModel)
        case .about:
            AboutSettingsView()
        }
    }

    @ViewBuilder
    private func drawerDestination(for route: DrawerRoute) -> some View {
        switch route {
        case .aboutYourself:
            EditAboutYourselfView()
        case .journalGoals:
            EditJournalGoalsView()
        }
    }
}

// MARK: - Previews

#Preview("Profile sheet") {
    Rectangle()
        .fill(Color.gray.opacity(0.2))
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            ProfileSheet(navigationPath: .constant(NavigationPath()))
                .environmentObject(EntryViewModel())
                .environmentObject(AppStateStore())
                .useTheme()
                .useTypography()
        }
}
