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
    @State private var showSummarySheet = false
    @State private var summaryError: String?
    @State private var activeEntryRoute: EntryRoute?
    @State private var showEntryToast = false

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

    public init() {}

    public var body: some View {
        ZStack(alignment: .leading) {
            // Full-screen background that extends to all edges
            theme.background
                .ignoresSafeArea()

            // The left drawer used to live here, behind the main content, and
            // slid it aside via an offset/clip transform. It is gone: its
            // edge-swipe was attached with `.gesture` to the whole
            // NavigationStack, so every horizontal drag in the app arbitrated
            // against it. A root pager cannot share the screen with that.
            // Profile and settings now live in a bottom sheet on the Journal
            // page instead.
            NavigationStack(path: $navigationPath) {
                ZStack(alignment: .top) {
                    // Full-screen background that extends to all edges
                    theme.background
                        .ignoresSafeArea()

                    // Whole-page horizontal paging. Each page owns its own
                    // header and its own chrome, so nothing floats above both.
                    RootPager(selection: $selectedPage) { page in
                        switch page {
                        case .journal:
                            JournalView(
                                isEmbedded: true,
                                externalNavigationPath: $navigationPath,
                                onOpenChat: { selectedPage = .chat },
                                onPresentEntry: { route in
                                    activeEntryRoute = route
                                }
                            )
                        case .chat:
                            AIChatView(
                                viewModel: chatViewModel,
                                isEmbedded: true,
                                hasEntries: !entryViewModel.entries.isEmpty,
                                onOpenJournal: { selectedPage = .journal }
                            )
                        }
                    }

                    // Gradient blur overlay — bottom only, Journal tab only
                    // (AIChatView handles its own bottom fade).
                    //
                    // The matching top fade was removed when TopNavHeader became
                    // Liquid Glass. `ScrollEdgeFade(.top)` is opaque for its first
                    // 75% (`ScrollEdgeFade.swift`), so it painted a full-width band
                    // of solid `theme.background` directly behind the floating
                    // header — and glass over an opaque colour renders as an opaque
                    // panel. That scrim is the reason the 2026-08-07 glass attempt
                    // read as flat gray. Content now meets the header via the
                    // system scroll-edge effect on each tab's scroll view instead.
                    // NOTE: the global OfflineBannerContainer was removed 2026-08-08,
                    // and OfflineBanner + NetworkMonitor were deleted outright in the
                    // pre-1.0 cleanup. Nothing in this app needs a network — there are
                    // zero URLSession call sites — and the banner's copy promised a
                    // sync that no longer exists after the Supabase decommission.
                    // PRES-010 scopes offline UI to Z1-only features; when Z1 lands,
                    // recreate both from git history rather than reviving stale copy.
                    //
                    // The bottom scroll fade and the new-entry FAB both moved into
                    // JournalView. As siblings of the pager they needed a
                    // `swipeProgress` scalar to fade out on the way to Chat; inside
                    // the page they simply travel with it.
                }
                .ignoresSafeArea(edges: .all)
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarHidden(true)
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
        .environment(\.selectedTab, $selectedPage)
        .environment(\.tabBarHidden, $isTabBarHidden)
        .useTheme()
        .useTypography()
        .onAppear {
            if let tab = previewInitialTab, !didSetPreviewTab {
                selectedPage = tab
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

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func entrySheet(for route: EntryRoute) -> some View {
        switch route {
        case .create:
            AddEntryView(state: .create) { title, text, photoAction in
                entryViewModel.createEntry(title: title, text: text, photoAction: photoAction)
                activeEntryRoute = nil
                showEntryToast = true
            }
            .environment(\.fabVisible, false)
        case .createWithTitle(let prefillTitle):
            AddEntryView(state: .createWithTitle(prefillTitle)) { title, text, photoAction in
                entryViewModel.createEntry(title: title, text: text, photoAction: photoAction)
                activeEntryRoute = nil
                showEntryToast = true
            }
            .environment(\.fabVisible, false)
        case .createWithContent(let prefillTitle, let prefillContent):
            AddEntryView(state: .createWithContent(title: prefillTitle, content: prefillContent)) { title, text, photoAction in
                entryViewModel.createEntry(title: title, text: text, photoAction: photoAction)
                activeEntryRoute = nil
                showEntryToast = true
            }
            .environment(\.fabVisible, false)
        case .edit(let entry):
            AddEntryView(state: .edit(entry)) { title, text, photoAction in
                var updated = entry
                updated.title = title
                updated.text = text
                entryViewModel.updateEntry(updated, photoAction: photoAction)
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
        .environment(\.previewInitialTab, .chat)
        .environmentObject(AppStateStore())
        .useTheme()
        .useTypography()
}
