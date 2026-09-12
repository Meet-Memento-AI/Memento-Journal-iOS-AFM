import SwiftUI
import UIKit

/// A tiny, self-contained UI component with **pure inputs** so it can preview instantly
/// without booting your app, networking, or hitting storage.
///
/// Figma 804:3342 (text) / 804:3343 (photo as full-bleed backdrop).
struct JournalCard: View {
    // MARK: - Inputs (pure data only)
    let title: String
    let excerpt: String
    let date: Date
    /// The entry's decrypted cover photo, if any. Kept a plain synchronous
    /// `Image?` — no async/decrypt logic here — so this view keeps its "pure
    /// inputs, previews instantly" contract; the caller (YourEntriesView) owns
    /// the lazy decrypt+cache.
    var photoImage: Image? = nil
    /// Downsampled average of the cover, used to adapt scrim/blur for WCAG.
    var photoSample: JournalBackdropSample? = nil
    /// True when the entry has a stored cover. Independent of `photoImage` so
    /// a cache miss uses photo chrome (placeholder) instead of the text-only card.
    var hasPhoto: Bool = false

    /// Optional actions (no-op by default so previews never depend on app state)
    var onTap: (() -> Void)? = nil
    var onEditTapped: (() -> Void)? = nil
    var onDeleteTapped: (() -> Void)? = nil
    /// When false, all gestures and context menu are disabled (e.g. carousel preview in WelcomeView).
    var isInteractive: Bool = true

    // MARK: - Environment
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        card
            .modifier(JournalCardInteractionModifier(
                isInteractive: isInteractive,
                onTap: onTap,
                onEditTapped: onEditTapped,
                onDeleteTapped: onDeleteTapped
            ))
            .modifier(JournalCardAccessibilityModifier(
                isInteractive: isInteractive,
                label: accessibilityLabel,
                onTap: onTap,
                onEditTapped: onEditTapped,
                onDeleteTapped: onDeleteTapped
            ))
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.xxl, style: .continuous)
    }

    /// Photo rows always use photo chrome, even before the image arrives.
    static func usesPhotoChrome(hasPhoto: Bool) -> Bool { hasPhoto }

    private var card: some View {
        Group {
            if let photoImage {
                photoCardBody(photoImage)
            } else if hasPhoto {
                photoPlaceholderBody
            } else {
                plainCardBody
            }
        }
    }

    private func cardChrome<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .clipShape(cardShape)
            .contentShape(cardShape)
            .containerShape(cardShape)
    }

    private var plainCardBody: some View {
        cardChrome {
            contentStack(titleColor: theme.foreground)
                .padding(Spacing.xl)
                .background(theme.journalCardFill)
        }
    }

    private func photoCardBody(_ image: Image) -> some View {
        cardChrome {
            contentStack(titleColor: BaseColors.white)
                .padding(Spacing.xl)
                .background {
                    JournalPhotoBackdrop(image: image, sample: photoSample)
                }
        }
    }

    /// Same chip + title stack as a photo card, flat fill until the cover
    /// is in cache. Title stays `theme.foreground` — white only on the image.
    private var photoPlaceholderBody: some View {
        cardChrome {
            contentStack(titleColor: theme.foreground)
                .padding(Spacing.xl)
                .background(theme.journalCardFill)
        }
    }

    private func contentStack(titleColor: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            dateChip
            Text(title)
                .typographyH4()
                .photoCoverForeground(titleColor, shadowed: photoImage != nil)
                // Button injects `lineLimit(1)` into its label environment;
                // override so the card grows with the full title instead of
                // clipping to a single line in LazyVStack.
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Date / time / day as native clear glass (hair of frost). Type only —
    /// Figma 804:3342 has no calendar glyph.
    private var dateChip: some View {
        Text(formattedDate)
            .font(type.body1Bold)
            .photoCoverForeground(dateChipForeground, shadowed: photoImage != nil)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .glassEffect(
                .native(interactive: false),
                in: .rect(cornerRadius: theme.radius.button, style: .continuous)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Journal entry date \(formattedDate)")
    }

    /// White on a treated cover, same as editor chrome. Theme ink on the
    /// flat canvas / photo placeholder, where white would vanish into frost.
    private var dateChipForeground: Color {
        photoImage != nil ? BaseColors.white : theme.foreground
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        return formatter.string(from: date)
    }

    private var accessibilityLabel: String {
        let photoSuffix = hasPhoto ? ", with photo" : ""
        return "Journal card, \(title)\(photoSuffix). Dated \(formattedDate). \(excerpt)"
    }
}

// MARK: - Gestures & hit-testing (split out of `body` for type-checker performance)
private struct JournalCardInteractionModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let isInteractive: Bool
    var onTap: (() -> Void)?
    var onEditTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.xxl, style: .continuous)
    }

    func body(content: Content) -> some View {
        if isInteractive {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTap?()
            } label: {
                content
                    .environment(\.lineLimit, nil)
            }
            .buttonStyle(JournalCardButtonStyle())
            .buttonBorderShape(.roundedRectangle(radius: theme.radius.xxl))
            .containerShape(cardShape)
            .modifier(JournalCardContextMenuModifier(
                isInteractive: true,
                onEditTapped: onEditTapped,
                onDeleteTapped: onDeleteTapped
            ))
        } else {
            content
                .allowsHitTesting(false)
        }
    }
}

private struct JournalCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.lineLimit, nil)
    }
}

private struct JournalCardAccessibilityModifier: ViewModifier {
    let isInteractive: Bool
    let label: String
    var onTap: (() -> Void)?
    var onEditTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?

    private var traits: AccessibilityTraits { isInteractive ? .isButton : [] }
    private var hint: String { isInteractive ? "Double-tap to open" : "" }

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(traits)
            .accessibilityAction(named: "Open") {
                onTap?()
            }
            .accessibilityAction(named: "Edit") {
                onEditTapped?()
            }
            .accessibilityAction(named: "Delete") {
                onDeleteTapped?()
            }
    }
}

private struct JournalCardContextMenuModifier: ViewModifier {
    @Environment(\.theme) private var theme
    let isInteractive: Bool
    var onEditTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.xxl, style: .continuous)
    }

    func body(content: Content) -> some View {
        if isInteractive {
            content
                .contentShape(.contextMenuPreview, cardShape)
                .contextMenu {
                    Button(action: { onEditTapped?() }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: { onDeleteTapped?() }) {
                        Label("Delete", systemImage: "trash")
                    }
                }
        } else {
            content
        }
    }
}

extension JournalCard {
    static let sampleTitle = "Morning Reflection"
    static let sampleExcerpt = "I woke up feeling a bit groggy and not entirely refreshed. The alarm felt a bit harsh, and I struggled to get out of bed. Once I did, I noticed that the sky .."
}

private struct JournalCardHarness: View {
    private var previewDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        return Calendar.current.date(from: components) ?? .now
    }

    var body: some View {
        JournalCard(
            title: JournalCard.sampleTitle,
            excerpt: JournalCard.sampleExcerpt,
            date: previewDate,
            onTap: { },
            onEditTapped: { },
            onDeleteTapped: { }
        )
        .frame(maxWidth: .infinity)
        .padding()
        .background(Theme.light.background)
        .useTheme()
        .useTypography()
    }
}

#Preview("JournalCard · light") {
    JournalCardHarness()
}

#Preview("JournalCard · long text") {
    JournalCard(
        title: "Took the long way home through the park and watched the leaves change without rushing",
        excerpt: "What went well: shipped UI preview harnesses, stabilized Xcode canvas.",
        date: .now.addingTimeInterval(-36_00)
    )
    .padding()
        .background(Theme.light.background)
    .useTheme()
    .useTypography()
}

private enum JournalCardPreviewAssets {
    static let photo: Image = {
        let size = CGSize(width: 4, height: 3)
        let uiImage = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return Image(uiImage: uiImage)
    }()

    static let sample = JournalBackdropSample(red: 0.25, green: 0.55, blue: 0.55)
}

#Preview("JournalCard · with photo") {
    JournalCard(
        title: "Took the long way home through the park and watched the leaves change without rushing",
        excerpt: JournalCard.sampleExcerpt,
        date: .now.addingTimeInterval(-86_400),
        photoImage: JournalCardPreviewAssets.photo,
        photoSample: JournalCardPreviewAssets.sample,
        hasPhoto: true
    )
    .padding()
        .background(Theme.light.background)
    .useTheme()
    .useTypography()
}

#Preview("JournalCard · with photo, dark") {
    JournalCard(
        title: "Took the long way home through the park and watched the leaves change without rushing",
        excerpt: JournalCard.sampleExcerpt,
        date: .now.addingTimeInterval(-86_400),
        photoImage: JournalCardPreviewAssets.photo,
        photoSample: JournalCardPreviewAssets.sample,
        hasPhoto: true
    )
    .padding()
        .background(Theme.dark.background)
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}

#Preview("JournalCard · photo placeholder") {
    JournalCard(
        title: "Took the long way home through the park and watched the leaves change without rushing",
        excerpt: JournalCard.sampleExcerpt,
        date: .now.addingTimeInterval(-86_400),
        hasPhoto: true
    )
    .padding()
        .background(Theme.light.background)
    .useTheme()
    .useTypography()
}

#Preview("JournalCard · dark") {
    JournalCard(
        title: JournalCard.sampleTitle,
        excerpt: JournalCard.sampleExcerpt,
        date: .now
    )
    .padding()
        .background(Theme.dark.background)
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
