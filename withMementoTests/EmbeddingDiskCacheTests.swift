import XCTest
@testable import MeetMemento

/// The persistent embedding cache (spec 029): stable hashing, the per-entry
/// binary records, relaunch survival via a second instance on the same
/// directory, hash invalidation, purge hooks, and the vDSP cosine path.
/// Everything here uses `storeEntryVector`/`cachedEntryVector`, so no test
/// depends on NLEmbedding assets being provisioned on the test host.
final class EmbeddingDiskCacheTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmbeddingDiskCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// A fresh service on the shared test directory — constructing a second
    /// one simulates an app relaunch reading the same disk cache.
    private func makeService() -> EmbeddingService {
        EmbeddingService(directory: directory)
    }

    private func randomVector(_ count: Int = 128) -> [Double] {
        (0..<count).map { _ in Double.random(in: -1...1) }
    }

    // MARK: - Stable hash

    func test_stableHash_matchesKnownFNV1aVectors() {
        // Process-stable by construction — pinned to the published FNV-1a 64
        // test vectors, which `String.hashValue` (per-process randomized)
        // could never satisfy.
        XCTAssertEqual(EmbeddingService.stableHash(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(EmbeddingService.stableHash("a"), 0xaf63_dc4c_8601_ec8c)
        XCTAssertEqual(EmbeddingService.stableHash("abc"), 0xe71f_a219_0541_574b)
    }

    func test_stableHash_isDeterministic_andSensitive() {
        XCTAssertEqual(EmbeddingService.stableHash("hello world"), EmbeddingService.stableHash("hello world"))
        XCTAssertNotEqual(EmbeddingService.stableHash("hello world"), EmbeddingService.stableHash("hello world!"))
    }

    func test_contentHash_cannotCollideAcrossTitleTextBoundary() {
        // "a. b"/"c" and "a"/"b. c" concatenate to the same embed text; the
        // length-mixed content hash must still tell them apart.
        XCTAssertNotEqual(
            EmbeddingService.contentHash(title: "a. b", text: "c"),
            EmbeddingService.contentHash(title: "a", text: "b. c")
        )
        XCTAssertEqual(
            EmbeddingService.contentHash(title: "t", text: "x"),
            EmbeddingService.contentHash(title: "t", text: "x")
        )
    }

    // MARK: - Binary record round trip

    func test_vectorRecord_roundTripsThroughEncodeDecode() {
        let vector = randomVector()
        let norm = EmbeddingService.norm(of: vector)
        let data = EmbeddingService.encodeVectorRecord(hash: 0xDEAD_BEEF_0BAD_F00D, norm: norm, vector: vector)

        guard let decoded = EmbeddingService.decodeVectorRecord(data) else {
            return XCTFail("well-formed record must decode")
        }
        XCTAssertEqual(decoded.hash, 0xDEAD_BEEF_0BAD_F00D)
        XCTAssertEqual(decoded.norm, norm, accuracy: 1e-12)
        XCTAssertEqual(decoded.vector.count, vector.count)
        for (a, b) in zip(decoded.vector, vector) {
            // Vectors are persisted as Float32 — rounding stays far inside
            // retrieval tolerance.
            XCTAssertEqual(a, b, accuracy: 1e-6)
        }
    }

    func test_decodeVectorRecord_rejectsMalformedData() {
        XCTAssertNil(EmbeddingService.decodeVectorRecord(Data()))
        XCTAssertNil(EmbeddingService.decodeVectorRecord(Data(repeating: 0xAB, count: 64)))
        // Truncated genuine record.
        let good = EmbeddingService.encodeVectorRecord(hash: 1, norm: 1, vector: randomVector(16))
        XCTAssertNil(EmbeddingService.decodeVectorRecord(good.prefix(good.count - 3)))
    }

    // MARK: - Relaunch survival + invalidation

    func test_storedVector_survivesRelaunch() {
        let id = UUID()
        let hash = EmbeddingService.contentHash(title: "Title", text: "Body text")
        let vector = randomVector()
        makeService().storeEntryVector(vector, id: id, contentHash: hash)

        // "Relaunch": a brand-new instance, same directory, cold memory.
        let relaunched = makeService()
        guard let cached = relaunched.cachedEntryVector(id: id, contentHash: hash) else {
            return XCTFail("vector must be readable from disk after a relaunch")
        }
        XCTAssertEqual(cached.vector.count, vector.count)
        for (a, b) in zip(cached.vector, vector) {
            XCTAssertEqual(a, b, accuracy: 1e-6)
        }
        XCTAssertEqual(cached.norm, EmbeddingService.norm(of: vector), accuracy: 1e-6)
    }

    func test_changedText_invalidatesCachedVector() {
        let id = UUID()
        let oldHash = EmbeddingService.contentHash(title: "Title", text: "old body")
        makeService().storeEntryVector(randomVector(), id: id, contentHash: oldHash)

        let relaunched = makeService()
        let newHash = EmbeddingService.contentHash(title: "Title", text: "edited body")
        XCTAssertNil(relaunched.cachedEntryVector(id: id, contentHash: newHash),
                     "a changed content hash must force a re-embed, not serve the stale vector")
        XCTAssertNotNil(relaunched.cachedEntryVector(id: id, contentHash: oldHash))
    }

    // MARK: - Purge hooks (spec 029 R8)

    func test_removeEmbeddings_purgesMemoryAndDisk() {
        let id = UUID(), keep = UUID()
        let hash = EmbeddingService.stableHash("some text")
        let service = makeService()
        service.storeEntryVector(randomVector(), id: id, contentHash: hash)
        service.storeEntryVector(randomVector(), id: keep, contentHash: hash)

        service.removeEmbeddings(for: [id])

        XCTAssertNil(service.cachedEntryVector(id: id, contentHash: hash))
        XCTAssertNotNil(service.cachedEntryVector(id: keep, contentHash: hash))
        // And it is gone from DISK, not just memory.
        XCTAssertNil(makeService().cachedEntryVector(id: id, contentHash: hash))
        XCTAssertNotNil(makeService().cachedEntryVector(id: keep, contentHash: hash))
    }

    func test_retainEmbeddings_dropsEverythingOutsideTheSet() {
        let kept = UUID(), dropped = UUID()
        let hash = EmbeddingService.stableHash("t")
        let service = makeService()
        service.storeEntryVector(randomVector(), id: kept, contentHash: hash)
        service.storeEntryVector(randomVector(), id: dropped, contentHash: hash)

        service.retainEmbeddings(only: [kept])

        XCTAssertNotNil(service.cachedEntryVector(id: kept, contentHash: hash))
        XCTAssertNil(service.cachedEntryVector(id: dropped, contentHash: hash))
        XCTAssertNil(makeService().cachedEntryVector(id: dropped, contentHash: hash), "GC must reach disk")
    }

    func test_clearCache_removesTheDiskCacheToo() {
        let id = UUID()
        let hash = EmbeddingService.stableHash("t")
        let service = makeService()
        service.storeEntryVector(randomVector(), id: id, contentHash: hash)

        service.clearCache()

        XCTAssertNil(service.cachedEntryVector(id: id, contentHash: hash))
        XCTAssertNil(makeService().cachedEntryVector(id: id, contentHash: hash),
                     "delete-everything routes through clearCache, so disk must be empty")
        let leftovers = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(leftovers.filter { $0.pathExtension == "vec" }.isEmpty)
    }

    // MARK: - vDSP cosine

    /// Reference implementation: the scalar loop the vDSP path replaced.
    private func scalarCosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    func test_vDSPCosine_matchesScalarWithinEpsilon() {
        for _ in 0..<20 {
            let a = randomVector(300), b = randomVector(300)
            let expected = scalarCosine(a, b)
            XCTAssertEqual(EmbeddingService.cosineSimilarity(a, b), expected, accuracy: 1e-5)
            // Precomputed-norm variant must agree as well.
            let withNorms = EmbeddingService.cosineSimilarity(
                a, normA: EmbeddingService.norm(of: a),
                b, normB: EmbeddingService.norm(of: b)
            )
            XCTAssertEqual(withNorms, expected, accuracy: 1e-5)
        }
    }

    func test_cosine_degenerateInputsReturnZero() {
        XCTAssertEqual(EmbeddingService.cosineSimilarity([], []), 0)
        XCTAssertEqual(EmbeddingService.cosineSimilarity([1, 2], [1, 2, 3]), 0)
        XCTAssertEqual(EmbeddingService.cosineSimilarity([0, 0], [1, 1]), 0)
        XCTAssertEqual(EmbeddingService.cosineSimilarity([1, 0], normA: 0, [1, 0], normB: 1), 0)
    }

    // MARK: - Query LRU (embedder-dependent, skipped where unavailable)

    func test_embedQuery_isStableAndMatchesEmbed() {
        let service = makeService()
        guard service.isAvailable else { return } // no NLEmbedding assets on this host
        guard let direct = service.embed("how was my week"),
              let first = service.embedQuery("how was my week"),
              let second = service.embedQuery("how was my week") else {
            return XCTFail("embedder reported available but produced no vector")
        }
        XCTAssertEqual(first.vector, direct, "the LRU must cache exactly what embed() produces")
        XCTAssertEqual(first.vector, second.vector, "a repeat query must be served from the LRU unchanged")
        XCTAssertEqual(first.norm, EmbeddingService.norm(of: direct), accuracy: 1e-12)
    }
}
