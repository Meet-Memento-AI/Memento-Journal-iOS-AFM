//
//  LocalChatStore.swift
//  MeetMemento
//
//  On-device persistence for chat sessions and messages, replacing the Supabase
//  chat_sessions/chat_messages tables. The edge function used to persist turns
//  server-side; with native on-device chat there is no server, so multiple chat
//  windows (create / list / switch / delete / persist across launches) live here.
//
//  Stored as JSON under Application Support with complete file protection
//  (device-encrypted at rest — no PIN required). Uses its own Codable DTOs so it
//  doesn't depend on ChatSession's Supabase-oriented (asymmetric) Codable.
//

import Foundation

final class LocalChatStore: @unchecked Sendable {
    static let shared = LocalChatStore()

    private let lock = NSLock()
    private let rootDirectory: URL
    private let sessionsFile: URL
    private let messagesDirectory: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
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
        return loadSessions()
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { ChatSession(id: $0.id, title: $0.title, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
    }

    /// Create or update a session. Title is set once (first user message) and
    /// preserved; `updatedAt` bumps on every call.
    func upsertSession(id: UUID, title: String, at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var all = loadSessions()
        if let index = all.firstIndex(where: { $0.id == id }) {
            all[index].updatedAt = date
            if all[index].title.isEmpty { all[index].title = title }
        } else {
            all.append(StoredSession(id: id, title: title, createdAt: date, updatedAt: date))
        }
        saveSessions(all)
    }

    func deleteSession(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        var all = loadSessions()
        all.removeAll { $0.id == id }
        saveSessions(all)
        try? FileManager.default.removeItem(at: messagesFile(id))
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: rootDirectory)
        try? FileManager.default.createDirectory(at: messagesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Messages

    /// Messages for a session, oldest first, mapped to the DTO the chat UI parses.
    func messages(for sessionId: UUID) -> [ChatMessageDTO] {
        lock.lock(); defer { lock.unlock() }
        return loadMessages(sessionId).map { stored in
            ChatMessageDTO(
                id: stored.id,
                role: stored.role,
                content: stored.content,
                createdAt: Self.iso.string(from: stored.createdAt)
            )
        }
    }

    /// Append a message to a session (creating the file if needed).
    func appendMessage(id: UUID = UUID(), role: String, content: String, to sessionId: UUID, at date: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var all = loadMessages(sessionId)
        all.append(StoredMessage(id: id, role: role, content: content, createdAt: date))
        saveMessages(all, for: sessionId)
    }

    // MARK: - Disk

    private func messagesFile(_ id: UUID) -> URL {
        messagesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func loadSessions() -> [StoredSession] {
        guard let data = try? Data(contentsOf: sessionsFile) else { return [] }
        return (try? decoder.decode([StoredSession].self, from: data)) ?? []
    }
    private func saveSessions(_ sessions: [StoredSession]) {
        write(try? encoder.encode(sessions), to: sessionsFile)
    }
    private func loadMessages(_ id: UUID) -> [StoredMessage] {
        guard let data = try? Data(contentsOf: messagesFile(id)) else { return [] }
        return (try? decoder.decode([StoredMessage].self, from: data)) ?? []
    }
    private func saveMessages(_ messages: [StoredMessage], for id: UUID) {
        write(try? encoder.encode(messages), to: messagesFile(id))
    }

    private func write(_ data: Data?, to url: URL) {
        guard let data else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
