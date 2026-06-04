import XCTest
@testable import Aria

final class EchoCancellerTests: XCTestCase {
    // 16 kHz, 10 ms frames = 160 samples.
    private let frame = 160

    /// A near-end that is PURE echo (a scaled, delayed copy of the far-end) should be
    /// largely cancelled — residual energy well below the un-cancelled echo energy.
    func testCancelsEchoOnlyNearEnd() {
        let ec = EchoCanceller(frameSize: frame, filterTaps: frame * 8)
        var farHist = [Int16](repeating: 0, count: frame)
        var echoEnergy = 0.0, residualEnergy = 0.0
        var rng = SystemRandomNumberGenerator()
        for i in 0..<200 {
            let far = (0..<frame).map { _ in Int16(Int.random(in: -8000...8000, using: &rng)) }
            let near = farHist.map { Int16(Double($0) * 0.5) }   // echo = last frame * 0.5
            let cleaned = ec.process(near: near, far: far)
            if i > 150 {                                          // measure after convergence
                echoEnergy += near.reduce(0.0) { $0 + Double($1) * Double($1) }
                residualEnergy += cleaned.reduce(0.0) { $0 + Double($1) * Double($1) }
            }
            farHist = far
        }
        XCTAssertGreaterThan(echoEnergy, 0)
        XCTAssertLessThan(residualEnergy, echoEnergy * 0.5, "echo not cancelled")
    }

    func testProcessReturnsFrameSizedOutput() {
        let ec = EchoCanceller(frameSize: frame, filterTaps: frame * 8)
        let out = ec.process(near: [Int16](repeating: 100, count: frame),
                             far:  [Int16](repeating: 0, count: frame))
        XCTAssertEqual(out.count, frame)
    }
}
