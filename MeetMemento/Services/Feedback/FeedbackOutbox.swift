//
//  FeedbackOutbox.swift
//  MeetMemento
//
//  Durable queue for spec 042 verification uploads. Application Support JSON,
//  lock + write-behind, complete file protection. Retries keep clientEventID.
//

import Foundation

struct FeedbackOutboxItem: Codable, Equatable {
    let envelope: FeedbackEnvelope
    var attempts: Int
    var nextAttemptAt: Date

    var clientEventID: UUID { envelope.clientEventID }
}

final class FeedbackOutbox: @unchecked Sendable {
    static let maxEntries = 500

    private let lock = NSLock()
    private let fileURL: URL
    private let writeQueue: DispatchQueue
    private var cache: [FeedbackOutboxItem]?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MementoFeedback", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("verification-outbox.json")
        writeQueue = DispatchQueue(label: "com.meetmemento.FeedbackOutbox.write", qos: .utility)
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return cached().count
    }

    func enqueue(_ envelope: FeedbackEnvelope) {
        lock.lock(); defer { lock.unlock() }
        var items = cached()
        if items.contains(where: { $0.clientEventID == envelope.clientEventID }) {
            return
        }
        items.append(FeedbackOutboxItem(envelope: envelope, attempts: 0, nextAttemptAt: Date()))
        if items.count > Self.maxEntries {
            items.removeFirst(items.count - Self.maxEntries)
        }
        cache = items
        scheduleWrite(items)
    }

    func pending(now: Date = Date()) -> [FeedbackOutboxItem] {
        lock.lock(); defer { lock.unlock() }
        return cached().filter { $0.nextAttemptAt <= now }
    }

    func markSucceeded(clientEventID: UUID) {
        lock.lock(); defer { lock.unlock() }
        var items = cached()
        items.removeAll { $0.clientEventID == clientEventID }
        cache = items
        scheduleWrite(items)
    }

    func markFailed(clientEventID: UUID, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var items = cached()
        guard let index = items.firstIndex(where: { $0.clientEventID == clientEventID }) else { return }
        items[index].attempts += 1
        let delay = min(pow(2.0, Double(items[index].attempts)), 300)
        items[index].nextAttemptAt = now.addingTimeInterval(delay)
        cache = items
        scheduleWrite(items)
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        cache = []
        writeQueue.sync { [fileURL] in
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func flush() {
        writeQueue.sync {}
    }

    // MARK: - Private

    private func cached() -> [FeedbackOutboxItem] {
        if let cache { return cache }
        let loaded = loadFromDisk()
        cache = loaded
        return loaded
    }

    private func loadFromDisk() -> [FeedbackOutboxItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? decoder.decode([FeedbackOutboxItem].self, from: data) else {
            return []
        }
        return items
    }

    private func scheduleWrite(_ items: [FeedbackOutboxItem]) {
        let url = fileURL
        let encoder = encoder
        writeQueue.async {
            guard let data = try? encoder.encode(items) else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
}
