//
//  ReplyFeedbackSheet.swift
//  MeetMemento
//
//  Shared reason sheet for thumbs-down and Report answer (spec 041 R4).
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
    @State private var includeTextForReview = false

    private var isReport: Bool { draft.source == .report }
    private var canSubmit: Bool { category != nil }
    private var sharingEnabled: Bool { preferences.shareFeedbackWithDeveloper }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(disclosureCopy)
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)

                ThemeFlowLayout(spacing: 8) {
                    ForEach(AnswerFeedbackCategory.allCases) { item in
                        categoryChip(item)
                    }
                }

                TextField("Anything we should know?", text: $note, axis: .vertical)
                    .font(type.body2)
                    .foregroundStyle(theme.foreground)
                    .lineLimit(2...4)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
                            .fill(theme.muted.opacity(0.4))
                    )
                    .accessibilityIdentifier("chat.feedback.note")

                if isReport && sharingEnabled {
                    Toggle(isOn: $includeTextForReview) {
                        Text("Include the question and answer for review")
                            .font(type.body2)
                            .foregroundStyle(theme.foreground)
                    }
                    .tint(theme.primary)
                    .accessibilityIdentifier("chat.feedback.includeText")
                }

                Spacer(minLength: 0)

                HStack(spacing: Spacing.sm) {
                    Button("Cancel") { onCancel() }
                        .font(type.body2Medium)
                        .foregroundStyle(theme.foreground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .accessibilityIdentifier("chat.feedback.cancel")

                    Button {
                        guard let category else { return }
                        let trimmed = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
                        let includeText = isReport && sharingEnabled && includeTextForReview
                        onSubmit(category, trimmed, includeText)
                    } label: {
                        Text(isReport ? "Submit report" : "Submit")
                            .font(type.body2Medium)
                            .foregroundStyle(canSubmit ? theme.primaryForeground : theme.mutedForeground)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous)
                                    .fill(canSubmit ? theme.primary : theme.muted)
                            )
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("chat.feedback.submit")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .navigationTitle(isReport ? "Report answer" : "What went wrong?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            category = draft.category
            note = draft.note
            includeTextForReview = false
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var disclosureCopy: String {
        if sharingEnabled {
            return isReport
                ? "We'll review this reply. Ratings and your note can be sent for verification. Journal text is included only if you choose that below."
                : "Tell us what went wrong. If quality feedback sharing is on, the rating and note can be sent for verification — not your journal."
        }
        return isReport
            ? "We'll review this reply on this device. Turn on Share quality feedback in Settings to send a report for verification."
            : "Tell us what went wrong. This is stored on this device unless you turn on Share quality feedback in Settings."
    }

    private func categoryChip(_ item: AnswerFeedbackCategory) -> some View {
        let selected = category == item
        return Button {
            category = item
        } label: {
            Text(item.title)
                .font(type.body2Medium)
                .foregroundStyle(selected ? theme.primaryForeground : theme.foreground)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(selected ? theme.primary : theme.muted)
                )
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
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isReported ? theme.accent : theme.mutedForeground)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("chat.reply.more")
    }
}
