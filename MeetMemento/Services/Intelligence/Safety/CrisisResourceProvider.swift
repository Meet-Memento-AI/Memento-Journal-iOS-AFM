//
//  CrisisResourceProvider.swift
//  MeetMemento
//
//  Bundled, locale-keyed crisis resources — no network fetch (spec 026 / 019 R7).
//

import Foundation

struct CrisisResource: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let detail: String
    let url: URL?
}

struct CrisisResourceContent: Sendable, Equatable {
    let title: String
    let body: String
    let resources: [CrisisResource]
}

enum CrisisResourceProvider {

    private struct Payload: Decodable {
        let defaultLocale: String
        let locales: [String: LocaleBlock]
    }

    private struct LocaleBlock: Decodable {
        let title: String
        let body: String
        let resources: [ResourceRow]
    }

    private struct ResourceRow: Decodable {
        let name: String
        let detail: String
        let url: String?
    }

    private static let cached: CrisisResourceContent = {
        load() ?? fallback
    }()

    static var content: CrisisResourceContent { cached }

    private static var fallback: CrisisResourceContent {
        CrisisResourceContent(
            title: "You’re not alone",
            body: "If you’re in crisis or thinking about harming yourself, please talk to someone who can help right now. Memento is a journaling companion — not a crisis service.",
            resources: [
                CrisisResource(
                    id: "988",
                    name: "988 Suicide & Crisis Lifeline",
                    detail: "Call or text 988 (United States)",
                    url: URL(string: "tel:988")
                )
            ]
        )
    }

    private static func load() -> CrisisResourceContent? {
        guard let url = Bundle.main.url(forResource: "CrisisResources", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return nil
        }

        let preferred = Locale.current.identifier
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let block = payload.locales[preferred]
            ?? payload.locales["\(lang)-US"]
            ?? payload.locales[payload.defaultLocale]
            ?? payload.locales.values.first

        guard let block else { return nil }

        let resources = block.resources.enumerated().map { index, row in
            CrisisResource(
                id: "\(index)-\(row.name)",
                name: row.name,
                detail: row.detail,
                url: row.url.flatMap(URL.init(string:))
            )
        }
        return CrisisResourceContent(title: block.title, body: block.body, resources: resources)
    }
}
