//
//  AudioAssetStore.swift
//  MeetMemento
//
//  Spec 015 R5 / DEC-007: original capture audio as files in the app
//  container, never SwiftData blobs. Default retention is discard-after
//  transcription.
//

import Foundation

enum AudioRetention: String, Codable, CaseIterable, Sendable {
    case discardAfterTranscription
    case keepThirtyDays
    case keepForever
}

enum AudioRetentionPolicy {
    static let defaultRetention: AudioRetention = .discardAfterTranscription

    private static let retentionKey = "audioRetention"

    static var current: AudioRetention {
        get {
            let raw = UserDefaults.standard.string(forKey: retentionKey)
            return AudioRetention(rawValue: raw ?? "") ?? defaultRetention
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: retentionKey)
        }
    }
}

enum AudioAssetStore {
    static let directoryName = "AudioAssets"

    static var directoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(directoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func fileURL(assetID: String) -> URL {
        directoryURL.appendingPathComponent(assetID)
    }

    static func save(_ data: Data, assetID: String = UUID().uuidString) throws -> String {
        let url = fileURL(assetID: assetID)
        try data.write(to: url, options: .completeFileProtection)
        return assetID
    }

    static func delete(assetID: String) {
        let url = fileURL(assetID: assetID)
        try? FileManager.default.removeItem(at: url)
    }

    static func exists(assetID: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(assetID: assetID).path)
    }

    /// DEC-007 default: drop the file once words exist.
    static func applyRetentionAfterTranscription(assetID: String?) -> String? {
        guard let assetID else { return nil }
        switch AudioRetentionPolicy.current {
        case .discardAfterTranscription:
            delete(assetID: assetID)
            return nil
        case .keepThirtyDays, .keepForever:
            return assetID
        }
    }

    static func sweepExpired(now: Date = Date(), maxAge: TimeInterval = 30 * 24 * 3600) {
        guard AudioRetentionPolicy.current == .keepThirtyDays else { return }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        for url in items {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? now
            if now.timeIntervalSince(modified) > maxAge {
                try? fm.removeItem(at: url)
            }
        }
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directoryURL)
        _ = directoryURL
    }

    static var isEmpty: Bool {
        let items = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        return (items ?? []).isEmpty
    }
}
