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
    static let defaultValue: JournalTopTab? = nil
}
private struct TabBarHiddenKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}
private struct ShowAccessoryKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}
private struct SelectedTabKey: EnvironmentKey {
    static let defaultValue: Binding<JournalTopTab>? = nil
}
private struct FABVisibleKey: EnvironmentKey {
    static let defaultValue: Bool = true
}
extension EnvironmentValues {
    var previewEntryViewModel: EntryViewModel? {
        get { self[PreviewEntryViewModelKey.self] }
        set { self[PreviewEntryViewModelKey.self] = newValue }
    }
    var previewInitialTab: JournalTopTab? {
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
    var selectedTab: Binding<JournalTopTab>? {
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
    /// Selected tab using JournalTopTab enum for top pill navigation
    @State private var selectedTab: JournalTopTab = .yourEntries
    @State private var swipeProgress: CGFloat = 0
    @State private var didSetPreviewTab = false
    @State private var isTabBarHidden = false
    @State private var showAccessory = true
    @State private var showJournalSearch = false
    @State private var showSummarySheet = false
    @State private var summaryError: String?
    @State private var activeEntryRoute: EntryRoute?
    @State private var showEntryToast = false

    /// Consolidated navigation path for all routes
    @State private var navigationPath = NavigationPath()

    // MARK: - Drawer State
    @State private var isDrawerOpen = false
    @State private var drawerDragOffset: CGFloat = 0
    private let drawerWidth: CGFloat = DrawerMenuView.drawerWidth

    @StateObject private var defaultEntryViewModel = EntryViewModel()
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @Environment(\.previewEntryViewModel) private var previewEntryViewModel: EntryViewModel?
    @Environment(\.previewInitialTab) private var previewInitialTab: JournalTopTab?

    private var entryViewModel: EntryViewModel {
        previewEntryViewModel ?? defaultEntryViewModel
    }

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var appState: AppStateStore

    public init() {}

    public var body: some View {
        ZStack(alignment: .leading) {
            // Layer 0: Full-screen background that extends to all edges
            theme.background
                .ignoresSafeArea()

            // Layer 1: Drawer menu (behind main content)
            DrawerMenuView(
                onAboutYourselfTapped: {
                    navigationPath.append(DrawerRoute.aboutYourself)
                },
                onJournalGoalsTapped: {
                    navigationPath.append(DrawerRoute.journalGoals)
                },
                onSettingsTapped: {
                    navigationPath.append(SettingsRoute.main)
                },
                onClose: {
                    closeDrawer()
                },
                onSwipeClose: { offset in
                    // Update drag offset for interactive closing
                    drawerDragOffset = offset
                },
                onSwipeEnd: { velocity in
                    // Close drawer when swipe ends past threshold
                    closeDrawer()
                }
            )
            .offset(x: isDrawerOpen ? 0 : -drawerWidth)

            // Tap-to-close overlay (only when drawer is open)
            if isDrawerOpen {
                Color.black.opacity(0.001) // Nearly invisible but captures taps
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeDrawer()
                    }
                    .offset(x: drawerWidth) // Position it over the main content area
            }

            // Layer 2: Main content (slides right when drawer opens)
            NavigationStack(path: $navigationPath) {
                ZStack(alignment: .top) {
                    // Full-screen background that extends to all edges
                    theme.background
                        .ignoresSafeArea()

                    // Main content with swipeable tabs
                    // Note: Views handle their own top padding when isEmbedded == true
                    TopTabNavContainer(selection: $selectedTab, swipeProgress: $swipeProgress, showTopNav: false) { tab in
                        switch tab {
                        case .yourEntries:
                            JournalView(
                                isEmbedded: true,
                                externalNavigationPath: $navigationPath,
                                onSwipeToOpenMenu: { openDrawer() },
                                onPresentEntry: { route in
                                    activeEntryRoute = route
                                }
                            )
                        case .digDeeper:
                            AIChatView(
                                viewModel: chatViewModel,
                                isEmbedded: true,
                                hasEntries: !entryViewModel.entries.isEmpty
                            )
                        }
                    }

                    // Gradient blur overlays - at ContentView level to extend to absolute screen edges
                    // Top fade covers area behind TopNavHeader pills for better visibility while scrolling
                    // Bottom fade only for Journal tab (AIChatView handles its own bottom fade)
                    VStack(spacing: 0) {
                        ScrollEdgeFade(edge: .top, height: 100 + safeAreaTop)
                        Spacer()
                        if selectedTab == .yourEntries {
                            ScrollEdgeFade(edge: .bottom, height: 60)
                        }
                    }
                    .padding(.top, -safeAreaTop)
                    .ignoresSafeArea()

                    // Floating header
                    VStack {
                        TopNavHeader(
                            selection: $selectedTab,
                            hasActiveChat: chatViewModel.hasActiveChat,
                            userInitial: appState.firstName?.first.map { String($0) },
                            onMenuTapped: {
                                // Toggle drawer
                                if isDrawerOpen {
                                    closeDrawer()
                                } else {
                                    openDrawer()
                                }
                            },
                            onActionTapped: {
                                // Context-aware action: search for Journal, summarize/new entry for Insights
                                if selectedTab == .yourEntries {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        showJournalSearch = true
                                    }
                                } else {
                                    // Show summary sheet if active chat, otherwise create new entry
                                    if chatViewModel.hasActiveChat {
                                        showSummarySheet = true
                                    } else {
                                        activeEntryRoute = .create
                                    }
                                }
                            }
                        )
                        .padding(.top, safeAreaTop + 8)

                        // NOTE: the global OfflineBannerContainer was removed 2026-08-08.
                        // Nothing in this app needs a network — there are zero URLSession
                        // call sites — and the banner's own copy ("entries save locally
                        // and sync when you're back") promised a sync that no longer
                        // exists after the Supabase decommission. Shown in theme.destructive
                        // red, it presented the app's normal state as an error on every
                        // screen. PRES-010 already scopes it to Z1-only features; no Z1
                        // feature has shipped, so it applies to nothing. The component and
                        // NetworkMonitor are retained for when Z1 lands.

                        Spacer()
                    }

                    // FAB - Journal tab only, creates new entry
                    // Animates interactively with swipe progress
                    // Hidden completely when swipe progress > 95% to prevent lingering
                    // Hidden when no entries exist (empty state has its own CTA button)
                    if showAccessory && swipeProgress < 0.95 && !entryViewModel.entries.isEmpty {
                        PositionedNewEntryFAB(swipeProgress: swipeProgress) {
                            activeEntryRoute = .create
                        }
                    }
                }
                .ignoresSafeArea(edges: .all)
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarHidden(true)
                .overlay {
                    if showJournalSearch {
                        JournalSearchView(isPresented: $showJournalSearch, navigationPath: $navigationPath)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .zIndex(100)
                    }
                }
                .sheet(item: $activeEntryRoute) { route in
                    entrySheet(for: route)
                        .presentationDetents([.fraction(0.95)])
                        .presentationDragIndicator(.hidden)
                        .presentationCornerRadius(32)
                        .interactiveDismissDisabled(false)
                }
                .navigationDestination(for: SettingsRoute.self) { route in
                    settingsDestination(for: route)
                }
                .navigationDestination(for: DrawerRoute.self) { route in
                    drawerDestination(for: route)
                }
            }
            .ignoresSafeArea(edges: .all)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background.ignoresSafeArea())
            .clipShape(RoundedRectangle(cornerRadius: isDrawerOpen || drawerDragOffset > 0 ? 32 : 0))
            .shadow(color: .black.opacity(isDrawerOpen || drawerDragOffset > 0 ? 0.15 : 0), radius: 20, x: -5, y: 0)
            .offset(x: mainContentOffset)
            .disabled(isDrawerOpen)
            .gesture(edgeSwipeGesture)
            .ignoresSafeArea(edges: .all)
        }
        .ignoresSafeArea(edges: .all)
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
        .environment(\.selectedTab, $selectedTab)
        .environment(\.tabBarHidden, $isTabBarHidden)
        .environment(\.showAccessory, $showAccessory)
        .useTheme()
        .useTypography()
        .onAppear {
            if let tab = previewInitialTab, !didSetPreviewTab {
                selectedTab = tab
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
        }
        .onChange(of: selectedTab) { _, newTab in
            // Sync swipeProgress when tab changes via pill tap (fallback for geometry tracking)
            withAnimation(.smooth(duration: 0.3)) {
                swipeProgress = newTab == .yourEntries ? 0 : 1
            }
        }
        .onChange(of: navigationPath) { _, _ in
            // Close drawer when any navigation occurs
            if isDrawerOpen {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isDrawerOpen = false
                    drawerDragOffset = 0
                }
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
        .environmentObject(networkMonitor)
        .sheet(isPresented: $showSummarySheet) {
            ChatSummarySheet(
                onSummarize: {
                    Task {
                        do {
                            let summary = try await chatViewModel.generateChatSummary()
                            await MainActor.run {
                                showSummarySheet = false
                                activeEntryRoute = .createWithContent(
                                    title: summary.title,
                                    content: summary.content
                                )
                            }
                        } catch {
                            await MainActor.run {
                                summaryError = error.localizedDescription
                            }
                        }
                    }
                },
                isSummarizing: chatViewModel.isSummarizing
            )
        }
        .alert("Summary Failed", isPresented: .init(
            get: { summaryError != nil },
            set: { if !$0 { summaryError = nil } }
        )) {
            Button("OK") { summaryError = nil }
        } message: {
            Text(summaryError ?? "Unable to generate summary. Please try again.")
        }
    }

    // MARK: - Safe Area Helper

    private var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }

    // MARK: - Drawer Helpers

    /// Calculated offset for main content based on drawer state and drag
    private var mainContentOffset: CGFloat {
        if isDrawerOpen {
            // When drawer is open, offset by drawer width + any close-swipe offset
            return max(0, drawerWidth + drawerDragOffset)
        } else {
            // When drawer is closed, use the open-swipe drag offset
            return max(0, drawerDragOffset)
        }
    }

    /// Edge swipe gesture to open drawer
    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { value in
                // Only activate from left 40pt edge when drawer is closed
                if !isDrawerOpen && value.startLocation.x < 40 && value.translation.width > 0 {
                    drawerDragOffset = min(value.translation.width, drawerWidth)
                }
                // Allow swipe to close when drawer is open
                else if isDrawerOpen && value.translation.width < 0 {
                    drawerDragOffset = max(value.translation.width, -drawerWidth)
                }
            }
            .onEnded { value in
                let threshold = drawerWidth * 0.4

                if !isDrawerOpen {
                    // Opening gesture
                    if drawerDragOffset > threshold || value.velocity.width > 500 {
                        openDrawer()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            drawerDragOffset = 0
                        }
                    }
                } else {
                    // Closing gesture
                    if drawerDragOffset < -threshold || value.velocity.width < -500 {
                        closeDrawer()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            drawerDragOffset = 0
                        }
                    }
                }
            }
    }

    private func openDrawer() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isDrawerOpen = true
            drawerDragOffset = 0
        }
    }

    private func closeDrawer() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isDrawerOpen = false
            drawerDragOffset = 0
        }
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func entrySheet(for route: EntryRoute) -> some View {
        switch route {
        case .create:
            AddEntryView(state: .create) { title, text in
                entryViewModel.createEntry(title: title, text: text)
                activeEntryRoute = nil
                showEntryToast = true
            }
            .environment(\.fabVisible, false)
        case .createWithTitle(let prefillTitle):
            AddEntryView(state: .createWithTitle(prefillTitle)) { title, text in
                entryViewModel.createEntry(title: title, text: text)
                activeEntryRoute = nil
                showEntryToast = true
            }
            .environment(\.fabVisible, false)
        case .createWithContent(let prefillTitle, let prefillContent):
            AddEntryView(state: .createWithContent(title: prefillTitle, content: prefillContent)) { title, text in
                entryViewModel.createEntry(title: title, text: text)
                activeEntryRoute = nil
                showEntryToast = true
            }
            .environment(\.fabVisible, false)
        case .edit(let entry):
            AddEntryView(state: .edit(entry)) { title, text in
                var updated = entry
                updated.title = title
                updated.text = text
                entryViewModel.updateEntry(updated)
                activeEntryRoute = nil
                showEntryToast = true
            }
            .environment(\.fabVisible, false)
        }
    }

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
        case .security:
            SecuritySettingsView()
                .environmentObject(entryViewModel)
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        case .about:
            AboutSettingsView()
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
        .preferredColorScheme(.light)
}

#Preview("Dark - iPhone 15 Pro") {
    ContentView()
        .environmentObject(AppStateStore())
        .preferredColorScheme(.dark)
}

#Preview("Insights tab with entries") {
    @Previewable @StateObject var entryViewModel = EntryViewModel.withPreviewEntries()
    ContentView()
        .environment(\.previewEntryViewModel, entryViewModel)
        .environment(\.previewInitialTab, .digDeeper)
        .environmentObject(AppStateStore())
        .useTheme()
        .useTypography()
}
