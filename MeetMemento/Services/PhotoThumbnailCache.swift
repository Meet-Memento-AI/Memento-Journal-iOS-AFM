//
//  PhotoThumbnailCache.swift
//  MeetMemento
//
//  In-memory cache of decrypted entry-photo thumbnails, so YourEntriesView
//  only pays the decrypt cost once per entry per app session. NSCache (not a
//  plain dictionary) so it survives view-identity churn across tab switches
//  and evicts automatically under memory pressure.
//

import UIKit

final class PhotoThumbnailCache {
    static let shared = PhotoThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {}

    func image(for entryId: UUID) -> UIImage? {
        cache.object(forKey: entryId.uuidString as NSString)
    }

    func store(_ image: UIImage, for entryId: UUID) {
        cache.setObject(image, forKey: entryId.uuidString as NSString)
    }

    func removeImage(for entryId: UUID) {
        cache.removeObject(forKey: entryId.uuidString as NSString)
    }
}
