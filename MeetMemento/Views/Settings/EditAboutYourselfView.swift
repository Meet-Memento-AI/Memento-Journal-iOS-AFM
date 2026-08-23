//
//  EditAboutYourselfView.swift
//  MeetMemento
//
//  Settings editor for the journal-goals reflection. Chrome matches
//  LearnAboutYourselfView; persist + lens rebuild stay Settings-only.
//

import SwiftUI

public struct EditAboutYourselfView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    @State private var entryText: String = LocalProfileStore.personalizationText ?? ""
    @State private var isSaving = false
    @State private var rebuildError: String?
    @FocusState private var isFocused: Bool

    /// Figma well height (334:1600) — same as LearnAboutYourselfView.
    private let editorMinHeight: CGFloat = 200

    public init() {}

    public var body: some View {
        OnboardingPageScaffold(
            onBack: { dismiss() },
            scrolls: true
        ) {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                titleSection
                bodyField
            }
        } footer: {
            PrimaryButton(title: "Save", isLoading: isSaving) {
                saveChanges()
            }
            .disabled(isSaving)
            .accessibilityLabel("Save")
            .accessibilityIdentifier("settings.saveAbout")
        }
        .alert("Couldn't update tuning", isPresented: .init(
            get: { rebuildError != nil },
            set: { if !$0 { rebuildError = nil } }
        )) {
            Button("OK") { rebuildError = nil }
        } message: {
            Text(rebuildError ?? "Your reflection was saved. Theme tuning can be rebuilt later in Settings.")
        }
    }

    // MARK: - Subviews

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("What are your journal goals?")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("This will help customize your experience.")
                .font(type.body1Medium)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    private var bodyField: some View {
        ZStack(alignment: .topLeading) {
            if entryText.isEmpty {
                Text("Start writing here...")
                    .font(type.inputLarge)
                    .foregroundStyle(GrayScale.gray400)
                    .padding(Spacing.md)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $entryText)
                .font(type.inputLarge)
                .lineSpacing(type.bodyLineSpacing(for: 18))
                .foregroundStyle(theme.foreground)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .accessibilityLabel("Journal goals")
                .accessibilityIdentifier("settings.journalGoals")
        }
        .frame(minHeight: editorMinHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous)
                .fill(theme.cardBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous))
    }

    // MARK: - Actions

    private func saveChanges() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let trimmedText = entryText.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        Task {
            LocalProfileStore.personalizationText = trimmedText.isEmpty ? nil : trimmedText
            do {
                _ = try await ExperienceProfileBuilder.rebuildLens(
                    replaceConfirmedWithSuggestions: false
                )
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    rebuildError = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("EditAboutYourselfView • Light") {
    NavigationStack {
        EditAboutYourselfView()
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.light)
}

#Preview("EditAboutYourselfView • Dark") {
    NavigationStack {
        EditAboutYourselfView()
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
