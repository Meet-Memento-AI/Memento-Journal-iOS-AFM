//
//  JournalView.swift
//  MeetMemento
//
//  Main journal view with integrated navigation stack and toolbar
//

import SwiftUI

public struct JournalView: View {
    /// When true, hides internal NavigationStack (uses external from ContentView)
    var isEmbedded: Bool = false
    /// External navigation path binding when embedded
    @Binding var externalNavigationPath: NavigationPath
    /// Page to the AI chat screen. The header's chat icon and a left swipe are
    /// the same navigation, so both route through here.
    var onOpenChat: (() -> Void)? = nil

    @EnvironmentObject var entryViewModel: EntryViewModel
    @EnvironmentObject var appState: AppStateStore

    @State private var internalNavigationPath = NavigationPath()

    // Month picker state
    @State private var showMonthPicker = false
    @State private var selectedDate = Date()
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    // Scroll-based month detection
    @State private var visibleMonthStart: Date? = nil
    /// Set after the month picker confirms so the list can jump to that month.
    @State private var scrollToMonth: Date? = nil

    // Task for loading data
    @State private var loadingTask: Task<Void, Never>?
    @Namespace private var standaloneEntryZoom

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
        onOpenChat: (() -> Void)? = nil
    ) {
        self.isEmbedded = isEmbedded
        self._externalNavigationPath = externalNavigationPath
        self.onOpenChat = onOpenChat
    }

    public var body: some View {
        journalContent
            .onAppear {
                guard loadingTask == nil else { return }
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

                    #if MEMENTO_AI
                    // Warm passage embeddings off the send path so Chat never
                    // pays NLEmbedding on the first notebook question.
                    let snapshot = entryViewModel.entries
                    Task.detached(priority: .utility) {
                        EntryRetriever.warmEmbeddings(snapshot)
                        await EntryReflectionCoordinator.backfill(snapshot)
                    }
                    Task.detached(priority: .utility) {
                        await WeeklyReflectionCoordinator.generateIfNeeded(entries: snapshot)
                    }
                    Task.detached(priority: .utility) {
                        await ProfileRefreshCoordinator.refreshIfDue(entries: snapshot)
                    }
                    #endif
                }
            }
            .sheet(isPresented: $showMonthPicker) {
                monthPickerSheet
            }
    }

    // MARK: - Journal Content

    @ViewBuilder
    private var journalContent: some View {
        if isEmbedded {
            // When embedded, the pager is the host;
            // ContentView no longer wraps it in NavigationStack.
            coreContentView
        } else {
            // Standalone mode with own NavigationStack
            NavigationStack(path: navigationPath) {
                coreContentView
                    .navigationDestination(for: SettingsRoute.self) { route in
                        settingsDestination(for: route)
                    }
                    .navigationDestination(for: EntryRoute.self) { route in
                        EntryEditorDestination(route: route)
                    }
            }
            .environment(\.entryZoomNamespace, standaloneEntryZoom)
        }
    }

    @ViewBuilder
    private var coreContentView: some View {
        let showsFAB = isEmbedded
        let fabTitle = JournalFABTitle.resolved(
            hasInitiallyLoaded: entryViewModel.hasInitiallyLoaded,
            isEmpty: entryViewModel.entries.isEmpty
        )

        RootPageScaffold(
            footerBottomPadding: showsFAB ? 16 : 0,
            pageBackground: theme.background,
            header: { if isEmbedded { journalHeader } },
            footer: {
                if showsFAB {
                    HStack {
                        Spacer(minLength: 0)
                        NewEntryFAB(
                            title: fabTitle
                        ) {
                            presentEntry(.create)
                        }
                        .entryZoomSource(
                            EntryRoute.createZoomSourceID,
                            cornerRadius: NewEntryFAB.labeledCornerRadius
                        )
                    }
                    .padding(.horizontal, 16)
                }
            }
        ) {
            yourEntriesContent
        }
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
                    ToolbarItem(placement: .navigationBarLeading) {
                        AvatarInitialButton(
                            initial: appState.firstName?.first.map { String($0) },
                            enableHaptic: true,
                            accessibilityLabel: "Menu",
                            onTap: { showProfileSheet = true }
                        )
                    }

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

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            presentEntry(.create)
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(type.body1)
                                .fontWeight(.medium)
                                .foregroundStyle(theme.foreground)
                        }
                        .entryZoomSource(EntryRoute.createZoomSourceID)
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
            monthGroups: entryViewModel.entriesByMonth,
            topContentPadding: AppHeaderMetrics.contentTopPadding,
            bottomContentPadding: isEmbedded
                ? PositionedNewEntryFAB.scrollClearance
                : 20,
            onMonthVisibilityChanged: { monthStart in
                // Sync scroll position with picker selection
                selectedDate = monthStart
                selectedMonth = Calendar.current.component(.month, from: monthStart)
                selectedYear = Calendar.current.component(.year, from: monthStart)
                visibleMonthStart = monthStart
            },
            onMonthHeaderTapped: { monthStart in
                selectedDate = monthStart
                selectedMonth = Calendar.current.component(.month, from: monthStart)
                selectedYear = Calendar.current.component(.year, from: monthStart)
                visibleMonthStart = monthStart
                showMonthPicker = true
            },
            scrollToMonth: $scrollToMonth,
            onNavigateToEntry: { route in
                presentEntry(route)
            }
        )
    }

    /// Pushes the editor onto the overlay (embedded) or standalone stack.
    private func presentEntry(_ route: EntryRoute) {
        navigationPath.wrappedValue.append(route)
    }

    // MARK: - Header (Figma 483:1213)

    private var journalHeader: some View {
        AppHeader {
            AvatarInitialButton(
                initial: appState.firstName?.first.map { String($0) },
                size: AppHeaderMetrics.controlSize,
                enableHaptic: true,
                // Kept as "Menu" deliberately: the destructive-flow UI test uses
                // `app.buttons["Menu"]` as its entry point into settings.
                accessibilityLabel: "Menu",
                onTap: { showProfileSheet = true }
            )
        } trailing: {
            #if MEMENTO_AI
            JournalHeaderActionCluster(
                onSearch: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showJournalSearch = true
                    }
                },
                onChat: { onOpenChat?() }
            )
            #else
            HeaderIconButton(
                systemName: "magnifyingglass",
                accessibilityLabel: "Search"
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showJournalSearch = true
                }
            }
            #endif
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
                    .foregroundStyle(theme.foreground)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        updateSelectedDate()
                        scrollToMonth = selectedDate
                        showMonthPicker = false
                    }
                    .foregroundStyle(theme.foreground)
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
        .onChange(of: selectedYear) { _, _ in
            if !availableMonthsForYear.contains(selectedMonth),
               let first = availableMonthsForYear.first {
                selectedMonth = first
            }
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
        #if MEMENTO_AI
        case .voice:
            VoiceSettingsView()
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        #else
        case .voice:
            EmptyView()
        #endif
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
        #if MEMENTO_AI
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
        #else
        case .weekly, .patterns:
            EmptyView()
        #endif
        }
    }
}

// MARK: - Previews

#Preview("Journal • Empty") {
    @Previewable @StateObject var entryViewModel = EntryViewModel()
    @Previewable @StateObject var appState = AppStateStore()

    JournalView(isEmbedded: true)
        .environmentObject(entryViewModel)
        .environmentObject(appState)
        .onAppear {
            entryViewModel.entries = []
            entryViewModel.hasInitiallyLoaded = true
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
