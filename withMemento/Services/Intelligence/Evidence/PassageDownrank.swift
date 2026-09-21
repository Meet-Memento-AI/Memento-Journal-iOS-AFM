//
//  PassageDownrank.swift
//  MeetMemento
//
//  Spec 041 thumbs-down writes an on-device penalty keyed by passage hash.
//  Purged when the entry is deleted. Nothing leaves the device.
//

import CryptoKit
import Foundation

enum PassageDownrankStore {
    private static let defaultsKey = "memento.passageDownrank.v1"
    private static let penaltyPerHit = 0.25
    private static let penaltyCap = 0.75

    static func record(entryID: UUID, excerpt: String) {
        let hash = passageHash(excerpt)
        var map = load()
        var hashes = map[entryID.uuidString] ?? []
        if !hashes.contains(hash) { hashes.append(hash) }
        map[entryID.uuidString] = hashes
        save(map)
    }

    static func penalty(entryID: UUID) -> Double {
        let count = load()[entryID.uuidString]?.count ?? 0
        return min(penaltyCap, Double(count) * penaltyPerHit)
    }

    static func purge(entryID: UUID) {
        var map = load()
        map.removeValue(forKey: entryID.uuidString)
        save(map)
    }

    static func passageHash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func load() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String]] ?? [:]
    }

    private static func save(_ map: [String: [String]]) {
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }
}
