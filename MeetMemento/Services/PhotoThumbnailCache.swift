//
//  PhotoThumbnailCache.swift
//  MeetMemento
//
//  In-memory + on-disk cache of decrypted entry-photo thumbnails, so
//  YourEntriesView only pays the full-file decrypt once per photo. NSCache
//  (not a plain dictionary) so it survives view-identity churn across tab
//  switches and evicts automatically under memory pressure.
//
//  Thumbnails are ImageIO-downsampled (~400px) — list cards never decode
//  full camera JPEGs. A sibling encrypted thumb file keeps the next launch
//  off the 1600px original.
//

import ImageIO
import UIKit

final class PhotoThumbnailCache {
    static let shared = PhotoThumbnailCache()

    /// Longest edge for list-card thumbnails. Cards hug title height and
    /// already apply a 12pt blur; 400px is enough at 3x.
    static let maxPixelSize: CGFloat = 400
    static let prefetchConcurrency = 4

    /// Tests inject an in-memory keychain so persist/decrypt doesn't need
    /// the real Keychain entitlement.
    static var encryptionOverride: EncryptionService?

    /// Test seam: `loadEntries` must return without waiting on this.
    var prefetchWillRun: (@Sendable () async -> Void)?

    private let cache = NSCache<NSString, CachedThumbnail>()
    private let loadGate = ThumbnailLoadGate()
    private let counterLock = NSLock()
    private var _fullFileDecodeCount = 0

    /// How many times the full EncryptedPhotos file was decrypted.
    var fullFileDecodeCount: Int {
        counterLock.lock()
        defer { counterLock.unlock() }
        return _fullFileDecodeCount
    }

    private init() {}

    private static var encryption: EncryptionService {
        encryptionOverride ?? JournalService.shared.encryptionService
    }

    func resetTestCounters() {
        counterLock.lock()
        _fullFileDecodeCount = 0
        counterLock.unlock()
        prefetchWillRun = nil
    }

    func image(for entryId: UUID) -> UIImage? {
        cache.object(forKey: entryId.uuidString as NSString)?.image
    }

    func sample(for entryId: UUID) -> JournalBackdropSample? {
        cache.object(forKey: entryId.uuidString as NSString)?.sample
    }

    func hasPersistedThumb(for entryId: UUID) -> Bool {
        PhotoStorage.shared.hasEncryptedThumb(entryId: entryId)
    }

    /// Memory only — persisted thumb stays so tests can prove a disk hit.
    func evictMemory(for entryId: UUID) {
        cache.removeObject(forKey: entryId.uuidString as NSString)
    }

    func store(_ image: UIImage, for entryId: UUID) {
        store(image, sample: JournalBackdropContrast.sample(image: image), for: entryId, persist: true)
    }

    /// Write-path API: downsample the already-in-memory JPEG and cache it
    /// so the list never encrypts → disk → decrypts just to draw the card.
    func storeDownsampled(from data: Data, for entryId: UUID) {
        guard let thumb = Self.downsampledImage(from: data) else { return }
        store(thumb, for: entryId)
    }

    func removeImage(for entryId: UUID) {
        cache.removeObject(forKey: entryId.uuidString as NSString)
        PhotoStorage.shared.deleteEncryptedThumb(entryId: entryId)
    }

    /// Decrypts and downsamples any `hasPhoto` covers not already cached.
    /// Failures skip; does not throw. Bounded concurrency so launch is not
    /// a stampede of full-file reads.
    func prefetch(entryIds: [UUID]) async {
        if let prefetchWillRun {
            await prefetchWillRun()
        }
        let missing = entryIds.filter { image(for: $0) == nil }
        guard !missing.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            var nextIndex = 0
            func enqueue() {
                guard nextIndex < missing.count else { return }
                let id = missing[nextIndex]
                nextIndex += 1
                group.addTask { await self.loadIfNeeded(entryId: id) }
            }
            for _ in 0..<min(Self.prefetchConcurrency, missing.count) {
                enqueue()
            }
            for await _ in group {
                enqueue()
            }
        }
    }

    func loadIfNeeded(entryId: UUID) async {
        if image(for: entryId) != nil { return }
        let decoded = await loadGate.run(entryId: entryId) {
            PhotoThumbnailCache.decodeThumbOrFull(entryId: entryId)
        }
        guard let decoded else { return }
        if image(for: entryId) == nil {
            store(
                decoded.image,
                sample: decoded.sample,
                for: entryId,
                persist: !decoded.fromPersistedThumb
            )
        }
    }

    /// ImageIO thumbnail from decrypted photo bytes. Falls back to a full
    /// `UIImage(data:)` decode if the source cannot produce a thumbnail.
    static func downsampledImage(from data: Data, maxPixelSize: CGFloat = maxPixelSize) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cg)
    }

    // MARK: - Private

    private func store(
        _ image: UIImage,
        sample: JournalBackdropSample,
        for entryId: UUID,
        persist: Bool
    ) {
        cache.setObject(
            CachedThumbnail(image: image, sample: sample),
            forKey: entryId.uuidString as NSString
        )
        if persist {
            persistThumb(image, sample: sample, entryId: entryId)
        }
    }

    private func persistThumb(_ image: UIImage, sample: JournalBackdropSample, entryId: UUID) {
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else { return }
        let envelope = PersistedThumbnailEnvelope(
            jpeg: jpeg,
            red: sample.red,
            green: sample.green,
            blue: sample.blue
        )
        guard let payload = try? JSONEncoder().encode(envelope),
              let encrypted = Self.encryption.encryptData(payload) else { return }
        try? PhotoStorage.shared.saveEncryptedThumb(entryId: entryId, encryptedData: encrypted)
    }

    private static func decodeThumbOrFull(entryId: UUID) -> DecodedThumb? {
        if let fromDisk = decodePersistedThumb(entryId: entryId) {
            return fromDisk
        }
        return decodeFullFile(entryId: entryId)
    }

    private static func decodePersistedThumb(entryId: UUID) -> DecodedThumb? {
        guard let encrypted = PhotoStorage.shared.loadEncryptedThumb(entryId: entryId),
              let payload = encryption.decryptData(encrypted),
              let envelope = try? JSONDecoder().decode(PersistedThumbnailEnvelope.self, from: payload),
              let image = UIImage(data: envelope.jpeg) else {
            return nil
        }
        let sample = JournalBackdropSample(red: envelope.red, green: envelope.green, blue: envelope.blue)
        return DecodedThumb(image: image, sample: sample, fromPersistedThumb: true)
    }

    private static func decodeFullFile(entryId: UUID) -> DecodedThumb? {
        guard let encrypted = PhotoStorage.shared.loadEncrypted(entryId: entryId),
              let data = encryption.decryptData(encrypted),
              let image = downsampledImage(from: data) else {
            return nil
        }
        shared.recordFullFileDecode()
        return DecodedThumb(
            image: image,
            sample: JournalBackdropContrast.sample(image: image),
            fromPersistedThumb: false
        )
    }

    private func recordFullFileDecode() {
        counterLock.lock()
        _fullFileDecodeCount += 1
        counterLock.unlock()
    }
}

private struct DecodedThumb: @unchecked Sendable {
    let image: UIImage
    let sample: JournalBackdropSample
    let fromPersistedThumb: Bool
}

private struct PersistedThumbnailEnvelope: Codable {
    var version: Int = 1
    let jpeg: Data
    let red: Double
    let green: Double
    let blue: Double
}

/// Coalesces concurrent `loadIfNeeded` for the same id so prefetch + row
/// `.task` decrypt the cover once.
private actor ThumbnailLoadGate {
    private var inFlight: [UUID: Task<DecodedThumb?, Never>] = [:]

    func run(entryId: UUID, work: @escaping @Sendable () -> DecodedThumb?) async -> DecodedThumb? {
        if let existing = inFlight[entryId] {
            return await existing.value
        }
        let task = Task.detached(priority: .userInitiated) { work() }
        inFlight[entryId] = task
        let result = await task.value
        inFlight[entryId] = nil
        return result
    }
}

private final class CachedThumbnail: NSObject {
    let image: UIImage
    let sample: JournalBackdropSample

    init(image: UIImage, sample: JournalBackdropSample) {
        self.image = image
        self.sample = sample
    }
}
