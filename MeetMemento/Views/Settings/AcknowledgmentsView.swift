//
//  AcknowledgmentsView.swift
//  MeetMemento
//
//  Spec 030 R6 / DEC-010: OFL fonts + neural TTS model attribution.
//

import SwiftUI

struct AcknowledgmentsView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Typefaces") {
                    Text(fontAttribution)
                        .font(.footnote)
                        .foregroundStyle(theme.mutedForeground)
                        .padding(.vertical, Spacing.sm)
                        .accessibilityIdentifier("acknowledgments.fonts")
                }

                SettingsSection(title: "Voice model") {
                    Text(modelAttribution)
                        .font(.footnote)
                        .foregroundStyle(theme.mutedForeground)
                        .padding(.vertical, Spacing.sm)
                        .accessibilityIdentifier("acknowledgments.model")
                }

                if let ofl = oflText {
                    SettingsSection(title: "SIL Open Font License") {
                        Text(ofl)
                            .font(.caption2)
                            .foregroundStyle(theme.mutedForeground)
                            .padding(.vertical, Spacing.sm)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("acknowledgments.ofl")
                    }
                }

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Acknowledgments")
        .navigationBarTitleDisplayMode(.inline)
        // No container identifier here: it would overwrite the identifiers of
        // `acknowledgments.fonts` / `.model` / `.ofl` inside. Same trap as the
        // root of `AddEntryView`.
    }

    private var fontAttribution: String {
        "Figtree, Lora, and Manrope are licensed under the SIL Open Font License, Version 1.1. Copyright 2022 The Figtree Project Authors; The Lora Project Authors; The Manrope Project Authors."
    }

    private var modelAttribution: String {
        """
        On-device voice uses Supertonic 3 model weights (OpenRAIL-M) and a vendored inference runtime from soniqo/speech-swift (Apache-2.0). Weights are bundled in this app and are not downloaded at runtime. Use of the voices is limited to reading your own journal — impersonation and deceptive synthetic speech are not permitted.
        """
    }

    private var oflText: String? {
        guard let url = Bundle.main.url(forResource: "OFL", withExtension: "txt") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

#Preview {
    NavigationStack {
        AcknowledgmentsView()
            .useTheme()
            .useTypography()
    }
}
