
import Foundation
import Supabase

private enum Environment {
    static let supabaseURLKey = "SUPABASE_URL"
    static let supabaseAnonKeyKey = "SUPABASE_ANON_KEY"

    private static let placeholderValues: Set<String> = [
        "https://YOUR_PROJECT_ID.supabase.co",
        "YOUR_SUPABASE_ANON_KEY",
        "your-supabase-anon-key"
    ]

    static func value(forInfoDictionaryKey key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        var normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\/", with: "/")

        if normalized.hasPrefix("\"") && normalized.hasSuffix("\"") && normalized.count >= 2 {
            normalized.removeFirst()
            normalized.removeLast()
            normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !normalized.isEmpty, !normalized.hasPrefix("$(") else {
            return nil
        }

        if placeholderValues.contains(normalized) {
            return nil
        }

        return normalized
    }
}

/// Singleton service for Supabase client interaction.
/// Ensure you have added the 'supabase-swift' package dependency to your project.
class SupabaseService {
    static let shared = SupabaseService()

    // Supabase client initialization may parse JWT claims from anon key.
    // Use a structurally valid placeholder to avoid fatal crashes when local config is missing.
    private static let fallbackAnonJWT = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxvY2FsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDAwMDAwMDAsImV4cCI6MjAwMDAwMDAwMH0.c2lnbmF0dXJl"

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
            self.supabaseKey = Self.fallbackAnonJWT
            self.configurationError = .missingValue(Environment.supabaseAnonKeyKey)
        }

                // Validate URL - use a safe fallback if invalid to prevent crash.
                // URL(string:) accepts values like "https:" (no host), so we require
                // both an http/https scheme and a host component.
                  if let configuredURLString,
                      let url = URL(string: configuredURLString),
                     let scheme = url.scheme?.lowercased(),
                     ["http", "https"].contains(scheme),
                     url.host != nil {
            self.supabaseUrl = url
            if self.configurationError == nil {
                self.configurationError = nil
            }
        } else {
            // Log the error and use a placeholder URL to prevent crash
            // The configurationError will be checked by callers
            let badValue = configuredURLString ?? "<missing>"
            AppLogger.log("[SupabaseService] Invalid or missing SUPABASE_URL: '\(badValue)'", type: .error)
            self.supabaseUrl = URL(string: "https://invalid.supabase.co")!
            self.configurationError = self.configurationError ?? .invalidSupabaseURL(badValue)

            AppLogger.log("[SupabaseService] Check SUPABASE_URL and SUPABASE_ANON_KEY in your local xcconfig files.", type: .error)
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

        // spec-006 R3: surface misconfiguration immediately during development.
        // A misconfigured Release can't even be built (the Release build-phase gate
        // blocks a placeholder SUPABASE_URL); at runtime auth degrades to
        // an unauthenticated state. This assertion just shortens the dev feedback loop.
        #if DEBUG
        if let configurationError,
           ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
           NSClassFromString("XCTestCase") == nil {
            assertionFailure("Supabase misconfigured: \(configurationError.localizedDescription). Set MeetMemento/Config/Debug.local.xcconfig.")
        }
        #endif
    }

    /// Returns the Supabase client, throwing if configuration failed
    func getClient() throws -> SupabaseClient {
        if let error = configurationError {
            throw error
        }
        return client
    }
}
