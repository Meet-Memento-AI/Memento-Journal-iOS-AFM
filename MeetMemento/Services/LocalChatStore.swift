//
//  LocalChatStore.swift
//  MeetMemento
//
//  On-device persistence for chat sessions and messages, replacing the former
//  server chat tables. Turns used to be persisted server-side; with native
//  on-device chat there is no server, so multiple chat windows (create / list /
//  switch / delete / persist across launches) live here.
//
//  Stored as JSON under Application Support with complete file protection
//  (device-encrypted at rest — no PIN required). Uses its own Codable DTOs so it
//  doesn't depend on ChatSession's server-oriented (asymmetric) Codable.
//
//  Spec 029 R3: reads are memory-cached per launch (the chat send path used to
//  re-read and re-decode the whole transcript file on every send) and writes
//  are write-behind on a serial queue (each append used to read-modify-rewrite
//  the whole file inline, gating the `.final` event the UI waits on). Mutations
//  update the cache synchronously under the lock — readers always see the
//  latest state — while the disk write happens behind on `writeQueue`, whose
//  FIFO order preserves write order. `flush()` drains it (app background).
//

import Foundation

final class LocalChatStore: @unchecked Sendable {
    static let shared = LocalChatStore()

    private let lock = NSLock()
    private let rootDirectory: URL
    private let sessionsFile: URL
    private let messagesDirectory: URL

    /// Serial write-behind queue: preserves mutation order, keeps file I/O off
    /// the send path. Each block writes a full snapshot taken under the lock,
    /// so a later block strictly supersedes an earlier one.
    private let writeQueue = DispatchQueue(label: "com.meetmemento.LocalChatStore.write", qos: .utility)

    /// nil until first load; then the source of truth for the launch.
    private var sessionsCache: [StoredSession]?
    /// Message arrays for conversations touched this launch. Bounded by the
    /// number of conversations the user opens per launch (small).
    private var messagesCache: [UUID: [StoredMessage]] = [:]

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        // Compact on purpose (spec 029 R3): pretty-printing + key sorting was
        // pure write-path cost; the files are app-internal, not documentation.
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// `directory` is injectable for tests; defaults to Application Support.
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MementoChat", isDirectory: true)
        rootDirectory = base
        sessionsFile = base.appendingPathComponent("sessions.json")
        messagesDirectory = base.appendingPathComponent("messages", isDirectory: true)
        try? FileManager.default.createDirectory(at: messagesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Stored DTOs (symmetric Codable, decoupled from ChatSession)

    private struct StoredSession: Codable {
        let id: UUID
        var title: String
        let createdAt: Date
        var updatedAt: Date
    }
    private struct StoredMessage: Codable {
        let id: UUID
        let role: String
        let content: String
        let createdAt: Date
    }

    // MARK: - Sessions

    /// All sessions, most recently updated first.
    func sessions() -> [ChatSession] {
        lock.lock(); defer { lock.unlock() }
        return cachedSessions()
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { ChatSession(id: $0.id, title: $0.title, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
    }

    /// Create or update a session. Title is set once (first user message) and
    /// preserved; `updatedAt` bumps on every call.
    func upsertSession(id: UUID, title: String, at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var all = cachedSessions()
        if let index = all.firstIndex(where: { $0.id == id }) {
            all[index].updatedAt = date
            if all[index].title.isEmpty { all[index].title = title }
        } else {
            all.append(StoredSession(id: id, title: title, createdAt: date, updatedAt: date))
        }
        sessionsCache = all
        scheduleSessionsWrite(all)
    }

    func deleteSession(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        var all = cachedSessions()
        all.removeAll { $0.id == id }
        sessionsCache = all
        // Empty tombstone, not nil: a nil entry would read-through to the
        // on-disk file, which the write-behind removal may not have deleted
        // yet. Memory is authoritative for mutations.
        messagesCache[id] = []
        scheduleSessionsWrite(all)
        writeQueue.async { [messagesFile = messagesFile(id)] in
            try? FileManager.default.removeItem(at: messagesFile)
        }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        sessionsCache = []
        messagesCache = [:]
        // Destructive reset runs in order behind any pending writes, then the
        // directory is gone before this call's effects can be observed stale.
        writeQueue.sync { [rootDirectory, messagesDirectory] in
            try? FileManager.default.removeItem(at: rootDirectory)
            try? FileManager.default.createDirectory(at: messagesDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Messages

    /// Messages for a session, oldest first, mapped to the DTO the chat UI parses.
    func messages(for sessionId: UUID) -> [ChatMessageDTO] {
        lock.lock(); defer { lock.unlock() }
        return cachedMessages(sessionId).map { stored in
            ChatMessageDTO(
                id: stored.id,
                role: stored.role,
                content: stored.content,
                createdAt: Self.iso.string(from: stored.createdAt)
            )
        }
    }

    /// The trailing `limit` messages as bare (role, content) pairs — the shape
    /// the model-history rebuild actually consumes. Skips the DTO mapping and
    /// its per-message ISO date formatting, and callers stop paying for the
    /// whole transcript when only the tail feeds the prompt
    /// (spec 029 Amendment A).
    func recentTurnRecords(for sessionId: UUID, limit: Int) -> [(role: String, content: String)] {
        lock.lock(); defer { lock.unlock() }
        return cachedMessages(sessionId).suffix(limit).map { ($0.role, $0.content) }
    }

    /// Append a message to a session (creating the file if needed).
    func appendMessage(id: UUID = UUID(), role: String, content: String, to sessionId: UUID, at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var all = cachedMessages(sessionId)
        all.append(StoredMessage(id: id, role: role, content: content, createdAt: date))
        messagesCache[sessionId] = all
        scheduleMessagesWrite(all, for: sessionId)
    }

    /// Drains pending write-behind work. Call when the app backgrounds so a
    /// suspension can't strand a turn in memory only.
    func flush() {
        writeQueue.sync {}
    }

    // MARK: - Cache (call with `lock` held)

    private func cachedSessions() -> [StoredSession] {
        if let sessionsCache { return sessionsCache }
        let loaded = loadSessions()
        sessionsCache = loaded
        return loaded
    }

    private func cachedMessages(_ id: UUID) -> [StoredMessage] {
        if let cached = messagesCache[id] { return cached }
        let loaded = loadMessages(id)
        messagesCache[id] = loaded
        return loaded
    }

    // MARK: - Disk

    private func messagesFile(_ id: UUID) -> URL {
        messagesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func loadSessions() -> [StoredSession] {
        guard let data = try? Data(contentsOf: sessionsFile) else { return [] }
        return (try? decoder.decode([StoredSession].self, from: data)) ?? []
    }
    private func scheduleSessionsWrite(_ sessions: [StoredSession]) {
        // Encode on the queue too: the encode is O(list) and used to run on
        // the caller (send) thread between the last token and `.final`
        // (spec 029 Amendment A). `encoder` is queue-confined — these blocks
        // are its only users, and the queue is serial.
        writeQueue.async { [sessionsFile, encoder] in
            Self.write(try? encoder.encode(sessions), to: sessionsFile)
        }
    }
    private func loadMessages(_ id: UUID) -> [StoredMessage] {
        guard let data = try? Data(contentsOf: messagesFile(id)) else { return [] }
        return (try? decoder.decode([StoredMessage].self, from: data)) ?? []
    }
    private func scheduleMessagesWrite(_ messages: [StoredMessage], for id: UUID) {
        writeQueue.async { [file = messagesFile(id), encoder] in
            Self.write(try? encoder.encode(messages), to: file)
        }
    }

    private static func write(_ data: Data?, to url: URL) {
        guard let data else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
