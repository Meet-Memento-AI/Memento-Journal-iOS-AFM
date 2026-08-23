//
//  ContentView.swift
//  MeetMemento
//

//  Main content view with top pill-based navigation.
//  - Journal tab: displays user's journal entries
//  - Insights tab: displays AI chat interface (inline)
//

import SwiftUI

private struct PreviewEntryViewModelKey: EnvironmentKey {
    static let defaultValue: EntryViewModel? = nil
}
private struct PreviewInitialTabKey: EnvironmentKey {
    static let defaultValue: RootPage? = nil
}
private struct TabBarHiddenKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}
private struct ShowAccessoryKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}
private struct SelectedTabKey: EnvironmentKey {
    static let defaultValue: Binding<RootPage>? = nil
}
private struct FABVisibleKey: EnvironmentKey {
    static let defaultValue: Bool = true
}
extension EnvironmentValues {
    var previewEntryViewModel: EntryViewModel? {
        get { self[PreviewEntryViewModelKey.self] }
        set { self[PreviewEntryViewModelKey.self] = newValue }
    }
    var previewInitialTab: RootPage? {
        get { self[PreviewInitialTabKey.self] }
        set { self[PreviewInitialTabKey.self] = newValue }
    }
    var tabBarHidden: Binding<Bool>? {
        get { self[TabBarHiddenKey.self] }
        set { self[TabBarHiddenKey.self] = newValue }
    }
    var showAccessory: Binding<Bool>? {
        get { self[ShowAccessoryKey.self] }
        set { self[ShowAccessoryKey.self] = newValue }
    }
    var selectedTab: Binding<RootPage>? {
        get { self[SelectedTabKey.self] }
        set { self[SelectedTabKey.self] = newValue }
    }
    var fabVisible: Bool {
        get { self[FABVisibleKey.self] }
        set { self[FABVisibleKey.self] = newValue }
    }
}

// MARK: - Scroll Direction Tracker

/// ViewModifier that tracks scroll direction and updates the tabBarHidden binding.
/// Used for iOS 18 fallback to manually hide/show the tab bar accessory.
/// IMPORTANT: Only activates on iOS 18.x - does nothing on iOS 26+ to avoid interfering with native behavior.
private struct ScrollOffsetModifier: ViewModifier {
    @Binding var tabBarHidden: Bool
    @State private var lastOffset: CGFloat = 0
    @State private var currentOffset: CGFloat = 0
    @StateObject private var scrollDebouncer = ScrollDebouncer(delay: 0.1)

    private let threshold: CGFloat = 50 // Minimum scroll distance to trigger state change

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // iOS 26+: Native scroll tracking - don't interfere
            content
        } else {
            // iOS 18-25: Manual scroll tracking with debouncing
            content
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("scroll")).minY
                            )
                    }
                )
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollDebouncer.debounce {
                        let delta = value - lastOffset
                        currentOffset = value

                        // Scrolling down (delta < 0) - hide tab bar
                        if delta < -threshold && !tabBarHidden {
                            tabBarHidden = true
                        }
                        // Scrolling up (delta > 0) - show tab bar
                        else if delta > threshold && tabBarHidden {
                            tabBarHidden = false
                        }

                        lastOffset = value
                    }
                }
        }
    }
}


extension View {
    /// Attach to a ScrollView to track scroll direction and toggle tab bar visibility
    func trackScrollDirection(tabBarHidden: Binding<Bool>) -> some View {
        self.modifier(ScrollOffsetModifier(tabBarHidden: tabBarHidden))
    }
}

public struct ContentView: View {
    /// Which root page the pager is showing.
    @State private var selectedPage: RootPage = .journal
    @State private var didSetPreviewTab = false
    @State private var isTabBarHidden = false
    @State private var showEntryToast = false
    @Namespace private var entryZoom
    /// Keeps the overlay stack composited through a zoom-out. Snapping opacity
    /// to 0 the instant the path is empty hides the reverse morph.
    @State private var holdOverlayForZoomOut = false
    @State private var overlayHoldTask: Task<Void, Never>?

    /// Overlay is on while a destination is pushed, and for a beat after pop
    /// so `.navigationTransition(.zoom)` can shrink back to its source.
    private var overlayActive: Bool {
        !navigationPath.isEmpty || holdOverlayForZoomOut
    }

    /// Consolidated navigation path for all routes
    @State private var navigationPath = NavigationPath()

    @StateObject private var defaultEntryViewModel = EntryViewModel()
    @StateObject private var chatViewModel = ChatViewModel()
    @Environment(\.previewEntryViewModel) private var previewEntryViewModel: EntryViewModel?
    @Environment(\.previewInitialTab) private var previewInitialTab: RootPage?

    private var entryViewModel: EntryViewModel {
        previewEntryViewModel ?? defaultEntryViewModel
    }

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var appState: AppStateStore
    @EnvironmentObject var navigationState: AppNavigationState

    public init() {}

    public var body: some View {
        ZStack(alignment: .leading) {
            // Full-screen background that extends to all edges
            theme.secondaryBackground
                .ignoresSafeArea()

            // Journal and Chat share RootPageScaffold on the pager.
            // Narration is a mode of AIChatView, not a sibling overlay.
            // NavigationStack must not wrap the pager.
            RootPager(selection: $selectedPage) { page in
                switch page {
                case .journal:
                    JournalView(
                        isEmbedded: true,
                        externalNavigationPath: $navigationPath,
                        onOpenChat: { RootPage.select(.chat, in: $selectedPage) }
                    )
                case .chat:
                    AIChatView(
                        viewModel: chatViewModel,
                        isEmbedded: true,
                        hasEntries: !entryViewModel.entries.isEmpty,
                        onOpenJournal: { RootPage.select(.journal, in: $selectedPage) },
                        onPresentEntry: { route in
                            if case .edit(let id) = route {
                                entryViewModel.selectedEntryId = id
                            }
                            navigationPath.append(route)
                        }
                    )
                }
            }

            // Destinations that still push on `navigationPath` (search, the
            // standalone journal toolbar). Hit-testing is off while the path
            // is empty so the pager receives swipes.
            NavigationStack(path: $navigationPath) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .navigationDestination(for: SettingsRoute.self) { route in
                        settingsDestination(for: route)
                    }
                    .navigationDestination(for: DrawerRoute.self) { route in
                        drawerDestination(for: route)
                    }
                    .navigationDestination(for: EntryRoute.self) { route in
                        EntryEditorDestination(route: route) {
                            showEntryToast = true
                        }
                    }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .containerBackground(.clear, for: .navigation)
            .allowsHitTesting(overlayActive)
            .opacity(overlayActive ? 1 : 0)
            .animation(nil, value: overlayActive)
            .onChange(of: navigationPath.isEmpty) { _, isEmpty in
                overlayHoldTask?.cancel()
                if isEmpty {
                    holdOverlayForZoomOut = true
                    overlayHoldTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled, navigationPath.isEmpty else { return }
                        holdOverlayForZoomOut = false
                    }
                } else {
                    holdOverlayForZoomOut = false
                }
            }
        }
        .environment(\.entryZoomNamespace, entryZoom)
        .overlay(alignment: .bottom) {
            if showEntryToast {
                JournalToast(message: "Entry saved") {
                    showEntryToast = false
                }
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showEntryToast)
            }
        }
        .environmentObject(entryViewModel)
        .environmentObject(navigationState)
        .environment(\.selectedTab, $selectedPage)
        .environment(\.tabBarHidden, $isTabBarHidden)
        .useTheme()
        .useTypography()
        .onAppear {
            if let tab = previewInitialTab, !didSetPreviewTab {
                RootPage.select(tab, in: $selectedPage)
                didSetPreviewTab = true
            }
            // Update activity timestamp when ContentView appears
            SecurityService.shared.updateActivityTimestamp()
        }
        .task {
            // Pick up the encryption PIN from Keychain for every security
            // mode, not just the skipped-lock silent PIN. The lock screen's
            // `.didUnlockWithPIN` notification fires while ContentView isn't
            // mounted yet (the app root swaps LockScreenView out for
            // ContentView only after unlock), so it can never be received
            // here — but reaching this view at all means the lock was passed,
            // which is the exact access control the notification represented.
            if let pin = SecurityService.shared.getPIN() {
                entryViewModel.setSessionPIN(pin)
            }
            navigationState.primarySection = selectedPage
            await chatViewModel.fetchSessions()
        }
        .onChange(of: selectedPage) { _, page in
            navigationState.primarySection = page
        }
        .onChange(of: navigationState.primarySection) { _, section in
            if selectedPage != section {
                RootPage.select(section, in: $selectedPage)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didUnlockWithPIN)) { notification in
            // Pass the PIN to EntryViewModel for encryption operations
            if let pin = notification.userInfo?["pin"] as? String {
                entryViewModel.setSessionPIN(pin)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Clear session PIN when app goes to background (locks)
            if newPhase == .background || newPhase == .inactive {
                entryViewModel.clearSessionPIN()
            } else if newPhase == .active {
                // Restore the PIN on return to foreground, for every mode
                // (see the `.task` comment above). If the app actually
                // locked, ContentView is unmounted and this never fires;
                // if it didn't lock, this undoes the clear above.
                if let pin = SecurityService.shared.getPIN() {
                    entryViewModel.setSessionPIN(pin)
                }
            }
        }
        // The chat-summary sheet and its "Summary Failed" alert used to be
        // duplicated here. They were orphaned when the shared header was
        // replaced by per-page headers — nothing could set `showSummarySheet`
        // once ContentView stopped drawing chat's chrome. AIChatView owns the
        // whole flow now and hands the finished summary back through
        // `onPresentEntry`, which appends `EntryRoute` onto the overlay
        // NavigationStack — the only path that actually calls
        // `entryViewModel.createEntry`.
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .main:
            SettingsView()
                .environmentObject(entryViewModel)
                .environmentObject(appState)
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        case .profile:
            ProfileSettingsView()
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        case .appearance:
            AppearanceSettingsView()
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        case .voice:
            VoiceSettingsView()
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        case .security:
            SecuritySettingsView()
                .environmentObject(entryViewModel)
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        case .about:
            AboutSettingsView()
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        case .acknowledgments:
            AcknowledgmentsView()
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        case .weekly:
            WeeklyReflectionView()
                .environmentObject(entryViewModel)
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        case .patterns:
            PatternsView()
                .environmentObject(entryViewModel)
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        }
    }

    @ViewBuilder
    private func drawerDestination(for route: DrawerRoute) -> some View {
        switch route {
        case .aboutYourself:
            EditAboutYourselfView()
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        case .journalGoals:
            EditJournalGoalsView()
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        }
    }
}

// MARK: - Previews
#Preview("Light - iPhone 15 Pro") {
    ContentView()
        .environmentObject(AppStateStore())
        .environmentObject(AppNavigationState())
        .preferredColorScheme(.light)
}

#Preview("Dark - iPhone 15 Pro") {
    ContentView()
        .environmentObject(AppStateStore())
        .environmentObject(AppNavigationState())
        .preferredColorScheme(.dark)
}

#Preview("Insights tab with entries") {
    @Previewable @StateObject var entryViewModel = EntryViewModel.withPreviewEntries()
    ContentView()
        .environment(\.previewEntryViewModel, entryViewModel)
        .environment(\.previewInitialTab, .chat)
        .environmentObject(AppStateStore())
        .environmentObject(AppNavigationState())
        .useTheme()
        .useTypography()
}
