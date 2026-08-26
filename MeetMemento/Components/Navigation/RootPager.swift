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
//  Bounded exception: Chat's suggestion carousel consumes pans in its own hit
//  rect (`isolateFromPagingScroll`) so its rubber-band cannot slide this pager.
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

    /// Programmatic pager navigation — same horizontal slide as a swipe.
    public static func select(_ page: RootPage, in selection: Binding<RootPage>) {
        guard selection.wrappedValue != page else { return }
        withAnimation(.default) {
            selection.wrappedValue = page
        }
    }
}

// MARK: - RootPager

/// Pages between the root screens.
///
/// Built on `TabView` + `.page`, deliberately: it gives interruptible,
/// rubber-banded, velocity-aware paging and per-page state preservation that a
/// hand-rolled `DragGesture` would only approximate. The previous version of
/// this file shipped exactly such a hand-rolled alternative
/// (`SwipeGestureModifier`) that never had a single call site.
///
/// Layout contract (spec 027 R3): Journal and Chat on ContentView's outer
/// ZStack. Page `TabView` otherwise keeps its own top inset, which stacked
/// on `windowTop` and floated headers. Expand the pager to the physical
/// frame (`windowTop` on the glass row, `windowBottom + 16` on the footer).
/// Narration is a mode of `AIChatView`, not a sibling of this pager.
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
        GeometryReader { proxy in
            // TabView + `.page` keeps a top inset even when told to ignore
            // the safe area. Lift the pager by its global minY so Journal/Chat
            // occupy the physical frame.
            let topLift = max(proxy.frame(in: .global).minY, 0)
            let bottomLift = topLift > 0 ? AppHeaderMetrics.windowBottom : 0
            TabView(selection: $selection) {
                ForEach(RootPage.allCases) { page in
                    content(page)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.clear)
                        .ignoresSafeArea()
                        .tag(page)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .frame(
                width: proxy.size.width,
                height: proxy.size.height + topLift + bottomLift
            )
            .offset(y: -topLift)
        }
        .ignoresSafeArea()
        .onChange(of: selection) { _, _ in
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
        .background(theme.secondaryBackground.ignoresSafeArea())
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
                GrayScale.gray100
                VStack(spacing: 16) {
                    Text(page == .journal ? "Journal" : "Chat").font(.largeTitle)
                    Button("Go to the other page") {
                        RootPage.select(page == .journal ? .chat : .journal, in: $page)
                    }
                }
            }
        }
    }
}
