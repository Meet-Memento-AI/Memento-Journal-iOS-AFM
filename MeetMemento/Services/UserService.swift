
import Foundation
import Supabase

/// Service for managing user data in `public.users`.
class UserService {
    static let shared = UserService()
    
    private var client: SupabaseClient {
        SupabaseService.shared.client
    }
    
    /// Fetches the user profile for the current session.
    func getCurrentProfile() async throws -> UserProfile? {
        guard let userId = client.auth.currentUser?.id else { return nil }
        
        // Using DTO pattern similar to JournalService if dates are tricky, 
        // but let's try standard Codable first since UserProfile dates are simpler (createdAt).
        // If it fails, we fall back to DTO.
        let response: [UserProfile] = try await client
            .from("users")
            .select()
            .eq("id", value: userId)
            .execute()
            .value
            
        return response.first
    }
    
    /// Ensures that an entry exists in `public.users` for the authenticated user.
    /// If not, it creates one.
    func ensureUserExists(id: UUID, email: String) async throws {
        // 1. Check if exists
        let existing: [UserProfileDTO] = try await client
            .from("users")
            .select()
            .eq("id", value: id)
            .execute()
            .value
            
        if !existing.isEmpty {
            return // Already exists
        }
        
        // 2. Create if missing
        // Use DTO to handle dates safely
        let newProfileDTO = UserProfileDTO(
            id: id,
            email: email,
            full_name: nil,
            avatar_url: nil,
            onboarding_completed: false,
            created_at: ISO8601DateFormatter().string(from: Date()),
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        
        try await client
            .from("users")
            .insert(newProfileDTO)
            .execute()
            
        AppLogger.log("[UserService] Created new user profile")
    }

    /// Ensures user exists with OAuth profile data (Apple/Google Sign In).
    /// Creates user if missing, optionally updates name if provided for existing users.
    func ensureUserExistsWithProfile(
        id: UUID,
        email: String,
        fullName: String? = nil,
        avatarUrl: String? = nil
    ) async throws {
        // 1. Check if user exists
        let existing: [UserProfileDTO] = try await client
            .from("users")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        if let existingUser = existing.first {
            // User exists - optionally update name if provided and currently empty
            if let fullName = fullName, !fullName.isEmpty,
               (existingUser.full_name == nil || existingUser.full_name?.isEmpty == true) {
                try await client
                    .from("users")
                    .update(["full_name": fullName, "updated_at": ISO8601DateFormatter().string(from: Date())])
                    .eq("id", value: id)
                    .execute()
                AppLogger.log("[UserService] Updated user profile name")
            }
            return
        }

        // 2. Create new user with OAuth data
        let newProfileDTO = UserProfileDTO(
            id: id,
            email: email,
            full_name: fullName,
            avatar_url: avatarUrl,
            onboarding_completed: false,
            created_at: ISO8601DateFormatter().string(from: Date()),
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        try await client
            .from("users")
            .insert(newProfileDTO)
            .execute()

        AppLogger.log("[UserService] Created new OAuth user profile")
    }

    /// Checks if user has completed onboarding
    func hasCompletedOnboarding(userId: UUID) async throws -> Bool {
        struct OnboardingStatus: Codable {
            let onboarding_completed: Bool
        }

        let result: [OnboardingStatus] = try await client
            .from("users")
            .select("onboarding_completed")
            .eq("id", value: userId)
            .execute()
            .value

        return result.first?.onboarding_completed ?? false
    }

    // MARK: - Onboarding Persistence

    /// Updates the user's full name in the `users` table.
    func updateFullName(firstName: String, lastName: String) async throws {
        guard let userId = client.auth.currentUser?.id else { return }
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        try await client
            .from("users")
            .update(["full_name": fullName, "updated_at": iso8601Now()])
            .eq("id", value: userId)
            .execute()
    }

    /// Updates the user's goals and selected topics.
    func updateGoals(_ goals: [String]) async throws {
        guard let userId = client.auth.currentUser?.id else { return }
        let payload: [String: AnyJSON] = [
            "goals": .string(goals.joined(separator: ", ")),
            "selected_topics": .array(goals.map { .string($0) }),
            "updated_at": .string(iso8601Now())
        ]
        try await client
            .from("users")
            .update(payload)
            .eq("id", value: userId)
            .execute()
    }

    /// Marks onboarding as complete.
    func markOnboardingComplete() async throws {
        guard let userId = client.auth.currentUser?.id else { return }
        let payload: [String: AnyJSON] = [
            "onboarding_completed": .bool(true),
            "onboarding_completed_at": .string(iso8601Now()),
            "updated_at": .string(iso8601Now())
        ]
        try await client
            .from("users")
            .update(payload)
            .eq("id", value: userId)
            .execute()
    }

    /// Saves the personalization text to `user_profiles`.
    func savePersonalizationText(_ text: String) async throws {
        guard let userId = client.auth.currentUser?.id else { return }

        // Upsert into user_profiles
        let payload: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "onboarding_self_reflection": .string(text),
            "updated_at": .string(iso8601Now())
        ]
        try await client
            .from("user_profiles")
            .upsert(payload)
            .execute()
    }

    /// Fetches the personalization text from `user_profiles` for the current user.
    func getPersonalizationText() async throws -> String? {
        guard let userId = client.auth.currentUser?.id else { return nil }
        let result: [[String: String?]] = try await client
            .from("user_profiles")
            .select("onboarding_self_reflection")
            .eq("user_id", value: userId)
            .execute()
            .value
        return result.first?["onboarding_self_reflection"] ?? nil
    }

    // MARK: - Helpers

    private func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

// MARK: - DTO
struct UserProfileDTO: Codable {
    let id: UUID
    let email: String
    let full_name: String?
    let avatar_url: String?
    let onboarding_completed: Bool
    let created_at: String
    let updated_at: String
}
