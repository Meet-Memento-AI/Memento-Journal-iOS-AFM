//
//  TopTabNav.swift
//  MeetMemento
//
//  A fully functional top tab navigation component with:
//  - Pill-based tab switching via tap
//  - Swipe left/right gesture support
//  - Smooth animated transitions
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - TopNavVariant
public enum TopNavVariant {
    case tabs
    case single
    case singleSelected
}

// MARK: - JournalTopTab
public enum JournalTopTab: String, CaseIterable, Identifiable, Hashable {
    case yourEntries
    case digDeeper

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .yourEntries: return "Journal"
        case .digDeeper:   return "Insights"
        }
    }

    /// Get the next tab (for swipe navigation)
    public var next: JournalTopTab? {
        switch self {
        case .yourEntries: return .digDeeper
        case .digDeeper: return nil
        }
    }

    /// Get the previous tab (for swipe navigation)
    public var previous: JournalTopTab? {
        switch self {
        case .yourEntries: return nil
        case .digDeeper: return .yourEntries
        }
    }
}

// MARK: - Haptic Helper
private func triggerHaptic() {
    #if canImport(UIKit)
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    #endif
}

// MARK: - TopNav (Pills Only)
/// The pill-based tab selector component
public struct TopNav: View {
    public let variant: TopNavVariant
    @Binding public var selection: JournalTopTab

    private let navHeight: CGFloat = 44
    private let labelSpacing: CGFloat = 0
    private let hitPadding: CGFloat = 2

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Namespace private var tabAnimation

    public init(variant: TopNavVariant, selection: Binding<JournalTopTab>) {
        self.variant = variant
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: labelSpacing) {
            switch variant {
            case .tabs:
                tabsContent
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Top Navigation Tabs")

            case .single:
                Text("Your Insights")
                    .font(type.body1Bold)
                    .foregroundStyle(theme.primary)
                    .padding(.horizontal, hitPadding)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(.isHeader)

            case .singleSelected:
                Text("Your Insights")
                    .font(type.body1Bold)
                    .foregroundStyle(theme.primary)
                    .padding(.horizontal, hitPadding)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits([.isHeader, .isSelected])
            }
        }
        .frame(height: navHeight, alignment: .center)
        .background(.clear)
        .animation(.spring(response: 0.32, dampingFraction: 0.85, blendDuration: 0.12), value: selection)
    }

    // MARK: - Tabs Content
    private var tabsContent: some View {
        HStack(spacing: labelSpacing) {
            tabLabel(.yourEntries)
            tabLabel(.digDeeper)
        }
    }

    @ViewBuilder
    private func tabLabel(_ tab: JournalTopTab) -> some View {
        let isSelected = (tab == selection)

        Button {
            guard !isSelected else { return }
            triggerHaptic()
            selection = tab
        } label: {
            Text(tab.title)
                .font(type.body1Bold)
                .foregroundStyle(
                    isSelected
                        ? theme.primary              // Purple text when selected
                        : theme.mutedForeground      // Gray text when not selected
                )
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(
                    ZStack {
                        if isSelected {
                            pillBackground
                                .matchedGeometryEffect(id: "tabPill", in: tabAnimation)
                        }
                    }
                )
                .contentShape(Rectangle())
                .accessibilityAddTraits(isSelected ? [.isHeader, .isSelected] : [.isHeader])
        }
        .buttonStyle(.plain)
        .zIndex(isSelected ? 1 : 0)
    }

    // MARK: - Pill Background
    // Liquid Glass removed — flat #fafafa surface. The selected-tab pill still
    // slides between tabs via `matchedGeometryEffect` (PRES-004); only the fill
    // changed.
    @ViewBuilder
    private var pillBackground: some View {
        Capsule()
            .fill(Color(hex: "#FAFAFA"))
    }
}

// MARK: - TopTabNavContainer
/// A container view that combines TopNav pills with swipeable content pages.
///
/// Features an iOS 26-style floating pill navigation that hovers over full-height content.
/// Both pill taps and swipe gestures are synchronized.
///
/// Usage:
/// ```swift
/// @State private var selectedTab: JournalTopTab = .yourEntries
///
/// TopTabNavContainer(selection: $selectedTab) { tab in
///     switch tab {
///     case .yourEntries:
///         JournalEntriesView()
///     case .digDeeper:
///         InsightsView()
///     }
/// }
/// ```
public struct TopTabNavContainer<Content: View>: View {
    @Binding public var selection: JournalTopTab
    @Binding public var swipeProgress: CGFloat
    public let content: (JournalTopTab) -> Content

    /// Optional: Hide the top navigation pills (useful when embedding in custom layouts)
    public var showTopNav: Bool

    @Environment(\.theme) private var theme

    public init(
        selection: Binding<JournalTopTab>,
        swipeProgress: Binding<CGFloat> = .constant(0),
        showTopNav: Bool = true,
        @ViewBuilder content: @escaping (JournalTopTab) -> Content
    ) {
        self._selection = selection
        self._swipeProgress = swipeProgress
        self.showTopNav = showTopNav
        self.content = content
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Full-height swipeable content area - extends to screen edges
                SwipeableTabView(selection: $selection, swipeProgress: $swipeProgress, content: content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .all)

                // Floating pill navigation overlay - respects safe area for positioning
                if showTopNav {
                    floatingPillsOverlay(safeAreaTop: geometry.safeAreaInsets.top)
                }
            }
            .ignoresSafeArea(edges: .all)
        }
        .ignoresSafeArea(edges: .all)
    }

    // MARK: - Floating Pills Overlay
    private func floatingPillsOverlay(safeAreaTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            TopNav(variant: .tabs, selection: $selection)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                
                .padding(.top, safeAreaTop + 48)

            Spacer()
        }
    }
}

// MARK: - Swipe Progress Preference Key
private struct SwipeProgressPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - SwipeableTabView
/// A swipeable tab view that syncs with the selection binding.
/// Can be used standalone when you want custom navigation UI.
/// Optionally tracks swipe progress for interactive animations.
public struct SwipeableTabView<Content: View>: View {
    @Binding public var selection: JournalTopTab
    @Binding public var swipeProgress: CGFloat
    public let content: (JournalTopTab) -> Content

    @Environment(\.theme) private var theme

    public init(
        selection: Binding<JournalTopTab>,
        swipeProgress: Binding<CGFloat> = .constant(0),
        @ViewBuilder content: @escaping (JournalTopTab) -> Content
    ) {
        self._selection = selection
        self._swipeProgress = swipeProgress
        self.content = content
    }

    public var body: some View {
        GeometryReader { outerGeometry in
            let screenWidth = outerGeometry.size.width

            TabView(selection: $selection) {
                ForEach(JournalTopTab.allCases) { tab in
                    content(tab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .ignoresSafeArea(edges: .all)
                        .tag(tab)
                        .background(
                            // Track position of the first tab to calculate swipe progress
                            GeometryReader { innerGeometry in
                                if tab == .yourEntries {
                                    Color.clear
                                        .preference(
                                            key: SwipeProgressPreferenceKey.self,
                                            value: calculateProgress(
                                                offset: innerGeometry.frame(in: .global).minX,
                                                screenWidth: screenWidth
                                            )
                                        )
                                }
                            }
                        )
                }
            }
            .background(theme.background)
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .ignoresSafeArea()
            .onPreferenceChange(SwipeProgressPreferenceKey.self) { progress in
                swipeProgress = progress
            }
            .onChange(of: selection) { _, _ in
                triggerHaptic()
            }
        }
        .background(theme.background.ignoresSafeArea())
        .ignoresSafeArea(edges: .all)
    }

    /// Calculate swipe progress from 0 (Journal) to 1 (Insights)
    private func calculateProgress(offset: CGFloat, screenWidth: CGFloat) -> CGFloat {
        guard screenWidth > 0 else { return 0 }
        // When Journal is fully visible, offset ≈ 0, progress = 0
        // When Insights is fully visible, offset ≈ -screenWidth, progress = 1
        let progress = -offset / screenWidth
        return min(max(progress, 0), 1)
    }
}

// MARK: - SwipeGestureModifier
/// A view modifier that adds swipe gesture support to any view.
/// Use this when you need swipe navigation but can't use TabView.
public struct SwipeGestureModifier: ViewModifier {
    @Binding var selection: JournalTopTab
    var minimumDistance: CGFloat = 50

    @State private var dragOffset: CGFloat = 0

    public func body(content: Content) -> some View {
        content
            .offset(x: dragOffset)
            .gesture(
                DragGesture(minimumDistance: minimumDistance)
                    .onChanged { value in
                        // Only allow horizontal drag in the direction of available tabs
                        let canGoLeft = selection.previous != nil
                        let canGoRight = selection.next != nil

                        if value.translation.width > 0 && canGoLeft {
                            dragOffset = min(value.translation.width * 0.3, 30)
                        } else if value.translation.width < 0 && canGoRight {
                            dragOffset = max(value.translation.width * 0.3, -30)
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0

                            let threshold: CGFloat = 50

                            if value.translation.width > threshold, let prev = selection.previous {
                                triggerHaptic()
                                selection = prev
                            } else if value.translation.width < -threshold, let next = selection.next {
                                triggerHaptic()
                                selection = next
                            }
                        }
                    }
            )
    }
}

public extension View {
    /// Adds swipe gesture navigation to switch between tabs.
    /// Use when you can't use TabView but want swipe support.
    func swipeToSwitchTab(_ selection: Binding<JournalTopTab>) -> some View {
        modifier(SwipeGestureModifier(selection: selection))
    }
}

// MARK: - Previews

#Preview("Pills Only") {
    TopNav(variant: .tabs, selection: .constant(.yourEntries))
        .environment(\.theme, Theme.light)
        .environment(\.typography, Typography())
}

#Preview("Interactive Pills") {
    TopNavPreviewInteractive()
        .padding()
}

#Preview("Full Swipeable Container") {
    TopTabNavContainerPreview()
}

// MARK: - Preview Helpers

private struct TopNavPreviewInteractive: View {
    @State private var selection: JournalTopTab = .yourEntries

    var body: some View {
        VStack(spacing: 12) {
            TopNav(variant: .tabs, selection: $selection)
                .environment(\.theme, Theme.light)
                .environment(\.typography, Typography())
                .frame(width: 320)

            Text("Selected: \(selection.title)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 1)
    }
}

private struct TopTabNavContainerPreview: View {
    @State private var selection: JournalTopTab = .yourEntries

    var body: some View {
        TopTabNavContainer(selection: $selection) { tab in
            GeometryReader { geometry in
                tabContent(for: tab, geometry: geometry)
            }
        }
        .environment(\.theme, Theme.light)
        .environment(\.typography, Typography())
    }

    @ViewBuilder
    private func tabContent(for tab: JournalTopTab, geometry: GeometryProxy) -> some View {
        let topPadding = geometry.safeAreaInsets.top + 72

        switch tab {
        case .yourEntries:
            ScrollView {
                VStack(spacing: 16) {
                    Color.clear.frame(height: topPadding)

                    Text("Swipe left/right or tap the pills above")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(0..<15, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.15))
                            .frame(height: 100)
                            .overlay(
                                Text("Journal Entry \(index + 1)")
                                    .font(.headline)
                            )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, geometry.safeAreaInsets.bottom)
            }
            .background(Color.blue.opacity(0.05))

        case .digDeeper:
            ScrollView {
                VStack(spacing: 16) {
                    Color.clear.frame(height: topPadding)

                    Text("Swipe left/right or tap the pills above")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(0..<8, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.purple.opacity(0.15))
                            .frame(height: 150)
                            .overlay(
                                Text("Insight \(index + 1)")
                                    .font(.headline)
                            )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, geometry.safeAreaInsets.bottom)
            }
            .background(Color.purple.opacity(0.05))
        }
    }
}
