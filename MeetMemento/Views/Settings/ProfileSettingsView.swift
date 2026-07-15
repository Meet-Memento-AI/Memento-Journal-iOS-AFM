//
//  ProfileSettingsView.swift
//  MeetMemento
//
//  Edit user profile information (name)
//

import SwiftUI

public struct ProfileSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String = ""
    @State private var showSuccessMessage: Bool = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Form section
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // First name
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("First name")
                            .font(type.body1)
                            .foregroundStyle(theme.foreground)
                            .fontWeight(.medium)

                        AppTextField(
                            placeholder: "Enter your first name",
                            text: $firstName,
                            textInputAutocapitalization: .words
                        )
                    }

                    // Last name
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Last name")
                            .font(type.body1)
                            .foregroundStyle(theme.foreground)
                            .fontWeight(.medium)

                        AppTextField(
                            placeholder: "Enter your last name",
                            text: $lastName,
                            textInputAutocapitalization: .words
                        )
                    }

                    // Save button
                    Button {
                        saveProfile()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save Changes")
                                    .font(type.body1Bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(canSave ? theme.primary : theme.mutedForeground.opacity(0.3))
                        .foregroundStyle(.white)
                        .cornerRadius(theme.radius.md)
                    }
                    .disabled(!canSave || isSaving)
                    .padding(.top, Spacing.xs)

                    // Success message
                    if showSuccessMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 14))
                            Text("Profile updated successfully")
                                .font(type.body2)
                                .foregroundStyle(.green)
                        }
                        .padding(Spacing.sm)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md))
                    }

                    // Error message
                    if !errorMessage.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(theme.destructive)
                                .font(.system(size: 14))
                            Text(errorMessage)
                                .font(type.body2)
                                .foregroundStyle(theme.destructive)
                        }
                        .padding(Spacing.sm)
                        .background(theme.destructive.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md))
                    }
                }

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Profile")
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
            loadCurrentProfile()
        }
    }

    // MARK: - Computed Properties

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        firstName.count <= 50 &&
        lastName.count <= 50 &&
        !isSaving
    }

    // MARK: - Actions

    private func loadCurrentProfile() {
        firstName = UserDefaults.standard.string(forKey: "memento_first_name") ?? ""
        lastName = UserDefaults.standard.string(forKey: "memento_last_name") ?? ""
    }

    private func saveProfile() {
        guard canSave else { return }

        isSaving = true
        errorMessage = ""
        showSuccessMessage = false

        let trimmedFirstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            // Simulate network delay for better UX
            try? await Task.sleep(nanoseconds: 500_000_000)

            UserDefaults.standard.set(trimmedFirstName, forKey: "memento_first_name")
            UserDefaults.standard.set(trimmedLastName, forKey: "memento_last_name")

            await MainActor.run {
                authViewModel.firstName = trimmedFirstName
                isSaving = false
                showSuccessMessage = true

                // Haptic feedback
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                // Dismiss after short delay
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    dismiss()
                }
            }
        }
    }
}

#Preview("Light") {
    NavigationStack {
        ProfileSettingsView()
            .useTheme()
            .useTypography()
            .environmentObject(AuthViewModel())
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        ProfileSettingsView()
            .useTheme()
            .useTypography()
            .environmentObject(AuthViewModel())
    }
    .preferredColorScheme(.dark)
}
