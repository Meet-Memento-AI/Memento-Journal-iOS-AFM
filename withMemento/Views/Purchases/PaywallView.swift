//
//  PaywallView.swift
//  withMemento
//
//  Spec 021: the Memento Pro paywall, drawn by the app over the RevenueCat
//  current offering. RevenueCat still does products, purchase, restore and
//  entitlements (`EntitlementStore`); this view only draws them.
//
//  - Annual first, prices only from the store (R1).
//  - Restore sits in the pinned footer, so it is visible without scrolling at
//    every text size (R3).
//  - The Free / Pro table shows the free/paid split (R4) as it is: capture,
//    search and export are free. Nothing here sells Apple's models or quota
//    (017 R3).
//
//  Layout: mark, serif title, a Yearly / Monthly pill, the comparison table,
//  and a pinned button that carries the price.
//
//  Shadows RevenueCatUI's `PaywallView` inside this module; this one wins.

import SwiftUI

struct PaywallView: View {
    /// What the person just did that opened the paywall (spec 021 R9). It
    /// picks the headline and description.
    let trigger: PaywallTrigger

    @StateObject private var model: PaywallModel
    @ObservedObject private var store = EntitlementStore.shared

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Entry counts and the day, set at the root, so the headline can cite
    /// the journal when that makes it true.
    @Environment(\.paywallContext) private var paywallContext

    /// At accessibility sizes the footer pins only the button and Restore
    /// (R3); the terms move under the table so the content keeps its room.
    private var isCompactFooter: Bool { dynamicTypeSize.isAccessibilitySize }

    /// `model` defaults to the live store; previews and the DEBUG harness pass
    /// `PaywallModel.preview()`.
    init(trigger: PaywallTrigger = .settings, model: PaywallModel? = nil) {
        self.trigger = trigger
        _model = StateObject(wrappedValue: model ?? PaywallModel.live())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                header
                    .padding(.bottom, Spacing.xs)
                plansSection
                PaywallComparisonTable()
                if isCompactFooter {
                    disclosure
                    legalLinks
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
            .proseColumn(PaywallMetrics.column)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background(theme.background.ignoresSafeArea())
        .interactiveDismissDisabled(model.phase == .purchasing)
        .task { await model.load() }
        // A purchase, a restore, or the customer-info stream unlocking Pro.
        .onChange(of: store.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    // MARK: - Top

    private var topBar: some View {
        ZStack(alignment: .topTrailing) {
            MementoSheetHandle()
                .frame(maxWidth: .infinity)
            HeaderIconButton(
                systemName: "xmark",
                size: 40,
                accessibilityLabel: "Close",
                action: { dismiss() }
            )
            .accessibilityIdentifier("paywall.close")
            .padding(.top, Spacing.sm)
            .padding(.trailing, Spacing.md)
        }
    }

    private var header: some View {
        VStack(spacing: Spacing.lg) {
            MementoBrandMark(size: 56)

            VStack(spacing: Spacing.xs) {
                Text(trigger.title(in: paywallContext))
                    .font(type.h2)
                    .foregroundStyle(theme.foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(trigger.subtitle(in: paywallContext))
                    .font(type.body1)
                    .foregroundStyle(theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Billing

    @ViewBuilder
    private var plansSection: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 52)
                .accessibilityLabel("Loading plans")
        case .failed(let message):
            VStack(spacing: Spacing.md) {
                Text(message)
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                SecondaryButton(title: "Try again") {
                    Task { await model.load() }
                }
                .accessibilityIdentifier("paywall.retry")
            }
        case .ready, .purchasing:
            PaywallBillingToggle(
                plans: model.plans,
                selectedID: model.selected?.id,
                savingsPercent: model.savingsPercent
            ) { id in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    model.selectedID = id
                }
            }
            .disabled(model.phase == .purchasing)
            .sensoryFeedback(.selection, trigger: model.selectedID)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Spacing.xs) {
            let plan = model.selected

            PrimaryButton(
                title: plan?.ctaTitle ?? "Continue",
                isLoading: model.phase == .purchasing
            ) {
                Task {
                    if await model.purchase() { dismiss() }
                }
            }
            .disabled(plan == nil || model.phase != .ready)
            .opacity(plan == nil || model.phase == .loading ? Spacing.Opacity.disabled : 1)
            .accessibilityIdentifier("paywall.purchase")

            restoreLink

            if !isCompactFooter {
                disclosure
                legalLinks
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.sm)
        .frame(maxWidth: PaywallMetrics.column)
        .frame(maxWidth: .infinity)
        .background {
            // A short fade instead of a rule, so the table dissolves under the
            // footer rather than being cut by a line.
            theme.background
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [theme.background.opacity(0), theme.background],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: Spacing.xl)
                    .offset(y: -Spacing.xl)
                    .allowsHitTesting(false)
                }
        }
    }

    /// The selected plan's renewal terms (App Review 3.1.2).
    @ViewBuilder
    private var disclosure: some View {
        if let plan = model.selected, model.phase == .ready || model.phase == .purchasing {
            Text(plan.disclosure)
                .font(type.caption)
                .foregroundStyle(theme.foreground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("paywall.disclosure")
        }
    }

    /// Where ChatGPT puts "Upgrade with Apple": the one secondary action.
    private var restoreLink: some View {
        Button {
            Task { await model.restore() }
        } label: {
            HStack(spacing: Spacing.xxs) {
                Text("Restore Purchases")
                    .font(type.captionBold)
                    .underline()
                    .fixedSize()
                if store.isRestoring { ProgressView().controlSize(.mini) }
            }
            .foregroundStyle(theme.foreground)
            .frame(minHeight: 44) // AX5: minHeight, the tap target grows with text
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.phase == .purchasing || store.isRestoring)
        .accessibilityIdentifier("paywall.restore")
    }

    private var legalLinks: some View {
        HStack(spacing: Spacing.xs) {
            legalLink("Terms", identifier: "paywall.terms", url: Constants.Legal.termsOfServiceURL)
            Text("·")
                .font(type.caption)
                .foregroundStyle(theme.mutedForeground)
                .accessibilityHidden(true)
            legalLink("Privacy", identifier: "paywall.privacy", url: Constants.Legal.privacyPolicyURL)
        }
    }

    private func legalLink(_ title: String, identifier: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Text(title)
                .font(type.caption)
                .foregroundStyle(theme.mutedForeground)
                .fixedSize()
                .frame(minHeight: 44) // AX5: minHeight, the tap target grows with text
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

private enum PaywallMetrics {
    /// Narrower than the reading column: a centred composition reads calmer
    /// than a full-width one on iPad and large iPhones.
    static let column: CGFloat = 460
}

// MARK: - Billing toggle

/// Yearly / Monthly as one pill: a sunken track and a raised thumb that
/// slides to the chosen period. Yearly leads (R1) and carries the saving.
private struct PaywallBillingToggle: View {
    let plans: [PaywallPlan]
    let selectedID: String?
    let savingsPercent: Int?
    let onSelect: (String) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 0) {
            ForEach(plans) { plan in
                segment(plan)
            }
        }
        .padding(4)
        .background(theme.muted, in: Capsule())
    }

    /// Raised above the track: white in light, one step lighter in dark.
    private var thumbFill: Color {
        colorScheme == .dark ? theme.input : theme.background
    }

    private func segment(_ plan: PaywallPlan) -> some View {
        let isSelected = plan.id == selectedID
        let savings = plan.kind == .annual ? savingsPercent : nil
        return Button {
            onSelect(plan.id)
        } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.xs) { label(plan, isSelected); chip(savings) }
                VStack(spacing: 2) { label(plan, isSelected); chip(savings) }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 44) // AX5: minHeight
            .background {
                if isSelected {
                    Capsule()
                        .fill(thumbFill)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.08), radius: 6, y: 1)
                        .matchedGeometryEffect(id: "thumb", in: thumb)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plan.accessibilityLabel(savingsPercent: savings))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("paywall.plan.\(plan.kind.rawValue)")
    }

    private func label(_ plan: PaywallPlan, _ isSelected: Bool) -> some View {
        Text(plan.title)
            .font(type.body1Medium)
            .foregroundStyle(isSelected ? theme.foreground : theme.mutedForeground)
            .fixedSize()
    }

    @ViewBuilder
    private func chip(_ savingsPercent: Int?) -> some View {
        if let savingsPercent {
            Text("Save \(savingsPercent)%")
                .font(type.microMedium)
                .foregroundStyle(theme.themeTagSelectedForeground)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.themeTagSelectedBackground, in: Capsule())
                .fixedSize()
        }
    }
}

// MARK: - Comparison table

/// Features | Free | Pro. Free rows are the free-forever promise (R4); the
/// paid rows are the surfaces `proGated` locks. The mark columns are fixed
/// width so checks and dashes line up down every row.
private struct PaywallComparisonTable: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private static let markColumn: CGFloat = 52

    /// Brand brown as text: the darker `brandOnText` clears 4.5:1 on white;
    /// on black the lighter accent does.
    private var proLabelColor: Color {
        colorScheme == .dark ? theme.accent : BrandColors.brandOnText
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Text("Features")
                    .foregroundStyle(theme.mutedForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .foregroundStyle(theme.mutedForeground)
                    .frame(width: Self.markColumn)
                Text("Pro")
                    .fontWeight(.semibold)
                    .foregroundStyle(proLabelColor)
                    .frame(width: Self.markColumn)
            }
            .font(type.body1)
            .padding(.bottom, Spacing.xs)
            .accessibilityHidden(true)

            ForEach(PaywallFeature.all, id: \.name) { feature in
                HStack(spacing: Spacing.sm) {
                    Text(feature.name)
                        .font(type.body1)
                        .foregroundStyle(theme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    mark(included: feature.inFree, isPro: false)
                    mark(included: true, isPro: true)
                }
                .padding(.vertical, Spacing.sm)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(feature.accessibilityLabel)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .overlay {
            RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.comparison")
    }

    private func mark(included: Bool, isPro: Bool) -> some View {
        Image(systemName: included ? "checkmark" : "minus")
            .font(.system(size: 20, weight: .light)) // icon-size: not user text
            .foregroundStyle(isPro ? theme.accent : theme.mutedForeground.opacity(included ? 1 : 0.5))
            .frame(width: Self.markColumn)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Light — Ask") {
    PaywallView(trigger: .askWholeJournal, model: .preview())
        .useTheme()
        .useTypography()
        .preferredColorScheme(.light)
}

#Preview("Dark — Settings") {
    PaywallView(model: .preview())
        .useTheme()
        .useTypography()
        .preferredColorScheme(.dark)
}

#Preview("Ask — 57 entries") {
    PaywallView(trigger: .askWholeJournal, model: .preview())
        .environment(\.paywallContext, PaywallContext(entryCount: 57, entriesThisWeek: 4, isSunday: true))
        .useTheme()
        .useTypography()
}

#Preview("Weekly — busy Sunday") {
    PaywallView(trigger: .weeklyReview, model: .preview())
        .environment(\.paywallContext, PaywallContext(entryCount: 57, entriesThisWeek: 4, isSunday: true))
        .useTheme()
        .useTypography()
}

#Preview("Daily limit") {
    PaywallView(trigger: .dailyLimit, model: .preview())
        .useTheme()
        .useTypography()
}

#Preview("AX5 — Weekly") {
    PaywallView(trigger: .weeklyReview, model: .preview())
        .useTheme()
        .useTypography()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Loading") {
    PaywallView(model: .preview(phase: .loading))
        .useTheme()
        .useTypography()
}

#Preview("Failed") {
    PaywallView(model: .preview(phase: .failed("You're offline. Connect to the internet and try again.")))
        .useTheme()
        .useTypography()
}
#endif
