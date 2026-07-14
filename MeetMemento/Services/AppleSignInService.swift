//
//  AppleSignInService.swift
//  MeetMemento
//
//  Handles Apple Sign In using AuthenticationServices framework.
//  Generates cryptographic nonce for security and manages ASAuthorizationController.
//

import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Result from Apple Sign In containing credential data for Supabase
struct AppleSignInResult {
    let idToken: String
    let nonce: String
    let email: String?
    let fullName: String?
}

/// Service for handling Apple Sign In authentication
@MainActor
class AppleSignInService: NSObject, ObservableObject {
    static let shared = AppleSignInService()

    private var currentNonce: String?
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?

    private override init() {
        super.init()
    }

    /// Initiates Apple Sign In flow and returns credential data
    func signIn() async throws -> AppleSignInResult {
        // Generate cryptographic nonce
        let nonce = try generateNonce()
        currentNonce = nonce

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)

            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.presentationContextProvider = self
            authorizationController.performRequests()
        }
    }

    /// Returns the current unhashed nonce for Supabase verification
    func getCurrentNonce() -> String? {
        return currentNonce
    }

    // MARK: - Nonce Generation

    /// Generates a random string for use as a nonce
    /// - Throws: AppleSignInError.nonceGenerationFailed if secure random bytes cannot be generated
    private func generateNonce(length: Int = 32) throws -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            throw AppleSignInError.nonceGenerationFailed(errorCode)
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }

    /// SHA256 hash of the nonce string
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                continuation?.resume(throwing: AppleSignInError.invalidCredential)
                continuation = nil
                return
            }

            guard let identityTokenData = appleIDCredential.identityToken,
                  let idToken = String(data: identityTokenData, encoding: .utf8) else {
                continuation?.resume(throwing: AppleSignInError.missingIdentityToken)
                continuation = nil
                return
            }

            guard let nonce = currentNonce else {
                continuation?.resume(throwing: AppleSignInError.missingNonce)
                continuation = nil
                return
            }

            // Extract name (only provided on first sign-in)
            var fullName: String? = nil
            if let givenName = appleIDCredential.fullName?.givenName {
                if let familyName = appleIDCredential.fullName?.familyName {
                    fullName = "\(givenName) \(familyName)"
                } else {
                    fullName = givenName
                }
            }

            let result = AppleSignInResult(
                idToken: idToken,
                nonce: nonce,
                email: appleIDCredential.email,
                fullName: fullName
            )

            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    continuation?.resume(throwing: AppleSignInError.canceled)
                case .failed:
                    continuation?.resume(throwing: AppleSignInError.failed)
                case .invalidResponse:
                    continuation?.resume(throwing: AppleSignInError.invalidResponse)
                case .notHandled:
                    continuation?.resume(throwing: AppleSignInError.notHandled)
                case .unknown:
                    continuation?.resume(throwing: AppleSignInError.unknown)
                case .notInteractive:
                    continuation?.resume(throwing: AppleSignInError.notInteractive)
                case .matchedExcludedCredential:
                    continuation?.resume(throwing: AppleSignInError.matchedExcludedCredential)
                 case .credentialImport, .credentialExport:
                    // These are passkey-related errors not applicable to Sign in with Apple
                    continuation?.resume(throwing: AppleSignInError.failed)
                default:
                    continuation?.resume(throwing: error)
                }
            } else {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Get the key window for presentation on main thread
        return MainActor.assumeIsolated {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first else {
                return UIWindow()
            }
            return window
        }
    }
}

// MARK: - Errors

enum AppleSignInError: LocalizedError {
    case invalidCredential
    case missingIdentityToken
    case missingNonce
    case nonceGenerationFailed(OSStatus)
    case canceled
    case failed
    case invalidResponse
    case notHandled
    case unknown
    case notInteractive
    case matchedExcludedCredential

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid Apple credential received"
        case .missingIdentityToken:
            return "Apple identity token is missing"
        case .missingNonce:
            return "Security nonce is missing"
        case .nonceGenerationFailed(let status):
            return "Failed to generate secure nonce (OSStatus: \(status))"
        case .canceled:
            return "Sign in was canceled"
        case .failed:
            return "Sign in failed"
        case .invalidResponse:
            return "Invalid response from Apple"
        case .notHandled:
            return "Request was not handled"
        case .unknown:
            return "An unknown error occurred"
        case .notInteractive:
            return "Non-interactive sign in not available"
        case .matchedExcludedCredential:
            return "Credential was excluded"
        }
    }
}
