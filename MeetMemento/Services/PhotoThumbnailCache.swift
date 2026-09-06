//
//  PhotoThumbnailCache.swift
//  MeetMemento
//
//  In-memory cache of decrypted entry-photo thumbnails, so YourEntriesView
//  only pays the decrypt cost once per entry per app session. NSCache (not a
//  plain dictionary) so it survives view-identity churn across tab switches
//  and evicts automatically under memory pressure.
//
//  Thumbnails are ImageIO-downsampled (~800px) — list cards never decode
//  full camera JPEGs.
//

import ImageIO
import UIKit

final class PhotoThumbnailCache {
    static let shared = PhotoThumbnailCache()

    /// Longest edge for list-card thumbnails. Card width is ~376pt at 3x.
    static let maxPixelSize: CGFloat = 800
    static let prefetchConcurrency = 4

    private let cache = NSCache<NSString, CachedThumbnail>()

    private init() {}

    func image(for entryId: UUID) -> UIImage? {
        cache.object(forKey: entryId.uuidString as NSString)?.image
    }

    func sample(for entryId: UUID) -> JournalBackdropSample? {
        cache.object(forKey: entryId.uuidString as NSString)?.sample
    }

    func store(_ image: UIImage, for entryId: UUID) {
        let sample = JournalBackdropContrast.sample(image: image)
        cache.setObject(
            CachedThumbnail(image: image, sample: sample),
            forKey: entryId.uuidString as NSString
        )
    }

    func removeImage(for entryId: UUID) {
        cache.removeObject(forKey: entryId.uuidString as NSString)
    }

    /// Decrypts and downsamples any `hasPhoto` covers not already cached.
    /// Failures skip; does not throw. Bounded concurrency so launch is not
    /// a stampede of full-file reads.
    func prefetch(entryIds: [UUID]) async {
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
        let decoded: UIImage? = await Task.detached(priority: .userInitiated) {
            Self.decodeDownsampled(entryId: entryId)
        }.value
        guard let decoded else { return }
        store(decoded, for: entryId)
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

    private static func decodeDownsampled(entryId: UUID) -> UIImage? {
        guard let encrypted = PhotoStorage.shared.loadEncrypted(entryId: entryId),
              let data = JournalService.shared.encryptionService.decryptData(encrypted) else {
            return nil
        }
        return downsampledImage(from: data)
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
