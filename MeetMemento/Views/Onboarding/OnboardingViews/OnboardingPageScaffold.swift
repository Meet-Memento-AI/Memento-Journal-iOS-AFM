//
//  OnboardingPageScaffold.swift
//  MeetMemento
//
//  Shared vertical rhythm for onboarding steps: header → content → footer.
//  Keeps pages in frame with consistent Spacing tokens across OnboardingViews.
//

import SwiftUI

/// Spacing tokens for onboarding screens (header / content / footer).
/// Aliases the app `Spacing` scale so onboarding pages share one rhythm.
enum OnboardingLayout {
    static let headerHorizontal: CGFloat = Spacing.md
    static let headerTop: CGFloat = Spacing.sm
    static let headerBottom: CGFloat = Spacing.md

    static let contentHorizontal: CGFloat = Spacing.lg
    /// Space under the header before the title / primary content.
    static let contentTop: CGFloat = Spacing.xs
    /// Title → fields / body blocks.
    static let sectionSpacing: CGFloat = Spacing.xl
    /// Title ↔ subtitle within the title block.
    static let titleBodySpacing: CGFloat = Spacing.sm
    /// Stacked text fields / compact stacks.
    static let fieldSpacing: CGFloat = Spacing.xs

    static let footerHorizontal: CGFloat = Spacing.md
    static let footerTop: CGFloat = Spacing.sm
    static let footerBottom: CGFloat = Spacing.md
    static let footerStackSpacing: CGFloat = Spacing.sm
}

/// Back-chevron header used across onboarding steps.
struct OnboardingBackHeader<Trailing: View>: View {
    @Environment(\.theme) private var theme

    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(onBack: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.onBack = onBack
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            IconButtonNav(
                icon: "chevron.left",
                iconSize: 20,
                buttonSize: 40,
                foregroundColor: theme.foreground,
                useDarkBackground: false,
                enableHaptic: true,
                onTap: onBack
            )
            .accessibilityLabel("Back")

            Spacer(minLength: 0)

            trailing()
        }
        .padding(.horizontal, OnboardingLayout.headerHorizontal)
        .padding(.top, OnboardingLayout.headerTop)
        .padding(.bottom, OnboardingLayout.headerBottom)
        .frame(maxWidth: .infinity)
        .background(theme.background)
    }
}

/// Keeps the back button optically centered when there is no trailing action.
struct OnboardingHeaderSpacer: View {
    var body: some View {
        Color.clear.frame(width: 40, height: 40)
    }
}

extension OnboardingBackHeader where Trailing == OnboardingHeaderSpacer {
    init(onBack: @escaping () -> Void) {
        self.init(onBack: onBack) {
            OnboardingHeaderSpacer()
        }
    }
}

/// Standard onboarding page chrome: background, header, in-frame content, footer.
///
/// Footer is a `safeAreaInset` so it stays above the home indicator **and** the
/// keyboard, and the content band always lays out in the remaining frame.
struct OnboardingPageScaffold<Trailing: View, Content: View, Footer: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    var onBack: (() -> Void)?
    /// When true, content scrolls between header and footer.
    var scrolls: Bool = true
    /// When true (and not scrolling), content is vertically centered in the middle band.
    var centersContent: Bool = false
    /// When false, the footer inset is omitted (no reserved bottom band).
    var showsFooter: Bool = true
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    init(
        onBack: (() -> Void)? = nil,
        scrolls: Bool = true,
        centersContent: Bool = false,
        showsFooter: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.onBack = onBack
        self.scrolls = scrolls
        self.centersContent = centersContent
        self.showsFooter = showsFooter
        self.trailing = trailing
        self.content = content
        self.footer = footer
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                OnboardingBackHeader(onBack: { onBack?() ?? dismiss() }, trailing: trailing)

                contentBand
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centersContent ? .center : .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsFooter {
                    footerBar
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var contentBand: some View {
        if scrolls {
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OnboardingLayout.contentHorizontal)
                    .padding(.top, OnboardingLayout.contentTop)
                    .padding(.bottom, OnboardingLayout.sectionSpacing)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        } else if centersContent {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, OnboardingLayout.contentHorizontal)
        } else {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, OnboardingLayout.contentHorizontal)
                .padding(.top, OnboardingLayout.contentTop)
        }
    }

    private var footerBar: some View {
        footer()
            .padding(.horizontal, OnboardingLayout.footerHorizontal)
            .padding(.top, OnboardingLayout.footerTop)
            .padding(.bottom, OnboardingLayout.footerBottom)
            .frame(maxWidth: .infinity)
            .background(theme.background.ignoresSafeArea(edges: .bottom))
    }
}

extension OnboardingPageScaffold where Trailing == OnboardingHeaderSpacer {
    init(
        onBack: (() -> Void)? = nil,
        scrolls: Bool = true,
        centersContent: Bool = false,
        showsFooter: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.init(
            onBack: onBack,
            scrolls: scrolls,
            centersContent: centersContent,
            showsFooter: showsFooter,
            trailing: { OnboardingHeaderSpacer() },
            content: content,
            footer: footer
        )
    }
}

extension OnboardingPageScaffold where Trailing == OnboardingHeaderSpacer, Footer == EmptyView {
    init(
        onBack: (() -> Void)? = nil,
        scrolls: Bool = true,
        centersContent: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            onBack: onBack,
            scrolls: scrolls,
            centersContent: centersContent,
            showsFooter: false,
            trailing: { OnboardingHeaderSpacer() },
            content: content,
            footer: { EmptyView() }
        )
    }
}
