import XCTest
@testable import Aria

final class ChatGPTImportToolTests: XCTestCase {

    func testExtractFindsAriaConversationAndCompactsSnippet() throws {
        let json = """
        [
          {
            "title": "Aria product ideas",
            "mapping": {
              "a": {
                "message": {
                  "create_time": 1,
                  "content": { "parts": ["We should make Aria import old ChatGPT planning chats and turn them into memory."] }
                }
              }
            }
          },
          {
            "title": "Dinner",
            "mapping": {
              "b": {
                "message": {
                  "create_time": 2,
                  "content": { "parts": ["Pasta notes"] }
                }
              }
            }
          }
        ]
        """
        let hits = try ChatGPTExportImporter.extract(from: Data(json.utf8), query: "Aria", limit: 10)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].title, "Aria product ideas")
        XCTAssertTrue(hits[0].snippet.contains("import old ChatGPT"))
    }

    func testExtractHonorsLimit() throws {
        let json = """
        [
          {"title":"Aria one","mapping":{"a":{"message":{"create_time":1,"content":{"parts":["Aria first"]}}}}},
          {"title":"Aria two","mapping":{"b":{"message":{"create_time":2,"content":{"parts":["Aria second"]}}}}}
        ]
        """
        let hits = try ChatGPTExportImporter.extract(from: Data(json.utf8), query: "Aria", limit: 1)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].title, "Aria one")
    }
}
