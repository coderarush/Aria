import XCTest
@testable import Aria

final class LensClassifierTests: XCTestCase {
    func testDetectsError() {
        XCTAssertEqual(LensClassifier.kind(of: "TypeError: undefined is not a function"), .error)
        XCTAssertEqual(LensClassifier.kind(of: "Traceback (most recent call last):"), .error)
        XCTAssertEqual(LensClassifier.kind(of: "fatal error: index out of range"), .error)
    }

    func testDetectsCode() {
        XCTAssertEqual(LensClassifier.kind(of: "func add(a: Int) -> Int { return a + 1 }"), .code)
        XCTAssertEqual(LensClassifier.kind(of: "const x = () => { console.log(x); };"), .code)
    }

    func testDetectsMath() {
        XCTAssertEqual(LensClassifier.kind(of: "12 * (4 + 3) = ?"), .math)
        XCTAssertEqual(LensClassifier.kind(of: "2^10"), .math)
    }

    func testProseFallback() {
        XCTAssertEqual(LensClassifier.kind(of: "The quarterly report is due on Friday."), .prose)
        XCTAssertEqual(LensClassifier.kind(of: "Export"), .prose)
        XCTAssertEqual(LensClassifier.kind(of: ""), .prose)
    }

    func testPromptsAreKindSpecificAndContainContent() {
        let err = LensClassifier.prompt(for: .error, ocr: "NullPointerException at line 42")
        XCTAssertTrue(err.contains("fix"))
        XCTAssertTrue(err.contains("NullPointerException at line 42"))
        let math = LensClassifier.prompt(for: .math, ocr: "5 + 7")
        XCTAssertTrue(math.lowercased().contains("answer"))
    }
}
