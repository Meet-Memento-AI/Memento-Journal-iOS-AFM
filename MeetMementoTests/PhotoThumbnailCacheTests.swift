import UIKit
import XCTest
@testable import MeetMemento

final class PhotoThumbnailCacheTests: XCTestCase {
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
        let thumb = PhotoThumbnailCache.downsampledImage(from: data, maxPixelSize: 800)
        XCTAssertNotNil(thumb)
        let longest = max(thumb!.size.width, thumb!.size.height)
        XCTAssertLessThanOrEqual(longest, 800, "list path must not keep camera-size bitmaps")
    }

    func test_photoChrome_notPlainLayoutWhenImageMissing() {
        XCTAssertTrue(JournalCard.usesPhotoChrome(hasPhoto: true))
        XCTAssertFalse(JournalCard.usesPhotoChrome(hasPhoto: false))
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
