import XCTest
@testable import Aria

final class FlashcardGeneratorTests: XCTestCase {
    let generator = FlashcardGenerator()

    // MARK: - generate()

    func testGenerateParsesCards() async throws {
        let json = """
        [
            {"front":"What is Swift?","back":"A compiled programming language.","category":"term"},
            {"front":"Explain actors.","back":"Actors protect shared mutable state.","category":"concept"}
        ]
        """
        let cards = try await generator.generate(from: "content", topic: "Swift") { _ in json }
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards[0].front, "What is Swift?")
        XCTAssertEqual(cards[0].category, "term")
        XCTAssertEqual(cards[1].category, "concept")
    }

    func testGenerateThrowsOnBadJSON() async throws {
        do {
            _ = try await generator.generate(from: "content", topic: "Test") { _ in "not json" }
            XCTFail("Expected parseFailure")
        } catch let error as FlashcardError {
            if case .parseFailure(let raw) = error {
                XCTAssertEqual(raw, "not json")
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testGenerateThrowsOnEmptyArray() async throws {
        do {
            _ = try await generator.generate(from: "content", topic: "Test") { _ in "[]" }
            XCTFail("Expected parseFailure")
        } catch let error as FlashcardError {
            if case .parseFailure = error {
                // expected
            } else {
                XCTFail("Wrong error: \(error)")
            }
        }
    }

    func testGenerateExtractsJSONFromMessyResponse() async throws {
        let messy = """
        Here are your cards: [{"front":"Q","back":"A","category":"term"}] done.
        """
        let cards = try await generator.generate(from: "content", topic: "Test") { _ in messy }
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].front, "Q")
    }

    // MARK: - save()

    func testSaveWritesFile() throws {
        // Use a temp directory approach by creating in a uniquely-named subdirectory
        // We'll patch the save path by using the real save and verifying the file
        let cards = [
            Flashcard(id: UUID(), front: "Q1", back: "A1", category: "term"),
            Flashcard(id: UUID(), front: "Q2", back: "A2", category: "concept")
        ]
        let topic = "test-\(UUID().uuidString)"
        try generator.save(cards, topic: topic)

        let expectedPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Aria Notes/Flashcards/\(topic)-flashcards.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath.path))

        // Cleanup
        try? FileManager.default.removeItem(at: expectedPath)
    }
}
