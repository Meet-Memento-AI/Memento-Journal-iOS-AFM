//
//  RootNavigationChrome.swift
//  withMemento
//
//  The one size-class branch for root-page chrome.
//
//  Compact width (every iPhone, and iPad Slide Over / narrow Split View) keeps
//  the floating `AppHeader` glass row exactly as it is. Regular width wraps
//  each `RootPager` page in its own `NavigationStack` and hands the same
//  `AppHeader` controls to a native `.toolbar` with an inline title. The pager,
//  pages, sheets and `navigationPath` routes are untouched either way.
//

import SwiftUI

private struct RootNavigationBarHostedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a page that `rootNavigationStack(title:)` wrapped in a
    /// native navigation bar. `AppHeader` reads it, so the header can never
    /// move into a toolbar that is not there.
    var rootNavigationBarHosted: Bool {
        get { self[RootNavigationBarHostedKey.self] }
        set { self[RootNavigationBarHostedKey.self] = newValue }
    }
}

extension View {
    /// Wraps a root page in a native `NavigationStack` on regular width only.
    func rootNavigationStack(title: String) -> some View {
        modifier(RootNavigationStack(title: title))
    }

    /// Hands `AppHeader`'s controls to the enclosing native navigation bar
    /// when one exists; otherwise leaves the glass row as it is.
    func rootHeaderToolbar<Leading: View, Trailing: View>(
        leading: Leading,
        trailing: Trailing
    ) -> some View {
        modifier(RootHeaderToolbar(leading: leading, trailing: trailing))
    }
}

private struct RootNavigationStack: ViewModifier {
    let title: String

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            NavigationStack {
                content
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .environment(\.rootNavigationBarHosted, true)
            }
        } else {
            content
        }
    }
}

private struct RootHeaderToolbar<Leading: View, Trailing: View>: ViewModifier {
    let leading: Leading
    let trailing: Trailing

    @Environment(\.rootNavigationBarHosted) private var hosted

    func body(content: Content) -> some View {
        if hosted {
            // The controls keep their own 48pt glass; the bar's shared glass
            // is hidden so they do not read as glass on glass.
            Color.clear
                .frame(height: 0)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        leading
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .topBarTrailing) {
                        trailing
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        } else {
            content
        }
    }
}

// MARK: - Previews

#Preview("Root header · regular width", traits: .fixedLayout(width: 1032, height: 1376)) {
    RootNavigationChromePreview()
        .environment(\.horizontalSizeClass, .regular)
}

#Preview("Root header · compact width") {
    RootNavigationChromePreview()
        .environment(\.horizontalSizeClass, .compact)
}

// periphery:ignore - instantiated only by #Preview canvases
private struct RootNavigationChromePreview: View {
    var body: some View {
        RootPageScaffold(
            header: {
                AppHeader {
                    AvatarInitialButton(
                        initial: "S",
                        size: AppHeaderMetrics.controlSize,
                        enableHaptic: true,
                        accessibilityLabel: "Menu"
                    ) {}
                } trailing: {
                    HeaderIconButton(
                        systemName: "magnifyingglass",
                        accessibilityLabel: "Search"
                    ) {}
                }
            },
            content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(0..<12) { index in
                            RoundedRectangle(cornerRadius: 16)
                                .fill(GrayScale.gray100)
                                .frame(height: 96)
                                .overlay { Text("Entry \(index + 1)") }
                        }
                    }
                    .padding(.horizontal, AppHeaderMetrics.edgeInset)
                    .contentColumn()
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppHeaderMetrics.contentTopPadding)
                }
            }
        )
        .rootNavigationStack(title: "Journal")
        .useTheme()
        .useTypography()
    }
}
