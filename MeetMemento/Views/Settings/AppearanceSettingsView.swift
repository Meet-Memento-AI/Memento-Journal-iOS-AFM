//
//  AppearanceSettingsView.swift
//  MeetMemento
//
//  Customize app theme and display settings
//

import SwiftUI

public struct AppearanceSettingsView: View {
    @Environment(\.theme) private var theme

    @State private var selectedTheme: AppThemePreference = .system

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Same SettingsSection + row chrome as Security / About / hub cards.
                SettingsSection(title: "Theme") {
                    ForEach(Array(AppThemePreference.allCases.enumerated()), id: \.element) { index, themeOption in
                        SettingsSelectableRow(
                            icon: iconForTheme(themeOption),
                            title: themeOption.displayName,
                            subtitle: descriptionForTheme(themeOption),
                            isSelected: selectedTheme == themeOption,
                            action: { selectTheme(themeOption) }
                        )

                        if index < AppThemePreference.allCases.count - 1 {
                            SettingsRowDivider()
                        }
                    }
                }

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCurrentTheme()
        }
    }

    // MARK: - Actions

    private func loadCurrentTheme() {
        selectedTheme = PreferencesService.shared.themePreference
    }

    private func selectTheme(_ themeOption: AppThemePreference) {
        selectedTheme = themeOption
        PreferencesService.shared.themePreference = themeOption
        NotificationCenter.default.post(name: .themePreferenceChanged, object: nil)
    }

    // MARK: - Helper Methods

    private func iconForTheme(_ themeOption: AppThemePreference) -> String {
        switch themeOption {
        case .system:
            return "gear"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    private func descriptionForTheme(_ themeOption: AppThemePreference) -> String {
        switch themeOption {
        case .system:
            return "Match your device settings"
        case .light:
            return "Always use light mode"
        case .dark:
            return "Always use dark mode"
        }
    }
}

#Preview("Light") {
    NavigationStack {
        AppearanceSettingsView()
            .useTheme()
            .useTypography()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        AppearanceSettingsView()
            .useTheme()
            .useTypography()
    }
    .preferredColorScheme(.dark)
}
