import NaturalLanguage
import XCTest
@testable import MeetMemento

final class PassageChunkerTests: XCTestCase {

    func test_shortEntry_isOnePassage() {
        let chunked = PassageChunker.chunk(text: "Just a short note about lunch.")
        XCTAssertEqual(chunked.passages.count, 1)
        XCTAssertEqual(chunked.passages[0].index, 0)
        XCTAssertTrue(chunked.passages[0].text.contains("lunch"))
    }

    func test_merge_staysInsideCharBudget() {
        let sentences = (0..<12).map { "This is sentence number \($0) with enough words to count." }
        let passages = PassageChunker.merge(sentences)
        XCTAssertGreaterThan(passages.count, 1)
        for passage in passages.dropLast() {
            XCTAssertGreaterThanOrEqual(passage.text.count, PassageChunker.minChars)
            XCTAssertLessThanOrEqual(passage.text.count, PassageChunker.maxChars)
        }
        for passage in passages {
            XCTAssertLessThanOrEqual(passage.text.count, PassageChunker.maxChars + 80,
                                     "a single oversize sentence may exceed max, merged ones must not by much")
        }
    }

    func test_neverSplitsMidSentence() {
        let long = String(repeating: "word ", count: 90).trimmingCharacters(in: .whitespaces) + "."
        XCTAssertGreaterThan(long.count, PassageChunker.maxChars)
        let passages = PassageChunker.merge([long])
        XCTAssertEqual(passages.count, 1)
        XCTAssertEqual(passages[0].text, long)
    }

    func test_abbreviation_staysWithItsSentence() {
        let text = "I saw Dr. Chen at the clinic on Tuesday. We talked about the ceramic bicycle in the garage."
        let sentences = PassageChunker.tokenizeSentences(text)
        XCTAssertGreaterThanOrEqual(sentences.count, 1)
        let joined = sentences.joined(separator: " ")
        XCTAssertTrue(joined.contains("Dr. Chen") || joined.contains("Dr."))
        XCTAssertFalse(sentences.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "Dr" }))
    }

    func test_excerpt_includesNeighborSentences() {
        let sentences = [
            "First neighbor sits here.",
            "The middle passage names the ceramic bicycle.",
            "Third neighbor closes it out."
        ]
        let passage = Passage(index: 0, text: sentences[1], sentenceRange: 1..<2)
        let excerpt = PassageChunker.excerpt(sentences: sentences, passage: passage, maxChars: 400)
        XCTAssertTrue(excerpt.contains("First neighbor"))
        XCTAssertTrue(excerpt.contains("ceramic bicycle"))
        XCTAssertTrue(excerpt.contains("Third neighbor"))
    }

    func test_retrieve_usesBestPassageNotEntryPrefix() {
        let filler = String(repeating: "Morning weather notes and grocery lists fill the start. ", count: 12)
        XCTAssertGreaterThan(filler.count, 500)
        let gold = "The ceramic bicycle I painted with Priya sat in the garage all winter."
        let entry = Entry(
            title: "Long day",
            text: filler + gold + " Afterwards I made tea and went to bed early.",
            createdAt: Date().addingTimeInterval(-86_400)
        )
        let decoys = (0..<4).map { i in
            Entry(title: "decoy \(i)", text: "flumox vendrik parlune quostam grebbin marzipol \(i)",
                  createdAt: Date().addingTimeInterval(-Double(i + 2) * 86_400))
        }
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "what did I write about the ceramic bicycle"),
            entries: decoys + [entry]
        )
        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(result.isAmbient)
        guard let hit = result.entries.first(where: { $0.id == entry.id }) else {
            return XCTFail("expected the long entry to be retrieved")
        }
        XCTAssertTrue(hit.text.contains("ceramic bicycle"), "excerpt must include the matching passage")
        XCTAssertFalse(result.contextBlock.contains(String(filler.prefix(80))),
                       "context block must not be the first-500-character prefix")
        let prefix = String(entry.text.prefix(EntryRetriever.maxContentChars))
        XCTAssertNotEqual(hit.text, prefix)
    }

    func test_languageDetection_englishJournal() {
        let language = PassageChunker.detectLanguage(
            title: "Tuesday",
            text: "Walked to the store and bought apples for the pie."
        )
        XCTAssertTrue(language == .english || language == .undetermined)
    }
}

final class PassageEmbeddingCacheTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PassageEmbeddingCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeService() -> EmbeddingService {
        EmbeddingService(directory: directory)
    }

    private func randomVector(_ count: Int = 32) -> [Double] {
        (0..<count).map { _ in Double.random(in: -1...1) }
    }

    func test_unchangedPassages_areNotReEmbedded() {
        let id = UUID()
        let p0 = "First passage stays exactly the same across the edit."
        let p1old = "Second passage will change on the next save."
        let p1new = "Second passage now names a different subject entirely."
        let p2 = "Third passage is also left untouched by the edit."
        let hash1 = EmbeddingService.contentHash(title: "t", text: p0 + p1old + p2)
        let hash2 = EmbeddingService.contentHash(title: "t", text: p0 + p1new + p2)
        let service = makeService()
        service.storePassageVector(randomVector(), id: id, index: 0, textHash: EmbeddingService.stableHash(p0), contentHash: hash1)
        service.storePassageVector(randomVector(), id: id, index: 1, textHash: EmbeddingService.stableHash(p1old), contentHash: hash1)
        service.storePassageVector(randomVector(), id: id, index: 2, textHash: EmbeddingService.stableHash(p2), contentHash: hash1)

        let passages = [
            Passage(index: 0, text: p0, sentenceRange: 0..<1),
            Passage(index: 1, text: p1new, sentenceRange: 1..<2),
            Passage(index: 2, text: p2, sentenceRange: 2..<3)
        ]
        _ = service.passageVectors(id: id, passages: passages, contentHash: hash2)
        XCTAssertFalse(service.lastEmbeddedPassageIndexes.contains(0), "p0 text did not change")
        XCTAssertFalse(service.lastEmbeddedPassageIndexes.contains(2), "p2 text did not change")
        if service.isAvailable {
            XCTAssertEqual(service.lastEmbeddedPassageIndexes, [1])
        }
    }

    func test_removeEmbeddings_deletesPassageFiles() {
        let id = UUID()
        let hash = EmbeddingService.stableHash("p")
        let service = makeService()
        service.storePassageVector(randomVector(), id: id, index: 0, textHash: hash, contentHash: hash)
        service.removeEmbeddings(for: [id])
        let leftovers = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(leftovers.filter { $0.pathExtension == "vec" }.isEmpty)
        XCTAssertNil(service.cachedPassageVectors(id: id, contentHash: hash))
    }

    func test_parseVectorFilename_distinguishesWholeEntryFromPassage() {
        let id = UUID()
        let whole = URL(fileURLWithPath: "/tmp/\(id.uuidString).vec")
        let passage = URL(fileURLWithPath: "/tmp/\(id.uuidString).p3.vec")
        XCTAssertEqual(EmbeddingService.parseVectorFilename(whole)?.id, id)
        XCTAssertNil(EmbeddingService.parseVectorFilename(whole)?.passageIndex)
        XCTAssertEqual(EmbeddingService.parseVectorFilename(passage)?.id, id)
        XCTAssertEqual(EmbeddingService.parseVectorFilename(passage)?.passageIndex, 3)
    }
}
