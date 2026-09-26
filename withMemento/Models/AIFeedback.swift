
import Foundation

/// Represents user feedback on AI content from the `ai_feedback` table.
public struct AIFeedback: Identifiable, Codable, Hashable {
    public let id: UUID
    public let userId: UUID
    public let targetId: UUID
    public let targetType: String // 'insight', 'followup', 'summary'
    public var rating: Int? // 1-5
    public var isHelpful: Bool?
    public var userComment: String?
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case targetId = "target_id"
        case targetType = "target_type"
        case rating
        case isHelpful = "is_helpful"
        case userComment = "user_comment"
        case createdAt = "created_at"
    }

    public init(
        id: UUID = UUID(),
        userId: UUID,
        targetId: UUID,
        targetType: String,
        rating: Int? = nil,
        isHelpful: Bool? = nil,
        userComment: String? = nil,
        createdAt: Date? = Date()
    ) {
        self.id = id
        self.userId = userId
        self.targetId = targetId
        self.targetType = targetType
        self.rating = rating
        self.isHelpful = isHelpful
        self.userComment = userComment
        self.createdAt = createdAt
    }
}

// MARK: - Mocks
extension AIFeedback {
    public static let mock = AIFeedback(
        userId: UUID(),
        targetId: UUID(),
        targetType: "insight",
        rating: 5,
        isHelpful: true,
        userComment: "Very accurate!"
    )
}
