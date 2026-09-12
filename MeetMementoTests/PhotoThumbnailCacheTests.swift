import UIKit
import XCTest
@testable import MeetMemento

final class PhotoThumbnailCacheTests: XCTestCase {
    private var encryption: EncryptionService!

    override func setUp() {
        super.setUp()
        encryption = EncryptionService(keychain: InMemoryKeychainStore())
        XCTAssertNotNil(encryption.encryptData(Data([1])), "test DEK must be creatable")
        PhotoThumbnailCache.encryptionOverride = encryption
        PhotoThumbnailCache.shared.resetTestCounters()
        PhotoStorage.shared.clearAll()
    }

    override func tearDown() {
        PhotoThumbnailCache.encryptionOverride = nil
        PhotoThumbnailCache.shared.resetTestCounters()
        PhotoStorage.shared.clearAll()
        super.tearDown()
    }

    func test_store_makesImageRetrievable() {
        let id = UUID()
        let image = makeImage(size: CGSize(width: 16, height: 16), color: .red)
        PhotoThumbnailCache.shared.store(image, for: id)
        XCTAssertNotNil(PhotoThumbnailCache.shared.image(for: id))
        XCTAssertNotNil(PhotoThumbnailCache.shared.sample(for: id))
        PhotoThumbnailCache.shared.removeImage(for: id)
    }

    func test_downsample_capsLongestEdge() {
        let data = makeJPEG(size: CGSize(width: 1600, height: 900), color: .blue)
        let thumb = PhotoThumbnailCache.downsampledImage(from: data)
        XCTAssertNotNil(thumb)
        let longest = max(thumb!.size.width, thumb!.size.height)
        XCTAssertLessThanOrEqual(
            longest,
            PhotoThumbnailCache.maxPixelSize,
            "list path must not keep camera-size bitmaps"
        )
    }

    func test_photoChrome_notPlainLayoutWhenImageMissing() {
        XCTAssertTrue(JournalCard.usesPhotoChrome(hasPhoto: true))
        XCTAssertTrue(JournalCard.photoChromeTitleIsWhite(hasPhoto: true))
        XCTAssertFalse(JournalCard.usesPhotoChrome(hasPhoto: false))
        XCTAssertFalse(JournalCard.photoChromeTitleIsWhite(hasPhoto: false))

        let sample = JournalBackdropSample(red: 0.2, green: 0.4, blue: 0.6)
        let sampled = JournalCard.photoPlaceholderRGB(sample: sample)
        XCTAssertEqual(sampled.red, 0.2, accuracy: 0.001)
        XCTAssertEqual(sampled.green, 0.4, accuracy: 0.001)
        XCTAssertEqual(sampled.blue, 0.6, accuracy: 0.001)
        let fallback = JournalCard.photoPlaceholderRGB(sample: nil)
        XCTAssertEqual(fallback.red, JournalBackdropShader.scrimRed, accuracy: 0.001)
        XCTAssertNotEqual(fallback.red, 0.933, "placeholder must not be journalCardFill gray150")
    }

    func test_listFillScale_neverUsesEditorOverflow() {
        XCTAssertEqual(JournalPhotoBackdrop.fillScale(for: 12, isEditor: false), 1.12)
        XCTAssertEqual(JournalPhotoBackdrop.fillScale(for: 100, isEditor: false), 1.12)
        XCTAssertEqual(JournalPhotoBackdrop.fillScale(for: 100, isEditor: true), 1.4)
        XCTAssertEqual(JournalPhotoBackdrop.fillScale(for: 0, isEditor: false), 1)
    }

    func test_storeDownsampled_persistsAndSkipsFullFileOnReload() async {
        let id = UUID()
        let jpeg = makeJPEG(size: CGSize(width: 800, height: 600), color: .green)
        guard let encrypted = encryption.encryptData(jpeg) else {
            return XCTFail("could not encrypt fixture")
        }
        do {
            try PhotoStorage.shared.saveEncrypted(entryId: id, encryptedData: encrypted)
        } catch {
            return XCTFail("could not write fixture: \(error)")
        }

        PhotoThumbnailCache.shared.storeDownsampled(from: jpeg, for: id)
        XCTAssertTrue(PhotoThumbnailCache.shared.hasPersistedThumb(for: id))
        XCTAssertNotNil(PhotoThumbnailCache.shared.image(for: id))

        PhotoThumbnailCache.shared.evictMemory(for: id)
        XCTAssertNil(PhotoThumbnailCache.shared.image(for: id))
        PhotoThumbnailCache.shared.resetTestCounters()

        await PhotoThumbnailCache.shared.loadIfNeeded(entryId: id)

        XCTAssertNotNil(PhotoThumbnailCache.shared.image(for: id))
        XCTAssertEqual(
            PhotoThumbnailCache.shared.fullFileDecodeCount,
            0,
            "persisted thumb must skip the 1600px decrypt"
        )
        PhotoThumbnailCache.shared.removeImage(for: id)
    }

    func test_loadIfNeeded_coalescesInFlightFullFileDecode() async {
        let id = UUID()
        let jpeg = makeJPEG(size: CGSize(width: 640, height: 480), color: .orange)
        guard let encrypted = encryption.encryptData(jpeg) else {
            return XCTFail("could not encrypt fixture")
        }
        do {
            try PhotoStorage.shared.saveEncrypted(entryId: id, encryptedData: encrypted)
        } catch {
            return XCTFail("could not write fixture: \(error)")
        }

        PhotoThumbnailCache.shared.resetTestCounters()
        async let first: Void = PhotoThumbnailCache.shared.loadIfNeeded(entryId: id)
        async let second: Void = PhotoThumbnailCache.shared.loadIfNeeded(entryId: id)
        _ = await (first, second)

        XCTAssertNotNil(PhotoThumbnailCache.shared.image(for: id))
        XCTAssertEqual(
            PhotoThumbnailCache.shared.fullFileDecodeCount,
            1,
            "prefetch + row task must decrypt the cover once"
        )
        PhotoThumbnailCache.shared.removeImage(for: id)
    }

    func test_storeDownsampled_isWritePathPrime() {
        let id = UUID()
        let jpeg = makeJPEG(size: CGSize(width: 400, height: 300), color: .purple)
        PhotoThumbnailCache.shared.storeDownsampled(from: jpeg, for: id)
        XCTAssertNotNil(PhotoThumbnailCache.shared.image(for: id), "create/update .set must prime the list cache")
        XCTAssertTrue(PhotoThumbnailCache.shared.hasPersistedThumb(for: id))
        PhotoThumbnailCache.shared.removeImage(for: id)
    }

    @MainActor
    func test_loadEntries_setsHasInitiallyLoadedWithoutWaitingForPrefetch() async {
        final class ResumeBox: @unchecked Sendable {
            private let lock = NSLock()
            private var continuation: CheckedContinuation<Void, Never>?

            func park(_ continuation: CheckedContinuation<Void, Never>) {
                lock.lock()
                self.continuation = continuation
                lock.unlock()
            }

            func release() {
                lock.lock()
                let parked = continuation
                continuation = nil
                lock.unlock()
                parked?.resume()
            }
        }

        let box = ResumeBox()
        let prefetchEntered = expectation(description: "prefetch invoked")
        let loadReturned = expectation(description: "loadEntries returned")
        PhotoThumbnailCache.shared.prefetchWillRun = {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                box.park(cont)
                prefetchEntered.fulfill()
            }
        }

        let vm = EntryViewModel()
        Task { @MainActor in
            await vm.loadEntries()
            loadReturned.fulfill()
        }

        await fulfillment(of: [loadReturned, prefetchEntered], timeout: 2.0)
        XCTAssertTrue(vm.hasInitiallyLoaded, "list must publish before covers decrypt")
        XCTAssertFalse(vm.isLoading)
        box.release()
        PhotoThumbnailCache.shared.prefetchWillRun = nil
    }

    private func makeImage(size: CGSize, color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeJPEG(size: CGSize, color: UIColor) -> Data {
        let image = makeImage(size: size, color: color)
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            XCTFail("could not encode JPEG fixture")
            return Data()
        }
        return data
    }
}
