//
//  ReplyFeedbackSheet.swift
//  withMemento
//
//  Shared reason sheet for thumbs-down and Report answer (spec 041 R4).
//  Chrome matches ChatSummarySheet (handle, type, stacked glass CTAs).
//

import SwiftUI

struct ReplyFeedbackSheet: View {
    let draft: FeedbackDraft
    var onCancel: () -> Void
    var onSubmit: (AnswerFeedbackCategory, String, Bool) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @ObservedObject private var preferences = PreferencesService.shared

    @State private var category: AnswerFeedbackCategory?
    @State private var note: String = ""

    private var isReport: Bool { draft.source == .report }
    private var canSubmit: Bool { category != nil }
    private var sharingEnabled: Bool { preferences.shareFeedbackWithDeveloper }

    var body: some View {
        VStack(spacing: 0) {
            MementoSheetHandle()

            ScrollView {
                VStack(spacing: 0) {
                    heroIcon
                        .padding(.bottom, Spacing.md)

                    Text(isReport ? "Report this answer" : "What went wrong?")
                        .font(type.h4)
                        .foregroundStyle(theme.foreground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Spacing.xs)

                    Text(disclosureCopy)
                        .font(type.body1)
                        .foregroundStyle(theme.mutedForeground)
                        .multilineTextAlignment(.center)
                        .lineSpacing(type.bodyLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)

                    ThemeFlowLayout(spacing: Spacing.xs) {
                        ForEach(AnswerFeedbackCategory.allCases) { item in
                            categoryChip(item)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.md)

                    noteField
                        .padding(.top, Spacing.md)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
        }
        .onAppear {
            category = draft.category
            note = draft.note
        }
        .presentationDetents([.height(520), .large])
        .mementoSheetPresentation()
    }

    // MARK: - Chrome

    private var heroIcon: some View {
        Image(systemName: isReport ? "flag" : "hand.thumbsdown")
            .font(.system(size: 28, weight: .medium)) // icon-size: not user text
            .foregroundStyle(theme.foreground)
            .frame(width: AppHeaderMetrics.controlSize, height: AppHeaderMetrics.controlSize)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var disclosureCopy: String {
        if isReport {
            return "This sends the question, this answer, and your reason so we can improve. Journal stays on this device."
        }
        if sharingEnabled {
            return "Tell us what went wrong. If quality feedback sharing is on, the rating and note can be sent for verification — not your journal."
        }
        return "Tell us what went wrong. This is stored on this device unless you turn on Share quality feedback in Settings."
    }

    private var noteField: some View {
        TextField("Anything we should know?", text: $note, axis: .vertical)
            .font(type.body2)
            .foregroundStyle(theme.foreground)
            .lineLimit(2...4)
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
                    .fill(theme.card)
            )
            .accessibilityIdentifier("chat.feedback.note")
    }

    // MARK: - Actions

    private var actions: some View {
        GlassEffectContainer(spacing: Spacing.xs) {
            VStack(spacing: Spacing.sm) {
                submitButton
                cancelButton
            }
        }
    }

    private var submitButton: some View {
        Button {
            guard let category else { return }
            let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
            onSubmit(category, trimmed, isReport)
        } label: {
            Text(isReport ? "Submit report" : "Submit")
                .font(type.button)
                .frame(maxWidth: .infinity)
                .foregroundStyle(BaseColors.white)
                .mementoGlassButtonChrome(MementoSheetChrome.primaryGlass)
        }
        .buttonStyle(PrimaryButtonPressStyle())
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.5)
        .accessibilityIdentifier("chat.feedback.submit")
    }

    private var cancelButton: some View {
        Button {
            onCancel()
        } label: {
            Text("Cancel")
                .font(type.button)
                .frame(maxWidth: .infinity)
                .foregroundStyle(theme.foreground)
                .mementoGlassButtonChrome()
        }
        .buttonStyle(PrimaryButtonPressStyle())
        .accessibilityIdentifier("chat.feedback.cancel")
    }

    private func categoryChip(_ item: AnswerFeedbackCategory) -> some View {
        let selected = category == item
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            category = item
        } label: {
            Text(item.title)
                .font(type.body2Medium)
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(selected ? theme.card : theme.muted)
                )
                .overlay {
                    Capsule()
                        .stroke(selected ? theme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.feedback.category.\(item.rawValue)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Overflow control shared by the action bar, refuse, and empty-observation rows.
struct ReplyOverflowMenu: View {
    var isReported: Bool
    var onReportAnswer: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            Button {
                onReportAnswer()
            } label: {
                Label(isReported ? "Reported" : "Report answer",
                      systemImage: isReported ? "checkmark" : "flag")
            }
            .disabled(isReported)
            .accessibilityIdentifier("chat.reply.report")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                .foregroundStyle(isReported ? theme.accent : theme.iconForeground)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("chat.reply.more")
    }
}

#Preview("Report") {
    ReplyFeedbackSheet(
        draft: FeedbackDraft(messageID: UUID(), source: .report, category: nil, note: ""),
        onCancel: {},
        onSubmit: { _, _, _ in }
    )
    .useTheme()
    .useTypography()
}

#Preview("Thumbs down") {
    ReplyFeedbackSheet(
        draft: FeedbackDraft(messageID: UUID(), source: .thumbsDown, category: nil, note: ""),
        onCancel: {},
        onSubmit: { _, _, _ in }
    )
    .useTheme()
    .useTypography()
}
