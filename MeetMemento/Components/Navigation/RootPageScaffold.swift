//
//  RootPageScaffold.swift
//  MeetMemento
//
//  Shared chrome for Journal and Chat (Chat's narration mode uses the same
//  scaffold, swapping only the footer and glow).
//
//  Root pages ignore the system safe area so no leftover band is painted.
//  AppHeader sits on the physical top and pads its glass row by `windowTop`.
//  Footer is `windowBottom + 16`.
//

import SwiftUI

/// Full-bleed page chrome. Fill reaches the physical edges; header and footer
/// sit where the window-inset padding puts them.
struct RootPageScaffold<Header: View, Footer: View, Content: View, BackgroundOverlay: View>: View {
    @Environment(\.theme) private var theme

    /// Extra air below the footer, on top of `windowBottom`. Resting chrome
    /// passes 16. Chat passes `keyboardHeight - windowBottom` while the
    /// keyboard is up so the total equals `keyboardHeight`. Pass 0 to skip
    /// the home-indicator pad (no footer).
    var footerBottomPadding: CGFloat = 16
    /// Page fill behind content. Defaults to `theme.background`; Journal passes
    /// `theme.secondaryBackground` for its subtle gray canvas.
    var pageBackground: Color? = nil
    /// Chat-only: round the top- and bottom-leading corners of the page fill
    /// so Journal's canvas shows through the seam. The page is clipped to its
    /// bounds so nothing paints onto Journal. Header, footer, and content
    /// stay full-bleed inside the page.
    var elevated: Bool = false

    @ViewBuilder var header: Header
    @ViewBuilder var footer: Footer
    @ViewBuilder var backgroundOverlay: BackgroundOverlay
    @ViewBuilder var content: Content

    /// Distance from this overlay's layout top to the physical screen top.
    /// TabView pages report a non-zero value; a full-bleed host reports 0.
    /// Offsetting by `-headerLift` pins every header to the same window origin.
    @State private var headerLift: CGFloat = 0

    init(
        footerBottomPadding: CGFloat = 16,
        pageBackground: Color? = nil,
        elevated: Bool = false,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder backgroundOverlay: () -> BackgroundOverlay,
        @ViewBuilder content: () -> Content
    ) {
        self.footerBottomPadding = footerBottomPadding
        self.pageBackground = pageBackground
        self.elevated = elevated
        self.header = header()
        self.footer = footer()
        self.backgroundOverlay = backgroundOverlay()
        self.content = content()
    }

    private var footerPad: CGFloat {
        footerBottomPadding == 0
            ? 0
            : AppHeaderMetrics.windowBottom + footerBottomPadding
    }

    private var resolvedBackground: Color {
        pageBackground ?? theme.background
    }

    private var leadingSheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: theme.radius.xxl,
            bottomLeadingRadius: theme.radius.xxl,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            resolvedBackground
                .ignoresSafeArea()
                .clipLeadingSheet(elevated, shape: leadingSheetShape)

            content

            // Voice glow (and any other page wash) sits on the canvas, above
            // content, under the footer — never composited into a backing rect.
            backgroundOverlay
                .clipLeadingSheet(elevated, shape: leadingSheetShape)

            footer
                .padding(.bottom, footerPad)
        }
        .ignoresSafeArea()
        .clipToPage(elevated)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: OverlayMinYKey.self,
                        value: geo.frame(in: .global).minY
                    )
                }
                .frame(width: 0, height: 0)

                header
                    .frame(maxWidth: .infinity)
                    .offset(y: -headerLift)
            }
            .onPreferenceChange(OverlayMinYKey.self) { headerLift = max($0, 0) }
        }
    }
}

private struct OverlayMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    @ViewBuilder
    func clipLeadingSheet(_ enabled: Bool, shape: UnevenRoundedRectangle) -> some View {
        if enabled {
            self.clipShape(shape)
        } else {
            self
        }
    }

    @ViewBuilder
    func clipToPage(_ enabled: Bool) -> some View {
        if enabled {
            self.clipped()
        } else {
            self
        }
    }
}

extension RootPageScaffold where BackgroundOverlay == EmptyView {
    init(
        footerBottomPadding: CGFloat = 16,
        pageBackground: Color? = nil,
        elevated: Bool = false,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            footerBottomPadding: footerBottomPadding,
            pageBackground: pageBackground,
            elevated: elevated,
            header: header,
            footer: footer,
            backgroundOverlay: { EmptyView() },
            content: content
        )
    }
}

extension RootPageScaffold where Footer == EmptyView, BackgroundOverlay == EmptyView {
    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            footerBottomPadding: 0,
            header: header,
            footer: { EmptyView() },
            backgroundOverlay: { EmptyView() },
            content: content
        )
    }
}
