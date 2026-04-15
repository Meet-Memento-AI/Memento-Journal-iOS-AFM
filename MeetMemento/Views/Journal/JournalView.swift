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
    /// Callback to open drawer menu on right swipe
    var onSwipeToOpenMenu: (() -> Void)? = nil
    /// Callback to present entry sheet when embedded (ContentView provides this)
    var onPresentEntry: ((EntryRoute) -> Void)? = nil

    @EnvironmentObject var entryViewModel: EntryViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

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

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.showAccessory) private var showAccessory
    @Environment(\.selectedTab) private var selectedTab

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

    /// Dynamic inset for floating header (includes 32px gap below header)
    private var topHeaderInset: CGFloat {
        let safeAreaTop = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
        // TopNavHeader positioned at safeAreaTop + 8 with height 44px
        // Content starts 32px below header bottom
        return safeAreaTop + 8 + 44 + 32  // = safeAreaTop + 84
    }

    public init(
        isEmbedded: Bool = false,
        externalNavigationPath: Binding<NavigationPath> = .constant(NavigationPath()),
        onSwipeToOpenMenu: (() -> Void)? = nil,
        onPresentEntry: ((EntryRoute) -> Void)? = nil
    ) {
        self.isEmbedded = isEmbedded
        self._externalNavigationPath = externalNavigationPath
        self.onSwipeToOpenMenu = onSwipeToOpenMenu
        self.onPresentEntry = onPresentEntry
    }

    public var body: some View {
        journalContent
            .onChange(of: navigationPath.wrappedValue.count) { _, count in
                // Only update if Journal tab is selected to avoid race condition
                if selectedTab?.wrappedValue == .yourEntries {
                    showAccessory?.wrappedValue = (count == 0)
                }
            }
            .onAppear {
                // Only update if Journal tab is selected to avoid race condition
                if selectedTab?.wrappedValue == .yourEntries {
                    showAccessory?.wrappedValue = (navigationPath.wrappedValue.count == 0)
                }
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
                    .navigationDestination(for: MonthInsightRoute.self) { route in
                        switch route {
                        case .detail(let monthLabel, _):
                            InsightsView()
                                .environmentObject(entryViewModel)
                                .navigationTitle(monthLabel)
                                .navigationBarTitleDisplayMode(.large)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .all)
        .simultaneousGesture(
            DragGesture(minimumDistance: 50, coordinateSpace: .local)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)
                    // Right swipe: positive horizontal, more horizontal than vertical
                    if horizontal > 80 && horizontal > vertical {
                        onSwipeToOpenMenu?()
                    }
                }
        )
        .background(theme.background.ignoresSafeArea(edges: .all))
        .toolbar {
                // Only show toolbar when NOT embedded (embedded uses TopNavHeader)
                if !isEmbedded {
                    // Leading: Hamburger menu (placeholder for future features)
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            // Future: Open side menu or feature panel
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(type.h5)
                                .foregroundStyle(theme.foreground)
                        }
                        .accessibilityLabel("Menu")
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
            topContentPadding: isEmbedded ? topHeaderInset : 0,
            onMonthVisibilityChanged: { monthStart in
                // Sync scroll position with picker selection
                selectedDate = monthStart
                selectedMonth = Calendar.current.component(.month, from: monthStart)
                selectedYear = Calendar.current.component(.year, from: monthStart)
                visibleMonthStart = monthStart
            },
            onNavigateToEntry: { route in
                if isEmbedded, let onPresentEntry = onPresentEntry {
                    // When embedded, use ContentView's sheet presentation
                    onPresentEntry(route)
                } else {
                    // Standalone mode: use our own sheet
                    activeEntryRoute = route
                }
            }
        )
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
            AddEntryView(state: .create) { title, text in
                entryViewModel.createEntry(title: title, text: text)
                activeEntryRoute = nil
            }
            .environment(\.fabVisible, false)
        case .createWithTitle(let prefillTitle):
            AddEntryView(state: .createWithTitle(prefillTitle)) { title, text in
                entryViewModel.createEntry(title: title, text: text)
                activeEntryRoute = nil
            }
            .environment(\.fabVisible, false)
        case .createWithContent(let prefillTitle, let prefillContent):
            AddEntryView(state: .createWithContent(title: prefillTitle, content: prefillContent)) { title, text in
                entryViewModel.createEntry(title: title, text: text)
                activeEntryRoute = nil
            }
            .environment(\.fabVisible, false)
        case .edit(let entry):
            AddEntryView(state: .edit(entry)) { title, text in
                var updated = entry
                updated.title = title
                updated.text = text
                entryViewModel.updateEntry(updated)
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
                .environmentObject(authViewModel)
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
    @Previewable @StateObject var authViewModel = AuthViewModel()

    JournalView()
        .environmentObject(entryViewModel)
        .environmentObject(authViewModel)
        .onAppear {
            entryViewModel.entries = []
        }
        .useTheme()
        .useTypography()
}

#Preview("Journal • With Entries") {
    @Previewable @StateObject var entryViewModel = EntryViewModel()
    @Previewable @StateObject var authViewModel = AuthViewModel()

    JournalView()
        .environmentObject(entryViewModel)
        .environmentObject(authViewModel)
        .onAppear {
            entryViewModel.loadMockEntries()
        }
        .useTheme()
        .useTypography()
}
