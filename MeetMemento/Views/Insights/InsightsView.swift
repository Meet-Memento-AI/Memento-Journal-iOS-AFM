//
//  InsightsView.swift
//  MeetMemento
//
//  Insights view with Liquid Glass toolbar and navigation
//

// MARK: - DEPRECATED
// This view is no longer used in the main navigation.
// The "Insights" tab now shows AIChatView instead.
// File kept for reference and potential future use.

import SwiftUI

public struct InsightsView: View {
    @EnvironmentObject var entryViewModel: EntryViewModel
    @EnvironmentObject var appState: AppStateStore
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @StateObject private var chatViewModel = ChatViewModel()

    @State private var navigationPath = NavigationPath()

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.selectedTab) private var selectedTab
    @Environment(\.showAccessory) private var showAccessory
    @Environment(\.tabBarHidden) private var tabBarHidden
    @Environment(\.previewInsightContent) private var previewInsightContent
    @Environment(\.previewInsightEntriesCount) private var previewInsightEntriesCount
    @Environment(\.previewForceLoadingState) private var previewForceLoadingState
    @Environment(\.previewSkipLoadEntries) private var previewSkipLoadEntries

    // Month picker state
    @State private var showMonthPicker = false
    @State private var selectedDate = Date()
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())

    // Available years (2026 onwards)
    private var availableYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let startYear = max(2026, currentYear)
        return Array(startYear...(startYear + 10))
    }

    // Month names
    private let monthNames = Calendar.current.monthSymbols

    // Current month for calendar button
    private var currentMonthDisplay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM, yyyy"
        return formatter.string(from: selectedDate)
    }

    // Animation state
    @State private var loadingStep = 0
    @State private var isShowingHeadlineSkeleton = true
    @State private var displayedHeadline = ""
    @State private var hasAnimated = false
    @State private var animationTask: Task<Void, Never>?

    // Scroll tracking state
    @State private var lastScrollOffset: CGFloat = 0
    @StateObject private var scrollDebouncer = ScrollDebouncer(delay: 0.1)

    private let scrollThreshold: CGFloat = 50

    // Data state - fetched from API or restored from cache
    @State private var insight: InsightContent?
    @State private var entriesCount: Int = 0
    @State private var isLoadingInsight = false
    @State private var insightError: String?

    // Entry sheet state
    @State private var activeEntryRoute: EntryRoute?

    // Cache: one insight per month (key: "yyyy-MM"). API is only called on pull-to-refresh or date change.
    @State private var insightCache: [String: CachedInsight] = [:]

    // Cache size limit to prevent unbounded memory growth
    private let maxCacheSize = 12

    // Fallback content for when API hasn't loaded yet
    private let fallbackHeadline = "Analyzing your journal entries..."
    private let fallbackObservation = "Your insights will appear here once we've analyzed your recent entries."
    private let totalSteps = 5 // Tag, Observation, Sentiments, Keywords, Questions

    // Computed properties for display content
    private var displayHeadline: String {
        insight?.headline ?? fallbackHeadline
    }

    private var displayObservation: String {
        insight?.observation ?? fallbackObservation
    }

    private var displayObservationExtended: String? {
        insight?.observationExtended
    }

    private var displaySentiments: [InsightSentiment] {
        insight?.sentiment ?? []
    }

    private var displayKeywords: [String] {
        insight?.keywords ?? []
    }

    private var displayQuestions: [String] {
        // Generate follow-up questions based on keywords or use defaults
        insight?.questions ?? [
            "What patterns do you notice in your recent entries?",
            "How have your feelings evolved over time?",
            "What would you like to explore further?"
        ]
    }

    public init() {}

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            contentView
                .background(theme.insightsBackground.ignoresSafeArea())
                .toolbar {
                    // Leading: Calendar/Month button (white on purple background)
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showMonthPicker = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                    .font(type.h5)
                                Text(currentMonthDisplay)
                                    .font(type.body2)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(theme.overlayText)
                        }
                        .accessibilityLabel("Select Month - \(currentMonthDisplay)")
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
                                .foregroundStyle(theme.overlayText)
                        }
                        .accessibilityLabel("New Journal Entry")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
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
                .navigationDestination(for: AIChatRoute.self) { route in
                    switch route {
                    case .main:
                        AIChatView(viewModel: chatViewModel)
                            .toolbar(.hidden, for: .tabBar)
                            .environment(\.fabVisible, false)
                    }
                }
                .sheet(isPresented: $showMonthPicker) {
                    monthPickerSheet
                }
        }
        .onChange(of: navigationPath.count) { _, count in
            // Only update if Insights tab is selected to avoid race condition
            if selectedTab?.wrappedValue == .digDeeper {
                showAccessory?.wrappedValue = (count == 0)
            }
        }
        .onAppear {
            // Only update if Insights tab is selected to avoid race condition
            if selectedTab?.wrappedValue == .digDeeper {
                showAccessory?.wrappedValue = (navigationPath.count == 0)
            }
            // Preview-only: force loading state (skeleton, no content).
            if previewForceLoadingState {
                isLoadingInsight = true
                isShowingHeadlineSkeleton = true
                loadingStep = 0
                displayedHeadline = ""
                return
            }
            // Preview-only: show loaded state with sample content.
            if let content = previewInsightContent {
                insight = content
                entriesCount = max(1, previewInsightEntriesCount)
                showInstantContent()
                return
            }
            // Sync restore from cache so first frame when switching to Insights already shows correct content (no flash).
            syncDisplayFromCache()
            if insight != nil {
                showInstantContent()
            }
        }
        .task(id: entryViewModel.entries.count) {
            // Async only: entries load (skip in preview so mock entries aren't overwritten) and first-appear insight load.
            if !previewSkipLoadEntries {
                await entryViewModel.loadEntriesIfNeeded()
            }

            let key = currentMonthKey
            let hasCached = insightCache[key] != nil
            let entries = entriesForSelectedMonth
            if !hasCached, !entries.isEmpty {
                await loadForCurrentMonth()
            }
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            // Clear cache on memory warning to free up memory
            insightCache.removeAll()
        }
    }

    /// Cache key for the selected month (yyyy-MM).
    private var currentMonthKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: selectedDate)
    }

    /// Entries that fall within the selected month.
    private var entriesForSelectedMonth: [Entry] {
        let calendar = Calendar.current
        return entryViewModel.entries.filter { entry in
            calendar.isDate(entry.createdAt, equalTo: selectedDate, toGranularity: .month)
        }
    }

    /// Restore displayed insight and count from cache for current month; does not call API.
    private func syncDisplayFromCache() {
        if let cached = insightCache[currentMonthKey] {
            insight = cached.content
            entriesCount = cached.entriesCount
            insightError = nil
        }
    }

    /// Load insight for the current month: use cache (show instantly, no animation) or run one sample load (animation once).
    private func loadForCurrentMonth() async {
        if let cached = insightCache[currentMonthKey] {
            await MainActor.run {
                insight = cached.content
                entriesCount = cached.entriesCount
                insightError = nil
                showInstantContent() // Cached content: fixed in place, no animation
            }
            return
        }
        await fetchInsights() // New load: sample "API" then animation runs once
    }

    // MARK: - Content View

    private var contentView: some View {
        Group {
            if entryViewModel.entries.isEmpty {
                emptyState(
                    icon: "sparkles",
                    title: "No insights yet",
                    message: "Your insights will appear here after journaling."
                )
            } else if !networkMonitor.isConnected && insight == nil {
                // spec-007 R3: generating an insight needs a connection, and
                // there's no cached one to fall back to — say so rather than
                // spinning forever or failing silently.
                emptyState(
                    icon: "wifi.slash",
                    title: "You're offline",
                    message: "Insights need a connection. Reconnect to see what's on your mind."
                )
            } else {
                placeholderContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Month Picker Sheet

    private var monthPickerSheet: some View {
        InsightMonthPickerSheet(
            selectedMonth: $selectedMonth,
            selectedYear: $selectedYear,
            isPresented: $showMonthPicker,
            availableYears: availableYears,
            onDone: updateSelectedDate
        )
        .onAppear {
            // Initialize pickers with current selected date
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
            // Load insight for the new month (from cache or API)
            Task {
                await loadForCurrentMonth()
            }
        }
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func entrySheet(for route: EntryRoute) -> some View {
        switch route {
        case .create:
            AddEntryView(state: .create) { title, text in
                entryViewModel.createEntry(title: title, text: text)
                selectedTab?.wrappedValue = .yourEntries
                activeEntryRoute = nil
            }
            .environment(\.fabVisible, false)
        case .createWithTitle(let prefillTitle):
            AddEntryView(state: .createWithTitle(prefillTitle)) { title, text in
                entryViewModel.createEntry(title: title, text: text)
                selectedTab?.wrappedValue = .yourEntries
                activeEntryRoute = nil
            }
            .environment(\.fabVisible, false)
        case .createWithContent(let prefillTitle, let prefillContent):
            AddEntryView(state: .createWithContent(title: prefillTitle, content: prefillContent)) { title, text in
                entryViewModel.createEntry(title: title, text: text)
                selectedTab?.wrappedValue = .yourEntries
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
        case .about:
            AboutSettingsView()
                .toolbar(.hidden, for: .tabBar)
                .environment(\.fabVisible, false)
        }
    }

    // MARK: - Actions

    private func createEntry() {
        activeEntryRoute = .create
    }

    // MARK: - Data Fetching (sample only; no edge function)

    /// Loads sample insight for the current month and caches it. No loading states; content appears immediately.
    private func fetchInsights() async {
        await MainActor.run { insightError = nil }
        let key = await MainActor.run { currentMonthKey }
        let entries = await MainActor.run { entriesForSelectedMonth }

        guard !entries.isEmpty else {
            await MainActor.run {
                insight = nil
                entriesCount = 0
                insightError = nil
            }
            return
        }

        let content = InsightContent.sample
        let count = entries.count

        guard !Task.isCancelled else { return }

        await MainActor.run {
            // Cache eviction: remove oldest entry if cache is full
            if insightCache.count >= maxCacheSize {
                if let oldestKey = insightCache.keys.sorted().first {
                    insightCache.removeValue(forKey: oldestKey)
                }
            }

            insightCache[key] = CachedInsight(content: content, entriesCount: count)
            if currentMonthKey == key {
                insight = content
                entriesCount = count
                showInstantContent()
            }
        }
    }

    private func showInstantContent() {
        isShowingHeadlineSkeleton = false
        displayedHeadline = displayHeadline
        loadingStep = totalSteps
        hasAnimated = true
    }

    private func startLoadingSequence() {
        animationTask?.cancel()
        isShowingHeadlineSkeleton = true
        displayedHeadline = ""
        loadingStep = 0

        animationTask = Task { @MainActor in
            // Phase 1: Show skeleton for 1.2s
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }

            isShowingHeadlineSkeleton = false

            // Phase 2: Typewrite headline
            let headlineText = displayHeadline
            for character in headlineText {
                guard !Task.isCancelled else { return }
                displayedHeadline.append(character)
                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms per character
            }

            // Phase 3: Staggered reveal of remaining sections
            for step in 1...totalSteps {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 600_000_000) // 600ms between steps
                loadingStep = step
            }

            guard !Task.isCancelled else { return }
            hasAnimated = true
        }
    }

    /// Content when entries exist - displays AI-generated insights
    private var placeholderContent: some View {
        InsightsContentView(
            insight: insight,
            entriesCount: entriesCount,
            totalEntries: entryViewModel.entries.count,
            currentMonthDisplay: currentMonthDisplay,
            entriesForSelectedMonth: entriesForSelectedMonth,
            isLoadingInsight: isLoadingInsight,
            isShowingHeadlineSkeleton: isShowingHeadlineSkeleton,
            displayedHeadline: displayedHeadline,
            loadingStep: loadingStep,
            insightError: insightError,
            lastScrollOffset: $lastScrollOffset,
            scrollDebouncer: scrollDebouncer,
            scrollThreshold: scrollThreshold,
            onNavigateToEntry: { route in
                navigationPath.append(route)
            },
            onRefresh: {
                await entryViewModel.refreshEntries()
                await loadForCurrentMonth()
            }
        )
    }

    private func resetAnimation() {
        animationTask?.cancel()
        animationTask = nil
        loadingStep = 0
        isShowingHeadlineSkeleton = true
        displayedHeadline = ""
        hasAnimated = false
        insight = nil
        insightError = nil
    }

    /// Reusable empty state view
    private func emptyState(icon: String, title: String, message: String) -> some View {
        InsightsEmptyState(icon: icon, title: title, message: message)
    }
}

// MARK: - Cache Model
private struct CachedInsight {
    let content: InsightContent
    let entriesCount: Int
}


// MARK: - Preview Environment Keys
private struct PreviewInsightContentKey: EnvironmentKey {
    static let defaultValue: InsightContent? = nil
}
private struct PreviewInsightEntriesCountKey: EnvironmentKey {
    static let defaultValue: Int = 0
}
private struct PreviewForceLoadingStateKey: EnvironmentKey {
    static let defaultValue: Bool = false
}
private struct PreviewSkipLoadEntriesKey: EnvironmentKey {
    static let defaultValue: Bool = false
}
extension EnvironmentValues {
    var previewInsightContent: InsightContent? {
        get { self[PreviewInsightContentKey.self] }
        set { self[PreviewInsightContentKey.self] = newValue }
    }
    var previewInsightEntriesCount: Int {
        get { self[PreviewInsightEntriesCountKey.self] }
        set { self[PreviewInsightEntriesCountKey.self] = newValue }
    }
    var previewForceLoadingState: Bool {
        get { self[PreviewForceLoadingStateKey.self] }
        set { self[PreviewForceLoadingStateKey.self] = newValue }
    }
    var previewSkipLoadEntries: Bool {
        get { self[PreviewSkipLoadEntriesKey.self] }
        set { self[PreviewSkipLoadEntriesKey.self] = newValue }
    }
}

// MARK: - Previews
#Preview("Empty State") {
    @Previewable @StateObject var entryViewModel = EntryViewModel()
    @Previewable @StateObject var appState = AppStateStore()

    InsightsView()
        .environmentObject(entryViewModel)
        .environmentObject(appState)
        .environmentObject(NetworkMonitor.shared)
        .useTheme()
        .useTypography()
}

#Preview("Loading State") {
    @Previewable @StateObject var entryViewModel = EntryViewModel()
    @Previewable @StateObject var appState = AppStateStore()

    InsightsView()
        .environmentObject(entryViewModel)
        .environmentObject(appState)
        .environmentObject(NetworkMonitor.shared)
        .environment(\.previewForceLoadingState, true)
        .onAppear {
            entryViewModel.loadMockEntries()
        }
        .useTheme()
        .useTypography()
}

#Preview("With Entries") {
    @Previewable @StateObject var entryViewModel = EntryViewModel()
    @Previewable @StateObject var appState = AppStateStore()
    @Previewable @State var hasEntries = false

    Group {
        if hasEntries {
            InsightsView()
                .environmentObject(entryViewModel)
                .environmentObject(appState)
                .environmentObject(NetworkMonitor.shared)
                .environment(\.previewSkipLoadEntries, true)
                .useTheme()
                .useTypography()
        } else {
            Color(red: 0.21, green: 0.08, blue: 0.38)
                .ignoresSafeArea()
                .onAppear {
                    entryViewModel.loadMockEntries()
                    hasEntries = true
                }
        }
    }
}
