import XCTest
import Metal
import SwiftUI
@testable import Friday

final class OrbShaderTests: XCTestCase {

    /// The orb shader is compiled from source at runtime, so a syntax error
    /// would only surface as a blank orb. Compile it here to catch MSL bugs.
    func testOrbShaderCompiles() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device (headless CI)")
        }
        let library = try device.makeLibrary(
            source: OrbMetalView.Renderer.shaderSource, options: nil)
        XCTAssertNotNil(library.makeFunction(name: "orb_vertex"))
        XCTAssertNotNil(library.makeFunction(name: "orb_fragment"))
    }

    func testColorComponentsRoundTrip() {
        let (r, g, b, a) = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6, opacity: 1).components
        XCTAssertEqual(r, 0.2, accuracy: 0.02)
        XCTAssertEqual(g, 0.4, accuracy: 0.02)
        XCTAssertEqual(b, 0.6, accuracy: 0.02)
        XCTAssertEqual(a, 1.0, accuracy: 0.02)
    }
}
