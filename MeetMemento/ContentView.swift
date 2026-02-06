//
//  ContentView.swift
//  MeetMemento
//

//  Main content view that displays the journal with top navigation tabs.
//  - Journal tab: displays user's journal entries
//  - Insights tab: displays AI-generated insights and themes
//

import SwiftUI

private struct PreviewEntryViewModelKey: EnvironmentKey {
    static let defaultValue: EntryViewModel? = nil
}
private struct PreviewInitialTabKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}
private struct TabBarHiddenKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}
private struct ShowAccessoryKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}
extension EnvironmentValues {
    var previewEntryViewModel: EntryViewModel? {
        get { self[PreviewEntryViewModelKey.self] }
        set { self[PreviewEntryViewModelKey.self] = newValue }
    }
    var previewInitialTab: Int? {
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
    /// Single source of truth for tab selection; @State avoids @SceneStorage persistence causing repeated/conflicting updates when switching tabs.
    @State private var selectedTab = 0
    @State private var didSetPreviewTab = false
    @State private var showAIChat = false
    @State private var isTabBarHidden = false
    @State private var showAccessory = true

    @StateObject private var defaultEntryViewModel = EntryViewModel()
    @Environment(\.previewEntryViewModel) private var previewEntryViewModel: EntryViewModel?
    @Environment(\.previewInitialTab) private var previewInitialTab: Int?

    private var entryViewModel: EntryViewModel {
        previewEntryViewModel ?? defaultEntryViewModel
    }

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var authViewModel: AuthViewModel

    /// Tab bar tint: selection-aware for visibility. When Insights is selected, white for contrast on dark purple background; when Journal is selected, follows light/dark behavior.
    private var tabBarTint: Color {
        if selectedTab == 1 {
            return .white
        }
        return colorScheme == .dark ? .white : PrimaryScale.primary600
    }

    public init() {}

    public var body: some View {
        tabViewContent
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
            }
            .sheet(isPresented: $showAIChat) {
                NavigationStack {
                    AIChatView()
                }
            }
    }

    
    @ViewBuilder
    private var tabViewContent: some View {
        if #available(iOS 26.0, *) {
            TabView(selection: $selectedTab) {
                JournalView()
                    .tabItem {
                        Label("Journal", systemImage: "book.closed")
                    }
                    .tag(0)

                insightsTab
                    .tabItem {
                        Label("Insights", systemImage: "sparkles")
                    }
                    .tag(1)
            }
            .tint(tabBarTint)
            .tabViewStyle(.automatic)
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                talkToAIAccessory
                    .opacity(showAccessory ? 1 : 0)
            }
        } else if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab) {
                JournalView()
                    .tabItem {
                        Label("Journal", systemImage: "book.closed")
                    }
                    .tag(0)

                insightsTab
                    .tabItem {
                        Label("Insights", systemImage: "sparkles")
                    }
                    .tag(1)
            }
            .tint(tabBarTint)
            .tabViewStyle(.sidebarAdaptable)
            .overlay(alignment: .bottom) {
                talkToAIAccessoryFallback
            }
        } else {
            TabView(selection: $selectedTab) {
                JournalView()
                    .tabItem {
                        Label("Journal", systemImage: "book.closed")
                    }
                    .tag(0)

                insightsTab
                    .tabItem {
                        Label("Insights", systemImage: "sparkles")
                    }
                    .tag(1)
            }
            .tint(tabBarTint)
        }
    }

    // MARK: - Insights Tab

    private var insightsTab: some View {
        InsightsView()
    }

    // MARK: - Talk to AI Tab Bar Accessory (iOS 26+)

    @ViewBuilder
    private var talkToAIAccessory: some View {
        if #available(iOS 26.0, *) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showAIChat = true
            } label: {
                HStack(spacing: 5) {
                    // Launch logo icon
                    Image("Memento-Icon-Circle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)

                    Text("Ask your journal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selectedTab == 1 ? .white : theme.primary)
                }

            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Talk to AI Fallback (iOS 18-25)

    @ViewBuilder
    private var talkToAIAccessoryFallback: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showAIChat = true
        } label: {
            HStack(spacing: 10) {
                // Launch logo icon
                Image("LaunchLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                Text("Ask your journal")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(selectedTab == 1 ? .white : theme.foreground)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(
                        selectedTab == 1
                        ? LinearGradient(
                            colors: [theme.fabGradientStart, theme.fabGradientEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [theme.cardBackground, theme.cardBackground],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
            )
            .overlay(
                Capsule()
                    .strokeBorder(selectedTab == 1 ? Color.clear : theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, isTabBarHidden ? 20 : 100) // Minimize with tab bar
        .opacity(showAccessory ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isTabBarHidden)
        .animation(.easeInOut(duration: 0.2), value: showAccessory)
    }
}

// MARK: - Previews
#Preview("Light • iPhone 15 Pro") {
    ContentView()
        .environmentObject(AuthViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark • iPhone 15 Pro") {
    ContentView()
        .environmentObject(AuthViewModel())
        .preferredColorScheme(.dark)
}

#Preview("Insights tab with entries") {
    @Previewable @StateObject var entryViewModel = EntryViewModel.withPreviewEntries()
    ContentView()
        .environment(\.previewEntryViewModel, entryViewModel)
        .environment(\.previewInitialTab, 1)
        .environment(\.previewSkipLoadEntries, true)
        .environmentObject(AuthViewModel())
        .useTheme()
        .useTypography()
}
