//
//  AppearanceSettingsView.swift
//  MeetMemento
//
//  Customize app theme and display settings
//

import SwiftUI

public struct AppearanceSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTheme: AppThemePreference = .system

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Spacer(minLength: Spacing.md)

                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Appearance")
                        .font(type.h3)
                        .headerGradient()

                    Text("Customize how MeetMemento looks")
                        .font(type.body1)
                        .foregroundStyle(theme.mutedForeground)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xs)

                // Theme selector section
                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Theme")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.foreground)

                        Text("Choose your preferred color scheme")
                            .font(type.body2)
                            .foregroundStyle(theme.mutedForeground)
                    }
                    .padding(.horizontal, Spacing.md)

                    // Theme options card
                    VStack(spacing: 0) {
                        ForEach(AppThemePreference.allCases, id: \.self) { themeOption in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectTheme(themeOption)
                                }
                            } label: {
                                HStack(spacing: Spacing.md) {
                                    // Icon
                                    Image(systemName: iconForTheme(themeOption))
                                        .font(.system(size: 20))
                                        .foregroundStyle(theme.primary)
                                        .frame(width: 28, height: 28)

                                    // Title and description
                                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                                        Text(themeOption.displayName)
                                            .font(type.body1)
                                            .foregroundStyle(theme.foreground)

                                        Text(descriptionForTheme(themeOption))
                                            .font(.system(size: 14))
                                            .foregroundStyle(theme.mutedForeground)
                                    }

                                    Spacer()

                                    // Checkmark for selected
                                    if selectedTheme == themeOption {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(theme.primary)
                                    } else {
                                        Image(systemName: "circle")
                                            .font(.system(size: 20))
                                            .foregroundStyle(theme.mutedForeground.opacity(0.3))
                                    }
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.md)
                                .background(selectedTheme == themeOption ? theme.primary.opacity(0.08) : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            // Divider between options (not after last one)
                            if themeOption != AppThemePreference.allCases.last {
                                Divider()
                                    .background(theme.border)
                                    .padding(.horizontal, Spacing.md)
                            }
                        }
                    }
                    .background(sectionCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
                }
                .padding(.horizontal, Spacing.md)

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.top, Spacing.xs)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                IconButtonNav(
                    icon: "chevron.left",
                    iconSize: 18,
                    buttonSize: 40,
                    enableHaptic: true,
                    onTap: { dismiss() }
                )
            }
        }
        .onAppear {
            loadCurrentTheme()
        }
    }

    // MARK: - Glass Card Background

    @ViewBuilder
    private var sectionCardBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .mementoGlassEffect(.regular, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        } else {
            colorScheme == .dark ? GrayScale.gray800 : GrayScale.gray100
        }
    }

    // MARK: - Actions

    private func loadCurrentTheme() {
        selectedTheme = PreferencesService.shared.themePreference
    }

    private func selectTheme(_ themeOption: AppThemePreference) {
        selectedTheme = themeOption
        PreferencesService.shared.themePreference = themeOption

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
