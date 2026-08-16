//
//  RootPager.swift
//  MeetMemento
//
//  Whole-page horizontal paging between the two root screens.
//
//  This replaces the old pill segmented control (`TopNav`/`TopNavHeader`). The
//  pills were a third navigation surface floating above both pages; now the
//  pages themselves carry mirrored corner icons — Journal's top-right chat icon
//  goes to Chat, Chat's top-left book icon comes back — and a swipe does the
//  same thing. That is the Snapchat/Instagram root-paging pattern: the icon is a
//  one-tap equivalent of the swipe, not a separate navigation, and it sits in
//  the corner facing its destination so the two agree directionally.
//
//  Nothing else in the app may own a horizontal edge drag while this is on
//  screen. The left drawer used to, and its edge gesture was attached to the
//  entire NavigationStack — that is why it was removed rather than hidden.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - RootPage

/// The two root screens. Previously `JournalTopTab` with `title` strings, which
/// only existed to label the pills.
public enum RootPage: String, CaseIterable, Identifiable, Hashable {
    case journal
    case chat

    public var id: String { rawValue }
}

// MARK: - RootPager

/// Pages between the root screens, full-bleed.
///
/// Built on `TabView` + `.page`, deliberately: it gives interruptible,
/// rubber-banded, velocity-aware paging and per-page state preservation that a
/// hand-rolled `DragGesture` would only approximate. The previous version of
/// this file shipped exactly such a hand-rolled alternative
/// (`SwipeGestureModifier`) that never had a single call site.
public struct RootPager<Content: View>: View {
    @Binding public var selection: RootPage
    public let content: (RootPage) -> Content

    @Environment(\.theme) private var theme

    public init(
        selection: Binding<RootPage>,
        @ViewBuilder content: @escaping (RootPage) -> Content
    ) {
        self._selection = selection
        self.content = content
    }

    public var body: some View {
        TabView(selection: $selection) {
            ForEach(RootPage.allCases) { page in
                // Deliberately NOT `.ignoresSafeArea(edges: .all)` here. The
                // previous pager did that, and it overrode each page's own
                // safe-area handling: the pages attach their headers with
                // `safeAreaInset(edge: .top)`, and forcing the content into the
                // safe area from out here pushed those headers to y = -48 —
                // above the screen edge, where taps land on the status bar
                // instead of the buttons. Each page owns its own bleed; its
                // background already ignores every edge.
                content(page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .tag(page)
            }
        }
        .background(theme.background)
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
        // The tactile half of the pattern — both apps this is modelled on tick
        // when the page commits, whether it was swiped or tapped.
        .onChange(of: selection) { _, _ in
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
        .background(theme.background.ignoresSafeArea())
    }
}

// MARK: - Previews

#Preview("RootPager") {
    RootPagerPreview()
        .useTheme()
        .useTypography()
}

private struct RootPagerPreview: View {
    @State private var page: RootPage = .journal

    var body: some View {
        RootPager(selection: $page) { page in
            ZStack {
                (page == .journal ? Color.blue : Color.purple).opacity(0.2)
                VStack(spacing: 16) {
                    Text(page == .journal ? "Journal" : "Chat").font(.largeTitle)
                    Button("Go to the other page") {
                        withAnimation { self.page = page == .journal ? .chat : .journal }
                    }
                }
            }
        }
    }
}
