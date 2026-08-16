
//
//  JournalView.swift
//  MeetMemento
//
//  Main journal view with integrated navigation stack and toolbar
//

import SwiftUI

// MARK: - Month Header Position Tracking

struct MonthHeaderPositionEntry: Equatable {
    let monthStart: Date
    let y: CGFloat
}

struct MonthHeaderPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [MonthHeaderPositionEntry] { [] }
    static func reduce(value: inout [MonthHeaderPositionEntry], nextValue: () -> [MonthHeaderPositionEntry]) {
        value.append(contentsOf: nextValue())
    }
}

public struct JournalView: View {
    /// When true, hides internal NavigationStack (uses external from ContentView)
    var isEmbedded: Bool = false
    /// External navigation path binding when embedded
    @Binding var externalNavigationPath: NavigationPath
    /// Page to the AI chat screen. The header's chat icon and a left swipe are
    /// the same navigation, so both route through here.
    var onOpenChat: (() -> Void)? = nil
    /// Callback to present entry sheet when embedded (ContentView provides this)
    var onPresentEntry: ((EntryRoute) -> Void)? = nil

    @EnvironmentObject var entryViewModel: EntryViewModel
    @EnvironmentObject var appState: AppStateStore

    @StateObject private var chatViewModel = ChatViewModel()
    @State private var internalNavigationPath = NavigationPath()

    // Month picker state
    @State private var showMonthPicker = false
    @State private var selectedDate = Date()
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    // Scroll-based month detection
    @State private var visibleMonthStart: Date? = nil

    // Task for loading data
    @State private var loadingTask: Task<Void, Never>?

    // Entry sheet state for standalone mode
    @State private var activeEntryRoute: EntryRoute?

    /// Search overlay and the profile/settings sheet, both driven by this
    /// page's own header. They used to live in ContentView because the header
    /// was shared; it isn't any more.
    @State private var showJournalSearch = false
    @State private var showProfileSheet = false

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    /// Use external navigation when embedded, internal when standalone
    private var navigationPath: Binding<NavigationPath> {
        isEmbedded ? $externalNavigationPath : $internalNavigationPath
    }

    // MARK: - Computed Properties

    private let monthNames = Calendar.current.monthSymbols

    private var availableMonths: [Date] {
        entryViewModel.entriesByMonth.map { $0.monthStart }.sorted(by: >)
    }

    private var availableYears: [Int] {
        let years = Set(availableMonths.map { Calendar.current.component(.year, from: $0) })
        return Array(years).sorted(by: >)
    }

    private var currentMonthDisplay: String {
        // Since scroll syncs with picker, we always use selectedDate
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM, yyyy"
        return formatter.string(from: selectedDate)
    }

    /// All entries grouped by month - no filtering for instant display of new entries
    private var allEntriesByMonth: [MonthGroup] {
        entryViewModel.entriesByMonth
    }

    private var availableMonthsForYear: [Int] {
        let calendar = Calendar.current
        let monthsForYear = availableMonths
            .filter { calendar.component(.year, from: $0) == selectedYear }
            .map { calendar.component(.month, from: $0) }
        return Array(Set(monthsForYear)).sorted()
    }

    public init(
        isEmbedded: Bool = false,
        externalNavigationPath: Binding<NavigationPath> = .constant(NavigationPath()),
        onOpenChat: (() -> Void)? = nil,
        onPresentEntry: ((EntryRoute) -> Void)? = nil
    ) {
        self.isEmbedded = isEmbedded
        self._externalNavigationPath = externalNavigationPath
        self.onOpenChat = onOpenChat
        self.onPresentEntry = onPresentEntry
    }

    public var body: some View {
        journalContent
            .onAppear {
                loadingTask = Task {
                    await entryViewModel.loadEntriesIfNeeded()
                    guard !Task.isCancelled else { return }

                    let calendar = Calendar.current
                    let hasEntriesForCurrentMonth = entryViewModel.entriesByMonth.contains { monthGroup in
                        calendar.isDate(monthGroup.monthStart, equalTo: Date(), toGranularity: .month)
                    }

                    if !hasEntriesForCurrentMonth, let mostRecent = entryViewModel.entriesByMonth.first {
                        selectedDate = mostRecent.monthStart
                        selectedMonth = calendar.component(.month, from: mostRecent.monthStart)
                        selectedYear = calendar.component(.year, from: mostRecent.monthStart)
                    }
                }
            }
            .onDisappear {
                loadingTask?.cancel()
                loadingTask = nil
            }
            .sheet(isPresented: $showMonthPicker) {
                monthPickerSheet
            }
    }

    // MARK: - Journal Content

    @ViewBuilder
    private var journalContent: some View {
        if isEmbedded {
            // When embedded, don't wrap in NavigationStack (ContentView provides it)
            coreContentView
        } else {
            // Standalone mode with own NavigationStack
            NavigationStack(path: navigationPath) {
                coreContentView
                    .navigationDestination(for: SettingsRoute.self) { route in
                        settingsDestination(for: route)
                    }
                    .navigationDestination(for: AIChatRoute.self) { route in
                        switch route {
                        case .main:
                            AIChatView(viewModel: chatViewModel)
                                .toolbar(.hidden, for: .tabBar)
                                .environment(\.fabVisible, false)
                        }
                    }
                    .sheet(item: $activeEntryRoute) { route in
                        entrySheet(for: route)
                            .presentationDetents([.fraction(0.95)])
                            .presentationDragIndicator(.hidden)
                            .presentationCornerRadius(32)
                            .interactiveDismissDisabled(false)
                    }
            }
        }
    }

    @ViewBuilder
    private var coreContentView: some View {
        ZStack {
            // Full-screen background - must fill entire space including safe areas
            theme.background
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .all)

            yourEntriesContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if isEmbedded {
                        // Spacer for FAB clearance when embedded
                        Color.clear.frame(height: 100)
                    }
                }
                // The header reserves its own height — no more hardcoded
                // `safeAreaTop + 8 + 44 + 32` guess in three separate files.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isEmbedded { journalHeader }
                }

            // Bottom scroll fade and the FAB both live inside the page now. As
            // siblings of the pager they needed a `swipeProgress` scalar to fade
            // out on the way to Chat; here they simply travel with the page.
            VStack(spacing: 0) {
                Spacer()
                ScrollEdgeFade(edge: .bottom, height: 60)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if isEmbedded,
               navigationPath.wrappedValue.isEmpty,
               !entryViewModel.entries.isEmpty {
                PositionedNewEntryFAB {
                    presentEntry(.create)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .all)
        // The right-swipe-to-open-drawer `simultaneousGesture` that used to sit
        // here is gone with the drawer. It fired *in addition to* the pager,
        // which is precisely the arbitration a root pager cannot tolerate.
        .background(theme.background.ignoresSafeArea(edges: .all))
        .overlay {
            if showJournalSearch {
                JournalSearchView(isPresented: $showJournalSearch,
                                  navigationPath: navigationPath)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .sheet(isPresented: $showProfileSheet) {
            ProfileSheet(navigationPath: navigationPath)
                .environmentObject(entryViewModel)
                .environmentObject(appState)
        }
        .toolbar {
                // Only show toolbar when NOT embedded (embedded uses AppHeader)
                if !isEmbedded {
                    // Leading: User avatar (placeholder for future features)
                    ToolbarItem(placement: .navigationBarLeading) {
                        AvatarInitialButton(
                            initial: appState.firstName?.first.map { String($0) },
                            size: 32,
                            enableHaptic: true,
                            accessibilityLabel: "Menu",
                            onTap: {
                                // Future: Open side menu or feature panel
                            }
                        )
                    }

                    // Trailing: Settings button
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            navigationPath.wrappedValue.append(SettingsRoute.main)
                        } label: {
                            Image(systemName: "person.fill")
                                .font(type.body1)
                                .fontWeight(.medium)
                                .foregroundStyle(theme.foreground)
                        }
                        .accessibilityLabel("Settings")
                    }

                    // Trailing: New Entry button
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            activeEntryRoute = .create
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(type.body1)
                                .fontWeight(.medium)
                                .foregroundStyle(theme.foreground)
                        }
                        .accessibilityLabel("New Journal Entry")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Your Entries Content

    @ViewBuilder
    private var yourEntriesContent: some View {
        YourEntriesView(
            entryViewModel: entryViewModel,
            monthGroups: allEntriesByMonth,
            // Breathing room under the floating header, matching
            // `AIChatView.topContentInset` so the two root pages agree. The
            // header reserves its own height via `safeAreaInset` above; this is
            // only the gap between it and the first month title.
            topContentPadding: 16,
            onMonthVisibilityChanged: { monthStart in
                // Sync scroll position with picker selection
                selectedDate = monthStart
                selectedMonth = Calendar.current.component(.month, from: monthStart)
                selectedYear = Calendar.current.component(.year, from: monthStart)
                visibleMonthStart = monthStart
            },
            onNavigateToEntry: { route in
                presentEntry(route)
            }
        )
    }

    /// Embedded, ContentView owns the entry sheet; standalone, we do.
    private func presentEntry(_ route: EntryRoute) {
        if isEmbedded, let onPresentEntry {
            onPresentEntry(route)
        } else {
            activeEntryRoute = route
        }
    }

    // MARK: - Header (Figma 483:1213)

    private var journalHeader: some View {
        AppHeader {
            AvatarInitialButton(
                initial: appState.firstName?.first.map { String($0) },
                size: 40,
                enableHaptic: true,
                // Kept as "Menu" deliberately: the destructive-flow UI test uses
                // `app.buttons["Menu"]` as its entry point into settings.
                accessibilityLabel: "Menu",
                onTap: { showProfileSheet = true }
            )
        } trailing: {
            HStack(spacing: 12) {
                HeaderIconButton(
                    systemName: "magnifyingglass",
                    size: 40,
                    accessibilityLabel: "Search"
                ) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showJournalSearch = true
                    }
                }

                // Top-right, facing its destination: Chat is the page to the
                // right, and a left swipe reveals it. Tap and swipe are the same
                // navigation.
                // Label is "AI chat", NOT "Chat with Memento": the composer's
                // idle button on the chat page already uses that label, and two
                // controls sharing one label is ambiguous for VoiceOver and
                // makes `app.buttons["Chat with Memento"]` resolve to whichever
                // page the pager happens to hand back first.
                HeaderIconButton(
                    systemName: "message",
                    size: 40,
                    accessibilityLabel: "AI chat",
                    accessibilityHint: "Double-tap to open the AI chat, or swipe left"
                ) {
                    onOpenChat?()
                }
            }
        }
    }

    // MARK: - Month Picker Sheet

    private var monthPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Picker("Month", selection: $selectedMonth) {
                        ForEach(availableMonthsForYear, id: \.self) { month in
                            Text(monthNames[month - 1])
                                .tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("Year", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(String(year))
                                .tag(year)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 200)
                .padding(.vertical, 20)
            }
            .navigationTitle("Select Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showMonthPicker = false
                    }
                    .foregroundStyle(theme.primary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        updateSelectedDate()
                        showMonthPicker = false
                    }
                    .foregroundStyle(theme.primary)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(350)])
        .presentationDragIndicator(.visible)
        .onAppear {
            selectedMonth = Calendar.current.component(.month, from: selectedDate)
            selectedYear = Calendar.current.component(.year, from: selectedDate)
        }
    }

    private func updateSelectedDate() {
        var components = DateComponents()
        components.year = selectedYear
        components.month = selectedMonth
        components.day = 1
        if let newDate = Calendar.current.date(from: components) {
            selectedDate = newDate
            visibleMonthStart = newDate  // Keep in sync
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
            }
            .environment(\.fabVisible, false)
        case .createWithTitle(let prefillTitle):
            AddEntryView(state: .createWithTitle(prefillTitle)) { title, text, photoAction in
                entryViewModel.createEntry(title: title, text: text, photoAction: photoAction)
                activeEntryRoute = nil
            }
            .environment(\.fabVisible, false)
        case .createWithContent(let prefillTitle, let prefillContent):
            AddEntryView(state: .createWithContent(title: prefillTitle, content: prefillContent)) { title, text, photoAction in
                entryViewModel.createEntry(title: title, text: text, photoAction: photoAction)
                activeEntryRoute = nil
            }
            .environment(\.fabVisible, false)
        case .edit(let entry):
            AddEntryView(state: .edit(entry)) { title, text, photoAction in
                var updated = entry
                updated.title = title
                updated.text = text
                entryViewModel.updateEntry(updated, photoAction: photoAction)
                activeEntryRoute = nil
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

    // MARK: - Actions

    private func createEntry() {
        navigationPath.wrappedValue.append(EntryRoute.create)
    }
}

// MARK: - Previews

#Preview("Journal • Empty") {
    @Previewable @StateObject var entryViewModel = EntryViewModel()
    @Previewable @StateObject var appState = AppStateStore()

    JournalView()
        .environmentObject(entryViewModel)
        .environmentObject(appState)
        .onAppear {
            entryViewModel.entries = []
        }
        .useTheme()
        .useTypography()
}

#Preview("Journal • With Entries") {
    @Previewable @StateObject var entryViewModel = EntryViewModel()
    @Previewable @StateObject var appState = AppStateStore()

    JournalView()
        .environmentObject(entryViewModel)
        .environmentObject(appState)
        .onAppear {
            entryViewModel.loadMockEntries()
        }
        .useTheme()
        .useTypography()
}
