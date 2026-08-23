//
//  JournalSearchView.swift
//  MeetMemento
//
//  Full-screen search overlay for journal entries
//

import SwiftUI

struct JournalSearchView: View {
    @Binding var isPresented: Bool
    @Binding var navigationPath: NavigationPath

    @EnvironmentObject private var entryViewModel: EntryViewModel
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    @State private var searchQuery = ""

    // MARK: - Computed Properties

    private var searchResults: [Entry] {
        entryViewModel.searchEntries(query: searchQuery)
    }

    private var hasQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search header
            searchHeader
                .padding(.horizontal, Spacing.md)
                .padding(.top, safeAreaTop + Spacing.md)
                .padding(.bottom, Spacing.md)

            // Content
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    if !hasQuery {
                        emptyPromptView
                    } else if searchResults.isEmpty {
                        noResultsView
                    } else {
                        resultsListView
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xxxl)
            }
            .animation(.easeInOut(duration: 0.2), value: searchResults.count)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
        .ignoresSafeArea()
    }

    // MARK: - Subviews

    private var searchHeader: some View {
        SearchTextField(
            text: $searchQuery,
            placeholder: "Search journal entries",
            onCancel: dismissSearch
        )
    }

    private var emptyPromptView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
                .frame(height: 100)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light)) // icon-size: not user text
                .foregroundStyle(theme.mutedForeground.opacity(0.5))

            Text("Search your journal")
                .typographyH4()
                .foregroundStyle(theme.mutedForeground)

            Text("Find entries by title or content")
                .typographyBody2()
                .foregroundStyle(theme.mutedForeground.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search your journal. Find entries by title or content.")
    }

    private var noResultsView: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
                .frame(height: 100)

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48, weight: .light)) // icon-size: not user text
                .foregroundStyle(theme.mutedForeground.opacity(0.5))

            Text("No results found")
                .typographyH4()
                .foregroundStyle(theme.mutedForeground)

            Text("Try different keywords")
                .typographyBody2()
                .foregroundStyle(theme.mutedForeground.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results found. Try different keywords.")
    }

    private var resultsListView: some View {
        ForEach(searchResults) { entry in
            SearchResultCard(
                title: entry.displayTitle,
                excerpt: entry.excerpt,
                date: entry.createdAt
            ) {
                navigateToEntry(entry)
            }
        }
    }

    // MARK: - Actions

    private func dismissSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isPresented = false
        }
    }

    private func navigateToEntry(_ entry: Entry) {
        // Dismiss search first, then navigate
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isPresented = false
        }
        // Delay navigation slightly to allow dismiss animation
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            navigationPath.append(EntryRoute.edit(entry.id))
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
}

// MARK: - Previews

#Preview("JournalSearchView - Empty") {
    @Previewable @StateObject var viewModel = EntryViewModel.withPreviewEntries()
    @Previewable @State var isPresented = true
    @Previewable @State var navPath = NavigationPath()

    JournalSearchView(isPresented: $isPresented, navigationPath: $navPath)
        .environmentObject(viewModel)
        .useTheme()
        .useTypography()
}

#Preview("JournalSearchView - Dark") {
    @Previewable @StateObject var viewModel = EntryViewModel.withPreviewEntries()
    @Previewable @State var isPresented = true
    @Previewable @State var navPath = NavigationPath()

    JournalSearchView(isPresented: $isPresented, navigationPath: $navPath)
        .environmentObject(viewModel)
        .preferredColorScheme(.dark)
        .useTheme()
        .useTypography()
}
