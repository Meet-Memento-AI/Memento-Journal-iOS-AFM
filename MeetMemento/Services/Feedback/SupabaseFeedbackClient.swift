//
//  SupabaseFeedbackClient.swift
//  MeetMemento
//
//  URLSession PostgREST client for spec 042. No supabase-swift.
//  Missing URL / anon key → not configured (callers no-op).
//

import Foundation

struct FeedbackSupabaseConfig: Equatable {
    let url: URL
    let anonKey: String

    static func fromBundle(_ bundle: Bundle = .main) -> FeedbackSupabaseConfig? {
        func cleaned(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if trimmed.hasPrefix("$(") { return nil }
            return trimmed
        }
        guard let urlString = cleaned("SUPABASE_URL"),
              let url = URL(string: urlString),
              let key = cleaned("SUPABASE_ANON_KEY") else {
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

        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            throw FeedbackClientError.invalidResponse(status: status)
        }
    }
}
