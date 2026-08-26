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
    /// Bumped when a thumbnail finishes loading, purely to re-render the rows.
    /// The decoded images themselves live in `PhotoThumbnailCache` (an NSCache)
    /// so they evict under memory pressure — holding a second copy in local
    /// `@State` would pin them for the life of this view and defeat that.
    @State private var thumbnailRevision = 0

    private let scrollThreshold: CGFloat = 50

    let monthGroups: [MonthGroup]
    let topContentPadding: CGFloat  // windowTop + header row + 16pt air
    let bottomContentPadding: CGFloat  // FAB + windowBottom + 16pt + 8pt air
    let onMonthVisibilityChanged: ((Date) -> Void)
    let onNavigateToEntry: (EntryRoute) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.tabBarHidden) private var tabBarHidden

    init(
        entryViewModel: EntryViewModel,
        monthGroups: [MonthGroup],
        topContentPadding: CGFloat = 0,
        bottomContentPadding: CGFloat = 20,
        onMonthVisibilityChanged: ((Date) -> Void)? = nil,
        onNavigateToEntry: @escaping (EntryRoute) -> Void
    ) {
        self.entryViewModel = entryViewModel
        self.monthGroups = monthGroups
        self.topContentPadding = topContentPadding
        self.bottomContentPadding = bottomContentPadding
        self.onMonthVisibilityChanged = onMonthVisibilityChanged ?? { _ in }
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
        VStack(spacing: 8) {
            Spacer()

            Image(systemName: "book.closed.fill")
                .font(.system(size: 36)) // icon-size: not user text
                .foregroundStyle(theme.foreground)

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
            .entryZoomSource(EntryRoute.createZoomSourceID)
            .accessibilityIdentifier("journal.emptyCreateCTA")
            .padding(.top, 24)
            .padding(.horizontal, 32)

            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        // Month header
                        Text(monthGroup.monthLabel)
                            .font(type.h3)
                            .foregroundStyle(theme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)

                        // Entries for this month. One container so neighbouring
                        // glass cards share a sampling region (PRES-092); spacing
                        // 0 keeps them separate at rest (layout gap is 16).
                        GlassEffectContainer(spacing: 0) {
                            VStack(spacing: 16) {
                                ForEach(monthGroup.entries) { entry in
                                    JournalCard(
                                        title: entry.displayTitle,
                                        excerpt: entry.excerpt,
                                        date: entry.createdAt,
                                        photoImage: thumbnail(for: entry),
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
                                    .entryZoomSource(EntryRoute.edit(entry.id).zoomSourceID)
                                    .frame(maxWidth: .infinity) // Stretch to full width
                                    .id(entry.id) // Explicit ID for better diffing
                                    // Keyed on updatedAt as well as id: replacing an
                                    // entry's photo keeps the same id, so an id-only
                                    // task would never re-fire and the list would keep
                                    // showing the old photo until relaunch.
                                    .task(id: thumbnailToken(for: entry)) {
                                        await loadThumbnailIfNeeded(for: entry)
                                    }
                                }
                            }
                        }
                    }
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
        .background(.clear)
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
    }

    /// Changes whenever the entry's photo could have changed, so `.task(id:)`
    /// re-runs after an edit that replaced or removed the photo.
    private func thumbnailToken(for entry: Entry) -> String {
        "\(entry.id.uuidString)-\(entry.updatedAt.timeIntervalSince1970)-\(entry.hasPhoto)"
    }

    /// The decoded cover photo for a row, if it's already cached. Reading
    /// `thumbnailRevision` here is what ties the cache (which SwiftUI can't
    /// observe) to this view's render cycle.
    private func thumbnail(for entry: Entry) -> Image? {
        _ = thumbnailRevision
        guard entry.hasPhoto,
              let uiImage = PhotoThumbnailCache.shared.image(for: entry.id) else { return nil }
        return Image(uiImage: uiImage)
    }

    /// Lazily decrypts an entry's cover photo at most once per session. A
    /// strict no-op for entries without a photo (the common case) — no disk
    /// read, no decrypt.
    ///
    /// The disk read, AES decrypt, and JPEG decode run off the main thread:
    /// `.task` inherits the MainActor, and doing this inline hitched scrolling
    /// as each photo row appeared in the LazyVStack.
    private func loadThumbnailIfNeeded(for entry: Entry) async {
        guard entry.hasPhoto else { return }
        if PhotoThumbnailCache.shared.image(for: entry.id) != nil { return }

        let entryId = entry.id
        let decoded: UIImage? = await Task.detached(priority: .utility) {
            guard let encrypted = PhotoStorage.shared.loadEncrypted(entryId: entryId),
                  let data = JournalService.shared.encryptionService.decryptData(encrypted),
                  let uiImage = UIImage(data: data) else { return nil }
            return uiImage
        }.value

        guard let decoded else { return }
        PhotoThumbnailCache.shared.store(decoded, for: entryId)
        thumbnailRevision &+= 1
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
