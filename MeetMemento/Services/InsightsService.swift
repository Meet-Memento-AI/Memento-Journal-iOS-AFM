import Foundation
import Supabase

// MARK: - Request Payload Types

/// Matches Edge Function's JournalEntry interface
private struct JournalEntryPayload: Codable {
    let date: String
    let title: String
    let content: String
    let word_count: Int
}

/// Request body for generate-insights Edge Function
private struct GenerateInsightsRequest: Codable {
    let entries: [JournalEntryPayload]
}

class InsightsService {
    static let shared = InsightsService()
    
    private var client: SupabaseClient {
        SupabaseService.shared.client
    }
    
    /// Fetches the latest valid insight for the current user.
    func fetchLatestInsight() async throws -> UserInsight? {
        guard let userId = client.auth.currentUser?.id else { return nil }
        
        let response: [UserInsight] = try await client
            .from("user_insights")
            .select() // Select all fields
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
            
        return response.first
    }
    
    /// Generates a new insight by calling the Supabase Edge Function 'generate-insight'.
    /// This keeps the Gemini API key secure on the server.
    func generateInsight(entries: [Entry]) async throws -> UserInsight {
        guard let userId = client.auth.currentUser?.id else {
            throw AuthError.missingEmail
        }
        
                AppLogger.log("🔍 [InsightsService] Starting insight generation for \(entries.count) entries")
        
        // 1. Prepare Payload
        // Format must match Edge Function's JournalEntry interface
        // Filter out entries with empty content to prevent validation errors
        let validEntries = entries.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !validEntries.isEmpty else {
                        AppLogger.log("❌ [InsightsService] No valid entries with content")
            throw NSError(domain: "InsightsService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No entries with content to analyze"])
        }

        let payloadEntries = validEntries.map { entry in
            JournalEntryPayload(
                date: ISO8601DateFormatter().string(from: entry.createdAt),
                title: entry.title.isEmpty ? "Untitled" : entry.title,
                content: entry.text,
                word_count: entry.text.split(separator: " ").count
            )
        }

        let requestBody = GenerateInsightsRequest(entries: payloadEntries)

                AppLogger.log("🔍 [InsightsService] Payload prepared: \(payloadEntries.count) entries")

        AppLogger.log("[InsightsService] Request payload prepared")

        do {
            // 2. Invoke Edge Function
                        AppLogger.log("🔍 [InsightsService] Calling Edge Function...")

            // The invoke method with a generic type parameter returns the decoded response
            let content: InsightContent = try await client.functions.invoke(
                "generate-insights",
                options: FunctionInvokeOptions(body: requestBody)
            )

                        AppLogger.log("✅ [InsightsService] Successfully decoded InsightContent")
            AppLogger.log("   - Headline: \(content.headline)")
            AppLogger.log("   - Themes: \(content.themes ?? [])")
            AppLogger.log("   - Suggestions: \(content.suggestions ?? [])")

            // 3. Wrap in UserInsight model for the UI
            let newInsight = UserInsight(
                userId: userId,
                insightType: "ai_generated",
                content: try InsightContent.encodeToJSONMap(content),
                entriesAnalyzedCount: entries.count
            )

                        AppLogger.log("✅ [InsightsService] UserInsight created successfully")
            return newInsight
            
        } catch let decodingError as DecodingError {
            #if DEBUG
            AppLogger.log("❌ [InsightsService] Decoding error: \(decodingError)")
            switch decodingError {
            case .keyNotFound(let key, let context):
                AppLogger.log("   - Missing key: \(key.stringValue)")
                AppLogger.log("   - Context: \(context.debugDescription)")
            case .typeMismatch(let type, let context):
                AppLogger.log("   - Type mismatch: expected \(type)")
                AppLogger.log("   - Context: \(context.debugDescription)")
            case .valueNotFound(let type, let context):
                AppLogger.log("   - Value not found: \(type)")
                AppLogger.log("   - Context: \(context.debugDescription)")
            case .dataCorrupted(let context):
                AppLogger.log("   - Data corrupted: \(context.debugDescription)")
            @unknown default:
                AppLogger.log("   - Unknown decoding error")
            }
            #endif
            throw decodingError
        } catch {
            #if DEBUG
            AppLogger.log("❌ [InsightsService] Error: \(error)")
            AppLogger.log("   - Error type: \(type(of: error))")
            AppLogger.log("   - Error description: \(error.localizedDescription)")

            // Extract response data from FunctionsError.httpError tuple
            let mirror = Mirror(reflecting: error)
            for child in mirror.children {
                if child.label == "httpError" {
                    // httpError is a tuple (code: Int, data: Data)
                    let tupleMirror = Mirror(reflecting: child.value)
                    for tupleChild in tupleMirror.children {
                        if let data = tupleChild.value as? Data {
                            if let responseString = String(data: data, encoding: .utf8) {
                                AppLogger.log("   - 📋 SERVER RESPONSE: \(responseString)")
                            } else {
                                AppLogger.log("   - 📋 SERVER RESPONSE (hex): \(data.map { String(format: "%02x", $0) }.joined())")
                            }
                        }
                    }
                }
            }
            #endif

            throw error
        }
    }
}

// Helper extension to encode typed content to JSON dictionary for the generic model
extension InsightContent {
    static func encodeToJSONMap(_ content: InsightContent) throws -> [String: AnyCodable] {
        var map: [String: AnyCodable] = [:]
        map["headline"] = AnyCodable(content.headline)
        map["observation"] = AnyCodable(content.observation)

        if let observationExtended = content.observationExtended {
            map["observationExtended"] = AnyCodable(observationExtended)
        }

        if let themes = content.themes {
            map["themes"] = AnyCodable(themes.map { AnyCodable($0) })
        }

        if let suggestions = content.suggestions {
            map["suggestions"] = AnyCodable(suggestions.map { AnyCodable($0) })
        }

        if let sentiment = content.sentiment {
            let sentimentMaps = sentiment.map { s -> [String: AnyCodable] in
                return ["label": AnyCodable(s.label), "score": AnyCodable(s.score)]
            }
            map["sentiment"] = AnyCodable(sentimentMaps.map { AnyCodable($0) })
        }

        if let keywords = content.keywords {
            map["keywords"] = AnyCodable(keywords.map { AnyCodable($0) })
        }

        if let questions = content.questions {
            map["questions"] = AnyCodable(questions.map { AnyCodable($0) })
        }

        return map
    }
}
