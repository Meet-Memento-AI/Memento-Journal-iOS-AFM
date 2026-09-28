//
//  SupabaseFeedbackClient.swift
//  withMemento
//
//  URLSession PostgREST client for spec 042. No supabase-swift.
//  Missing URL / anon key → not configured (callers no-op).
//

import Foundation

struct FeedbackSupabaseConfig: Equatable {
    let url: URL
    let anonKey: String

    static func fromBundle(_ bundle: Bundle = .main) -> FeedbackSupabaseConfig? {
        resolve(
            urlString: bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            anonKey: bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String
        )
    }

    /// Pure so the rules below are testable without rebuilding the app against
    /// different xcconfig values — which is how the `https:` truncation bug went
    /// unnoticed: nothing could exercise the parsing without a full build.
    static func resolve(urlString: String?, anonKey: String?) -> FeedbackSupabaseConfig? {
        func cleaned(_ raw: String?) -> String? {
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            // An unexpanded build variable means the xcconfig never supplied one.
            if trimmed.hasPrefix("$(") { return nil }
            return trimmed
        }
        guard let urlString = cleaned(urlString),
              let url = URL(string: urlString),
              let key = cleaned(anonKey) else {
            return nil
        }
        // A host is required, not merely a parseable URL. `URL(string: "https:")`
        // succeeds, so without this the app reports itself CONFIGURED and then
        // fails every upload against a scheme-only endpoint — silently, because
        // the outbox just retries. That exact value is what an xcconfig produces
        // from a literal `https://host` line, since `//` starts a comment there
        // (see Config/Supabase.xcconfig.example). Fail closed instead.
        guard url.scheme != nil, let host = url.host, !host.isEmpty else {
            return nil
        }
        return FeedbackSupabaseConfig(url: url, anonKey: key)
    }
}

protocol FeedbackSubmitting: AnyObject {
    var isConfigured: Bool { get }
    func submit(_ envelope: FeedbackEnvelope) async throws
    func erase(deviceID: UUID) async throws
}

enum FeedbackClientError: Error, Equatable {
    case notConfigured
    case invalidResponse(status: Int)
}

final class SupabaseFeedbackClient: FeedbackSubmitting, @unchecked Sendable {
    let config: FeedbackSupabaseConfig?
    private let session: URLSession
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    var isConfigured: Bool { config != nil }

    init(config: FeedbackSupabaseConfig? = FeedbackSupabaseConfig.fromBundle(),
         session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func submit(_ envelope: FeedbackEnvelope) async throws {
        try await post(rpc: "submit_device_feedback", jsonObject: ["payload": encodeJSONObject(envelope)])
    }

    func erase(deviceID: UUID) async throws {
        try await post(rpc: "erase_device_feedback", jsonObject: ["device_id": deviceID.uuidString])
    }

    // MARK: - Private

    private func encodeJSONObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func post(rpc: String, jsonObject: [String: Any]) async throws {
        guard let config else { throw FeedbackClientError.notConfigured }
        let endpoint = config.url
            .appendingPathComponent("rest/v1/rpc")
            .appendingPathComponent(rpc)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonObject)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            AppLogger.log(
                "⚠️ [Feedback] RPC \(rpc) HTTP \(status) \(body.prefix(240))",
                category: AppLogger.network
            )
            throw FeedbackClientError.invalidResponse(status: status)
        }
    }
}
