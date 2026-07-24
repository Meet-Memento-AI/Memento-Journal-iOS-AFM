import SwiftUI

/// A tiny, self-contained UI component with **pure inputs** so it can preview instantly
/// without booting your app, networking, or hitting storage.
struct JournalCard: View {
    // MARK: - Inputs (pure data only)
    let title: String
    let excerpt: String
    let date: Date
    /// True while this entry is written locally but hasn't reached the
    /// server yet (offline write, or a sync retry in progress).
    var isPendingSync: Bool = false

    /// Optional actions (no-op by default so previews never depend on app state)
    var onTap: (() -> Void)? = nil
    var onEditTapped: (() -> Void)? = nil
    var onDeleteTapped: (() -> Void)? = nil
    /// When false, all gestures and context menu are disabled (e.g. carousel preview in WelcomeView).
    var isInteractive: Bool = true

    // MARK: - Environment
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme
     
    // MARK: - State
    @State private var isPressed = false

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            header
                .hPadding(Spacing.lg)
                .padding(.top, Spacing.lg)

            // Excerpt
            Text(excerpt)
                .typographyBody1()
                .foregroundStyle(theme.mutedForeground)
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .hPadding(Spacing.lg)
                .padding(.top, Spacing.sm)

            // Footer/Date
            footer
                .hPadding(Spacing.lg)
                .vPadding(Spacing.md)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.secondary, theme.card], // Use semantic tokens
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(colorScheme == .dark ? GrayScale.gray900 : .white, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
        .pressEffect(isPressed: $isPressed, scale: 0.98, duration: Spacing.Duration.fast)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isInteractive else { return }
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap?()
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            guard isInteractive else { return }
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .modifier(JournalCardContextMenuModifier(isInteractive: isInteractive, onEditTapped: onEditTapped, onDeleteTapped: onDeleteTapped))
        .allowsHitTesting(isInteractive)
        // MARK: - Accessibility
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isInteractive ? "Double-tap to open" : "")
        .accessibilityAddTraits(isInteractive ? [.isButton] : [])
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

    // MARK: - Subviews
    private var header: some View {
        Text(title)
            .typographyH5()
            .foregroundStyle(theme.foreground)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(type.body2)
                .fontWeight(.bold)
                .foregroundStyle(theme.primary)
                .cornerRadius(16)
            Text(formattedDate)
                .typographyCaptionBold()
                .foregroundStyle(theme.mutedForeground)

            if isPendingSync {
                pendingSyncBadge
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Journal entry date \(formattedDate)\(isPendingSync ? ", waiting to sync" : "")")
    }

    private var pendingSyncBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .bold)) // icon-size: not user text
            Text("Pending sync")
                .typographyCaptionBold()
        }
        .foregroundStyle(theme.mutedForeground)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(theme.muted)
        )
    }

    // MARK: - Date Formatting
    private var formattedDate: String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        let monthName = monthFormatter.string(from: date)

        return "\(monthName) \(day)\(ordinalSuffix(for: day))"
    }

    private func ordinalSuffix(for day: Int) -> String {
        switch day {
        case 1, 21, 31:
            return "st"
        case 2, 22:
            return "nd"
        case 3, 23:
            return "rd"
        default:
            return "th"
        }
    }

    private var accessibilityLabel: String {
        "Journal card, \(title). Dated \(formattedDate). \(excerpt)"
    }
}

// MARK: - Context menu only when interactive
private struct JournalCardContextMenuModifier: ViewModifier {
    let isInteractive: Bool
    var onEditTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?

    func body(content: Content) -> some View {
        if isInteractive {
            content.contextMenu {
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

// MARK: - Sample Data (for previews & local playgrounds)
extension JournalCard {
    static let sampleTitle = "Morning Reflection"
    static let sampleExcerpt = "I woke up feeling a bit groggy and not entirely refreshed. The alarm felt a bit harsh, and I struggled to get out of bed. Once I did, I noticed that the sky .."
}

// MARK: - SIDE-CAR PREVIEW HARNESS
// Keep previews in the same file for convenience, or move into `JournalCard+Preview.swift`.
// Import NOTHING from your app target here besides SwiftUI and this view file.
private struct JournalCardHarness: View {
    // Create January 2026 date for preview
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
            onTap: { /* no-op for harness */ },
            onEditTapped: { /* no-op for harness */ },
            onDeleteTapped: { /* no-op for harness */ }
        )
        .previewLayout(.sizeThatFits)
        .frame(maxWidth: .infinity) // allow card to stretch
        .background(Color(uiColor: .systemBackground))
        .useTheme()
        .useTypography()
    }
}



#Preview("JournalCard · light") {
    JournalCardHarness()
}


#Preview("JournalCard · long text") {
    JournalCard(
        title: "Weekly review and planning checklist for Q4",
        excerpt: "What went well: shipped UI preview harnesses, stabilized Xcode canvas. What to improve: fewer side effects in initializers, mock services end-to-end. Next: connect Supabase after UI is final.",
        date: .now.addingTimeInterval(-36_00)
    )
    //.previewLayout(.sizeThatFits)
    .padding()
}
