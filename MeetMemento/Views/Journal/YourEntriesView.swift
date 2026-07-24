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

    let monthGroups: [MonthGroup]
    let topContentPadding: CGFloat  // Padding for floating header clearance
    let onMonthVisibilityChanged: ((Date) -> Void)?
    let onNavigateToEntry: (EntryRoute) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.tabBarHidden) private var tabBarHidden

    init(
        entryViewModel: EntryViewModel,
        monthGroups: [MonthGroup],
        topContentPadding: CGFloat = 0,
        onMonthVisibilityChanged: ((Date) -> Void)? = nil,
        onNavigateToEntry: @escaping (EntryRoute) -> Void
    ) {
        self.entryViewModel = entryViewModel
        self.monthGroups = monthGroups
        self.topContentPadding = topContentPadding
        self.onMonthVisibilityChanged = onMonthVisibilityChanged
        self.onNavigateToEntry = onNavigateToEntry
    }

    var body: some View {
        Group {
            if !entryViewModel.hasInitiallyLoaded || (entryViewModel.isLoading && entryViewModel.entries.isEmpty) {
                // Loading state - show until first load completes
                loadingState
            } else if let errorMessage = entryViewModel.errorMessage, entryViewModel.entries.isEmpty {
                // Error state (only show if no cached entries)
                errorState(message: errorMessage)
            } else if entryViewModel.entries.isEmpty {
                // Empty state - only after confirming no entries exist
                emptyState
            } else {
                // Content with entries grouped by month
                entriesList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
        .ignoresSafeArea()
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
                .tint(theme.primary)
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
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()

            Image(systemName: "book.closed.fill")
                .font(.system(size: 36)) // icon-size: not user text
                .foregroundStyle(theme.primary)

            Text("No journal entries yet")
                .font(type.h3)
                .foregroundStyle(theme.foreground)
                .padding(.top, 16)

            Text("Start writing your first entry to see it here.")
                .font(type.body1)
                .foregroundStyle(theme.mutedForeground)

            PrimaryButton(
                title: "Create your first entry",
                systemImage: "square.and.pencil"
            ) {
                onNavigateToEntry(.create)
            }
            .padding(.top, 24)
            .padding(.horizontal, 32)

            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
    }

    private var entriesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 32, pinnedViews: []) {

                // Show error banner if there's an error (but we have cached entries)
                if let errorMessage = entryViewModel.errorMessage {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(theme.destructive)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sync Error")
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
                        // Month header
                        Text(monthGroup.monthLabel)
                            .font(type.h3)
                            .foregroundStyle(theme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)

                        // Entries for this month
                        VStack(spacing: 16) {
                            ForEach(monthGroup.entries) { entry in
                                JournalCard(
                                    title: entry.displayTitle,
                                    excerpt: entry.excerpt,
                                    date: entry.createdAt,
                                    isPendingSync: entry.syncStatus == .pending,
                                    onTap: {
                                        onNavigateToEntry(.edit(entry))
                                    },
                                    onEditTapped: {
                                        onNavigateToEntry(.edit(entry))
                                    },
                                    onDeleteTapped: {
                                        entryToDelete = entry
                                        showDeleteConfirmation = true
                                    }
                                )
                                .frame(maxWidth: .infinity) // Stretch to full width
                                .id(entry.id) // Explicit ID for better diffing
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, topContentPadding) // Header clearance (includes 32px gap)
            .padding(.bottom, 20) // Bottom padding for scrolling
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
        .scrollContentBackground(.hidden)
        .background(theme.background)
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
