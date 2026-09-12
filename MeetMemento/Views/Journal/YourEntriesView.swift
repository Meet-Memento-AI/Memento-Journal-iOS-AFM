//
//  YourEntriesView.swift
//  MeetMemento
//
//  "Your Entries" tab - displays journal entries grouped by month
//

import SwiftUI

struct YourEntriesView: View {
    @ObservedObject var entryViewModel: EntryViewModel
    @State private var showDeleteConfirmation: Bool = false
    @State private var entryToDelete: Entry?
    @State private var lastScrollOffset: CGFloat = 0
    @StateObject private var scrollDebouncer = ScrollDebouncer(delay: 0.25)

    private let scrollThreshold: CGFloat = 50

    /// Drives the loading → list cross-fade. Identity is coarse on purpose:
    /// inserting a new card must not replay the first-paint dissolve.
    private var listPhase: Int {
        if !entryViewModel.hasInitiallyLoaded || (entryViewModel.isLoading && entryViewModel.entries.isEmpty) {
            return 0
        }
        if entryViewModel.errorMessage != nil, entryViewModel.entries.isEmpty {
            return 1
        }
        if entryViewModel.entries.isEmpty {
            return 2
        }
        return 3
    }

    let monthGroups: [MonthGroup]
    let topContentPadding: CGFloat  // windowTop + header row + 16pt air
    let bottomContentPadding: CGFloat  // FAB + windowBottom + 16pt + 8pt air
    let onMonthVisibilityChanged: ((Date) -> Void)
    let onMonthHeaderTapped: (Date) -> Void
    @Binding var scrollToMonth: Date?
    let onNavigateToEntry: (EntryRoute) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.tabBarHidden) private var tabBarHidden
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        entryViewModel: EntryViewModel,
        monthGroups: [MonthGroup],
        topContentPadding: CGFloat = 0,
        bottomContentPadding: CGFloat = 20,
        onMonthVisibilityChanged: ((Date) -> Void)? = nil,
        onMonthHeaderTapped: ((Date) -> Void)? = nil,
        scrollToMonth: Binding<Date?> = .constant(nil),
        onNavigateToEntry: @escaping (EntryRoute) -> Void
    ) {
        self.entryViewModel = entryViewModel
        self.monthGroups = monthGroups
        self.topContentPadding = topContentPadding
        self.bottomContentPadding = bottomContentPadding
        self.onMonthVisibilityChanged = onMonthVisibilityChanged ?? { _ in }
        self.onMonthHeaderTapped = onMonthHeaderTapped ?? { _ in }
        self._scrollToMonth = scrollToMonth
        self.onNavigateToEntry = onNavigateToEntry
    }

    var body: some View {
        Group {
            if !entryViewModel.hasInitiallyLoaded || (entryViewModel.isLoading && entryViewModel.entries.isEmpty) {
                // Loading state - show until first load completes
                loadingState
                    .transition(.opacity)
            } else if let errorMessage = entryViewModel.errorMessage, entryViewModel.entries.isEmpty {
                // Error state (only show if no cached entries)
                errorState(message: errorMessage)
                    .transition(.opacity)
            } else if entryViewModel.entries.isEmpty {
                // Empty state - only after confirming no entries exist
                emptyState
                    .transition(.opacity)
            } else {
                // Content with entries grouped by month
                entriesList
                    .transition(.identity)
                    .modifier(JournalEntriesAppearDissolve())
            }
        }
        .animation(reduceMotion ? nil : Motion.journalEntriesDissolve, value: listPhase)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $showDeleteConfirmation,
            presenting: entryToDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                entryViewModel.deleteEntry(id: entry.id)
            }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Subviews

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .tint(theme.foreground)
                .scaleEffect(1.2)
            Text("Loading your entries...")
                .font(type.body1)
                .foregroundStyle(theme.mutedForeground)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)) // icon-size: not user text
                .headerGradient()
            Text("Failed to load entries")
                .font(type.h3)
                .fontWeight(.semibold)
                .foregroundStyle(theme.foreground)
            Text(message)
                .font(type.body1)
                .foregroundStyle(theme.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task {
                    await entryViewModel.loadEntries()
                }
            }
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            JournalEmptyMark()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No journal entries yet")
    }

    private var entriesList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 32, pinnedViews: []) {

                // Show error banner if there's an error (but we have cached entries)
                if let errorMessage = entryViewModel.errorMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(theme.destructive)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Couldn't Save Entry")
                                .font(type.body1)
                                .fontWeight(.semibold)
                                .foregroundStyle(theme.foreground)
                            Text(errorMessage)
                                .font(type.body1)
                                .foregroundStyle(theme.mutedForeground)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(theme.destructive.opacity(0.1))
                    .cornerRadius(8)
                }

                // Month groups - entries organized by month
                ForEach(monthGroups) { monthGroup in
                    VStack(alignment: .leading, spacing: 16) {
                        // Month header — tap opens the month picker (PRES-022).
                        Button {
                            onMonthHeaderTapped(monthGroup.monthStart)
                        } label: {
                            Text(monthGroup.monthLabel)
                                .font(type.h3)
                                .foregroundStyle(theme.foreground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Double-tap to jump to another month")

                        // Entries for this month.
                        VStack(spacing: 16) {
                                ForEach(monthGroup.entries) { entry in
                                    JournalEntryCardRow(
                                        entry: entry,
                                        onTap: {
                                            onNavigateToEntry(.edit(entry.id))
                                        },
                                        onEditTapped: {
                                            onNavigateToEntry(.edit(entry.id))
                                        },
                                        onDeleteTapped: {
                                            entryToDelete = entry
                                            showDeleteConfirmation = true
                                        }
                                    )
                                }
                        }
                    }
                    .id(Self.monthScrollID(monthGroup.monthStart))
                    .onAppear { onMonthVisibilityChanged(monthGroup.monthStart) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, topContentPadding)
            .padding(.bottom, bottomContentPadding)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("scroll")).minY
                        )
                }
            )
        }
        .coordinateSpace(name: "scroll")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(theme.background)
        // The system scroll-edge material paints an opaque (usually white)
        // band into the top and bottom safe areas. Hide it so those regions
        // stay transparent and the page fill / glass can show through.
        .scrollEdgeEffectHidden(true, for: .top)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            // Only apply tracking on iOS 18, not iOS 26+
            if #available(iOS 26.0, *) {
                // Native behavior - do nothing
            } else if let binding = tabBarHidden {
                scrollDebouncer.debounce {
                    self.updateTabBarVisibility(scrollOffset: value, binding: binding)
                }
            }
        }
        .onChange(of: scrollToMonth) { _, date in
            guard let date else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(Self.monthScrollID(date), anchor: .top)
            }
            scrollToMonth = nil
        }
        }
    }

    /// Year-month key so picker `DateComponents(day: 1)` matches
    /// `dateInterval(of: .month).start` even when the hour/timezone differ.
    private static func monthScrollID(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        return "month-\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    private func updateTabBarVisibility(scrollOffset: CGFloat, binding: Binding<Bool>) {
        let delta = scrollOffset - lastScrollOffset

        // Scrolling down (negative delta) - hide tab bar
        if delta < -scrollThreshold && !binding.wrappedValue {
            binding.wrappedValue = true
        }
        // Scrolling up (positive delta) - show tab bar
        else if delta > scrollThreshold && binding.wrappedValue {
            binding.wrappedValue = false
        }

        lastScrollOffset = scrollOffset
    }

}

/// One journal row. Owns its own cache-revision so a finished decode
/// re-renders this card only — not the whole month list. The UIImage
/// itself stays in `PhotoThumbnailCache`.
private struct JournalEntryCardRow: View {
    let entry: Entry
    var onTap: () -> Void
    var onEditTapped: () -> Void
    var onDeleteTapped: () -> Void

    @Environment(\.theme) private var theme
    @State private var photoRevision = 0

    var body: some View {
        JournalCard(
            title: entry.displayTitle,
            excerpt: entry.excerpt,
            date: entry.createdAt,
            photoImage: thumbnail,
            photoSample: backdropSample,
            hasPhoto: entry.hasPhoto,
            onTap: onTap,
            onEditTapped: onEditTapped,
            onDeleteTapped: onDeleteTapped
        )
        .entryZoomSource(
            EntryRoute.edit(entry.id).zoomSourceID,
            cornerRadius: theme.radius.xxl
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .id(entry.id)
        .task(id: thumbnailToken) {
            await loadThumbnailIfNeeded()
        }
    }

    private var thumbnailToken: String {
        "\(entry.id.uuidString)-\(entry.updatedAt.timeIntervalSince1970)-\(entry.hasPhoto)"
    }

    private var thumbnail: Image? {
        _ = photoRevision
        guard entry.hasPhoto,
              let uiImage = PhotoThumbnailCache.shared.image(for: entry.id) else { return nil }
        return Image(uiImage: uiImage)
    }

    private var backdropSample: JournalBackdropSample? {
        _ = photoRevision
        guard entry.hasPhoto else { return nil }
        return PhotoThumbnailCache.shared.sample(for: entry.id)
    }

    private func loadThumbnailIfNeeded() async {
        guard entry.hasPhoto else { return }
        if PhotoThumbnailCache.shared.image(for: entry.id) != nil {
            photoRevision &+= 1
            return
        }
        await PhotoThumbnailCache.shared.loadIfNeeded(entryId: entry.id)
        guard PhotoThumbnailCache.shared.image(for: entry.id) != nil else { return }
        photoRevision &+= 1
    }
}

// MARK: - First-paint dissolve

/// Opacity plus a blur envelope that peaks mid-mix and is 0 at rest — not a
/// hard 0→1 fade. Applied to the list as a whole so LazyVStack rows do not
/// re-dissolve as they scroll into view. Reduce Motion skips blur (PRES-094).
private struct JournalEntriesAppearDissolve: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    func body(content: Content) -> some View {
        content
            .modifier(JournalDissolvePlate(progress: progress, blurs: !reduceMotion))
            .onAppear {
                guard progress < 1 else { return }
                if reduceMotion {
                    progress = 1
                } else {
                    withAnimation(Motion.journalEntriesDissolve) {
                        progress = 1
                    }
                }
            }
    }
}

private struct JournalDissolvePlate: ViewModifier, Animatable {
    var progress: Double
    var blurs: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        if blurs {
            content
                .blur(radius: blurRadius)
                .opacity(progress)
        } else {
            content
                .opacity(progress)
        }
    }

    private var blurRadius: CGFloat {
        CGFloat(4 * progress * (1 - progress)) * Motion.journalEntriesDissolveBlur
    }
}

// MARK: - Previews

#Preview("Empty State") {
    @Previewable @StateObject var viewModel = EntryViewModel()

    YourEntriesView(
        entryViewModel: viewModel,
        monthGroups: [],
        onNavigateToEntry: { _ in }
    )
    .onAppear {
        viewModel.entries = []
        viewModel.hasInitiallyLoaded = true
    }
    .useTheme()
    .useTypography()
}

#Preview("With Entries") {
    @Previewable @StateObject var viewModel = EntryViewModel()

    YourEntriesView(
        entryViewModel: viewModel,
        monthGroups: viewModel.entriesByMonth,
        onNavigateToEntry: { _ in }
    )
    .onAppear {
        viewModel.loadMockEntries()
    }
    .useTheme()
    .useTypography()
}
