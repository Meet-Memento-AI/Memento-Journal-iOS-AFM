import Foundation

/// Gold turn-kind rows for RT1 (Study cast, stratified sample).
enum TurnKindGoldFixture {

    struct Row: Decodable, Equatable {
        let id: String
        let text: String
        let goldTurnKind: String
        let hasHistory: Bool
        let lastAssistantAskedQuestion: Bool
        let labelSource: String
        let intentId: String?
        let personaId: String?
        let arm: String?
        let move: String?
        let turnIndex: Int?
    }

    struct File: Decodable {
        let version: Int
        let source: String
        let study: String
        let rowCount: Int
        let labelling: String
        let rows: [Row]
    }

    enum LoadError: Error, CustomStringConvertible {
        case notFound
        case unsupportedVersion(Int)

        var description: String {
            switch self {
            case .notFound:
                return "turn-kind/cast-gold.json not found beside withMementoTests/Fixtures/"
            case .unsupportedVersion(let v):
                return "Unsupported cast-gold.json version \(v)"
            }
        }
    }

    static func fileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Eval
            .deletingLastPathComponent() // withMementoTests
            .appendingPathComponent("Fixtures/turn-kind/cast-gold.json")
    }

    static func load() throws -> File {
        let url = fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.notFound
        }
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        guard file.version == 1 else {
            throw LoadError.unsupportedVersion(file.version)
        }
        return file
    }

    static func goldTurnType(for row: Row) -> TurnType? {
        TurnType(rawValue: row.goldTurnKind)
    }
}
