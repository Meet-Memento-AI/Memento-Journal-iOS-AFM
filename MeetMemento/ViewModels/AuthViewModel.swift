
//
//  AuthViewModel.swift
//  MeetMemento
//
//  Manages authentication state using Supabase.
//

import Foundation
import SwiftUI
import Supabase
import AuthenticationServices

/// Auth state enum for onboarding flow
enum AuthState: Equatable {
    case unauthenticated
    case authenticated(needsOnboarding: Bool)

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }
}

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasCompletedOnboarding = false
    @Published var authState: AuthState = .unauthenticated
    /// True only after `initializeAuth()` has finished (any branch). Root UI must not show Welcome/main until this is true.
    @Published var hasCheckedAuth = false
    @Published var isInitializing: Bool = true  // Busy during session restore (optional; root gates on `hasCheckedAuth`)

    // Pending profile from Apple Sign In (stub/flow)
    var pendingFirstName: String?
    var pendingLastName: String?

    private var client: SupabaseClient {
        SupabaseService.shared.client
    }

    private var isRunningAnyTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Restores session on app launch and checks onboarding status from DB.
    func initializeAuth() async {
        defer {
            self.isInitializing = false
            self.hasCheckedAuth = true
        }

        // Unit tests and UI tests should never require live Supabase bootstrap during app startup.
        if isRunningAnyTest {
            self.isAuthenticated = false
            self.hasCompletedOnboarding = false
            self.authState = .unauthenticated
            return
        }

        // UI tests: clear any persisted session so Welcome + stable IDs are reachable.
        let isUiTestRun =
            ProcessInfo.processInfo.arguments.contains("-UITesting")
            || ProcessInfo.processInfo.environment["MEETMEMENTO_UI_TEST"] == "1"
        if isUiTestRun {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { try? await self.client.auth.signOut() }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
                await group.next()
                group.cancelAll()
            }
            self.isAuthenticated = false
            self.hasCompletedOnboarding = false
            self.authState = .unauthenticated
            return
        }

        self.isInitializing = true

        // Check for inactivity timeout FIRST (14+ days of inactivity)
        if SecurityService.shared.shouldAutoLogout() {
            print("⏰ [Auth] Auto-logout triggered: 14+ days of inactivity")
            await performAutoLogout()
            return
        }

        do {
            let session = try await client.auth.session

            if let email = session.user.email {
                try? await UserService.shared.ensureUserExists(id: session.user.id, email: email)
            }

            let hasOnboarded = try await UserService.shared.hasCompletedOnboarding(userId: session.user.id)

            self.isAuthenticated = true
            self.hasCompletedOnboarding = hasOnboarded
            self.authState = .authenticated(needsOnboarding: !hasOnboarded)

            // Update activity timestamp on successful session restore
            SecurityService.shared.updateActivityTimestamp()

            print("✅ Supabase Session Restored: \(session.user.id), onboarded: \(hasOnboarded)")
        } catch {
            print("ℹ️ No active Supabase session found.")
            self.isAuthenticated = false
            self.hasCompletedOnboarding = false
            self.authState = .unauthenticated
        }
    }

    /// Performs auto-logout due to inactivity.
    private func performAutoLogout() async {
        try? await client.auth.signOut()
        SecurityService.shared.clearActivityTimestamp()

        self.isAuthenticated = false
        self.hasCompletedOnboarding = false
        self.authState = .unauthenticated
    }

    /// Explicitly check auth state (similar to initializeAuth, can range depending on logic)
    func checkAuthState() async {
        await initializeAuth()
    }

    /// Sends a magic link / OTP to the user's email
    func sendOTP(email: String) async throws {
        self.currentEmail = email
        // Using Email OTP (Magic Link logic can differ, standard is OTP)
        try await client.auth.signInWithOTP(email: email)
        print("✅ OTP sent to \(email)")
    }

    /// Verifies the OTP code and dynamically checks DB for onboarding status.
    func verifyOTP(email: String, code: String) async throws {
        let session = try await client.auth.verifyOTP(
            email: email,
            token: code,
            type: .email
        )

        do {
            try await UserService.shared.ensureUserExists(id: session.user.id, email: email)
        } catch {
            print("⚠️ Failed to ensure user profile exists: \(error)")
        }

        let hasOnboarded = try await UserService.shared.hasCompletedOnboarding(userId: session.user.id)

        try? await Task.sleep(nanoseconds: 300_000_000)

        self.isAuthenticated = true
        self.hasCompletedOnboarding = hasOnboarded
        self.authState = .authenticated(needsOnboarding: !hasOnboarded)

        // Update activity timestamp on successful sign-in
        SecurityService.shared.updateActivityTimestamp()
    }

    var currentEmail: String?

    func verifyOTP(code: String) async throws {
        guard let email = currentEmail else {
            throw AuthError.missingEmail
        }
        try await verifyOTP(email: email, code: code)
    }

    func signOut() async {
        try? await client.auth.signOut()
        SecurityService.shared.clearActivityTimestamp()
        self.isAuthenticated = false
        self.hasCompletedOnboarding = false
        self.authState = .unauthenticated
    }

    func storePendingAppleProfile(firstName: String, lastName: String) {
        pendingFirstName = firstName
        pendingLastName = lastName
    }

    func clearPendingProfile() {
        pendingFirstName = nil
        pendingLastName = nil
    }

    /// Bypass authentication for development/testing purposes
    func bypassToMainApp() {
        self.isAuthenticated = true
        self.hasCompletedOnboarding = true
        self.authState = .authenticated(needsOnboarding: false)
        self.hasCheckedAuth = true
        self.isInitializing = false
    }

    /// Skip to onboarding flow for UI testing (no real auth session).
    func skipToOnboardingForTesting() {
        self.isAuthenticated = true
        self.hasCompletedOnboarding = false
        self.authState = .authenticated(needsOnboarding: true)
        self.hasCheckedAuth = true
        self.isInitializing = false
    }

    func updateProfile(firstName: String, lastName: String) async throws {
        let attributes = UserAttributes(data: [
            "full_name": .string("\(firstName) \(lastName)")
        ])
        _ = try await client.auth.update(user: attributes)
        try await UserService.shared.updateFullName(firstName: firstName, lastName: lastName)
    }

    // MARK: - Apple Sign In

    /// Signs in with Apple using native AuthenticationServices
    func signInWithApple() async throws {
        let appleResult = try await AppleSignInService.shared.signIn()

        let session = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: appleResult.idToken,
                nonce: appleResult.nonce
            )
        )

        let email = appleResult.email ?? session.user.email ?? ""
        try await UserService.shared.ensureUserExistsWithProfile(
            id: session.user.id,
            email: email,
            fullName: appleResult.fullName
        )

        // Preserve Apple-provided name for YourNameView pre-fill (Apple only sends it once)
        if let fullName = appleResult.fullName, !fullName.isEmpty {
            let parts = fullName.split(separator: " ", maxSplits: 1)
            pendingFirstName = String(parts.first ?? "")
            pendingLastName = parts.count > 1 ? String(parts.last ?? "") : nil
        }

        let hasOnboarded = try await UserService.shared.hasCompletedOnboarding(userId: session.user.id)

        try? await Task.sleep(nanoseconds: 300_000_000)

        self.isAuthenticated = true
        self.hasCompletedOnboarding = hasOnboarded
        self.authState = .authenticated(needsOnboarding: !hasOnboarded)

        // Update activity timestamp on successful sign-in
        SecurityService.shared.updateActivityTimestamp()

        print("✅ Apple Sign In successful for user: \(session.user.id)")
    }

    // MARK: - Google Sign In

    /// Signs in with Google using the SDK's built-in ASWebAuthenticationSession flow
    func signInWithGoogle() async throws {
        let session = try await client.auth.signInWithOAuth(
            provider: .google
        ) { (session: ASWebAuthenticationSession) in
            session.prefersEphemeralWebBrowserSession = false
        }

        let email = session.user.email ?? ""
        let fullName = session.user.userMetadata["full_name"]?.stringValue

        try await UserService.shared.ensureUserExistsWithProfile(
            id: session.user.id,
            email: email,
            fullName: fullName
        )

        let hasOnboarded = try await UserService.shared.hasCompletedOnboarding(userId: session.user.id)

        try? await Task.sleep(nanoseconds: 300_000_000)

        self.isAuthenticated = true
        self.hasCompletedOnboarding = hasOnboarded
        self.authState = .authenticated(needsOnboarding: !hasOnboarded)

        // Update activity timestamp on successful sign-in
        SecurityService.shared.updateActivityTimestamp()

        print("✅ Google Sign In successful for user: \(session.user.id)")
    }

    /// Deletes the user's account and all associated data
    func deleteAccount() async throws {
        guard let userId = client.auth.currentUser?.id else {
            throw AuthError.notAuthenticated
        }

        // Try to call the delete_user() RPC (deletes auth.users and cascades)
        do {
            try await client.rpc("delete_user").execute()
            print("✅ [Auth] User deleted via RPC")
        } catch {
            // Fallback: manually delete app data if RPC fails
            print("⚠️ [Auth] RPC failed, falling back to manual deletion: \(error)")

            // Delete chat data first (foreign key order)
            _ = try? await client
                .from("chat_messages")
                .delete()
                .eq("user_id", value: userId)
                .execute()

            _ = try? await client
                .from("chat_sessions")
                .delete()
                .eq("user_id", value: userId)
                .execute()

            // Delete journal entries
            _ = try? await client
                .from("journal_entries")
                .delete()
                .eq("user_id", value: userId)
                .execute()

            // Delete user profile
            _ = try? await client
                .from("users")
                .delete()
                .eq("id", value: userId)
                .execute()

            // Note: auth.users cannot be deleted without service_role or RPC
            // User data is cleaned up, but auth identity persists
        }

        // Sign out
        try await client.auth.signOut()

        // Clear local data
        UserDefaults.standard.removeObject(forKey: "memento_first_name")
        UserDefaults.standard.removeObject(forKey: "memento_last_name")
        SecurityService.shared.clearAll()
        LocalJournalStorage.shared.clearAll()

        // Update state
        await MainActor.run {
            self.isAuthenticated = false
            self.authState = .unauthenticated
            self.hasCompletedOnboarding = false
        }
    }
}

extension AuthViewModel {
    /// SwiftUI previews for screens that expect `initializeAuth()` to have finished without running it.
    static func previewAuthReadyForWelcome() -> AuthViewModel {
        let vm = AuthViewModel()
        vm.hasCheckedAuth = true
        vm.isInitializing = false
        return vm
    }
}

enum AuthError: LocalizedError {
    case missingEmail
    case notAuthenticated
    case oauthFailed(String)
    case appleSignInFailed(String)
    case googleSignInFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingEmail:
            return "Email is required"
        case .notAuthenticated:
            return "Not authenticated"
        case .oauthFailed(let message):
            return "OAuth failed: \(message)"
        case .appleSignInFailed(let message):
            return "Apple Sign In failed: \(message)"
        case .googleSignInFailed(let message):
            return "Google Sign In failed: \(message)"
        }
    }
}
