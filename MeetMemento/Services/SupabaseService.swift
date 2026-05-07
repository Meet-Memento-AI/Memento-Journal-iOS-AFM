
import Foundation
import Supabase

private enum Environment {
    static let supabaseURLKey = "SUPABASE_URL"
    static let supabaseAnonKeyKey = "SUPABASE_ANON_KEY"

    static func value(forInfoDictionaryKey key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return nil
        }
        return trimmed
    }
}

/// Singleton service for Supabase client interaction.
/// Ensure you have added the 'supabase-swift' package dependency to your project.
class SupabaseService {
    static let shared = SupabaseService()

    /// Configuration error that occurred during initialization
    enum ConfigurationError: LocalizedError {
        case missingValue(String)
        case invalidSupabaseURL(String)

        var errorDescription: String? {
            switch self {
            case .missingValue(let key):
                return "Missing app configuration value for '\(key)'. Check your xcconfig and Info.plist setup."
            case .invalidSupabaseURL(let urlString):
                return "Invalid Supabase URL: '\(urlString)'. Check SUPABASE_URL in your xcconfig files."
            }
        }
    }

    // Configuration loaded from Info.plist values injected by xcconfig.
    private let supabaseUrl: URL
    private let supabaseKey: String

    /// The Supabase client. Access this safely using `getClient()` for error handling.
    let client: SupabaseClient

    /// Stores any configuration error that occurred during initialization
    private(set) var configurationError: ConfigurationError?

    /// Returns true if the service was initialized successfully
    var isConfiguredCorrectly: Bool { configurationError == nil }

    private init() {
        let configuredURLString = Environment.value(forInfoDictionaryKey: Environment.supabaseURLKey)
        let configuredAnonKey = Environment.value(forInfoDictionaryKey: Environment.supabaseAnonKeyKey)

        if let configuredAnonKey {
            self.supabaseKey = configuredAnonKey
        } else {
            self.supabaseKey = "invalid-anon-key"
            self.configurationError = .missingValue(Environment.supabaseAnonKeyKey)
        }

        // Validate URL - use a safe fallback if invalid to prevent crash
        if let configuredURLString, let url = URL(string: configuredURLString) {
            self.supabaseUrl = url
            if self.configurationError == nil {
                self.configurationError = nil
            }
        } else {
            // Log the error and use a placeholder URL to prevent crash
            // The configurationError will be checked by callers
            let badValue = configuredURLString ?? "<missing>"
            print("CRITICAL ERROR: Invalid or missing SUPABASE_URL in Info.plist/xcconfig: '\(badValue)'")
            self.supabaseUrl = URL(string: "https://invalid.supabase.co")!
            self.configurationError = self.configurationError ?? .invalidSupabaseURL(badValue)

            #if DEBUG
            // In debug builds, assert to catch configuration errors during development
            assertionFailure("Invalid Supabase configuration. Check SUPABASE_URL and SUPABASE_ANON_KEY in your xcconfig files.")
            #endif
        }

        self.client = SupabaseClient(
            supabaseURL: supabaseUrl,
            supabaseKey: supabaseKey,
            options: .init(
                auth: .init(
                    redirectToURL: URL(string: "memento://auth/callback")
                )
            )
        )
    }

    /// Returns the Supabase client, throwing if configuration failed
    func getClient() throws -> SupabaseClient {
        if let error = configurationError {
            throw error
        }
        return client
    }
}
