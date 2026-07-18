import XCTest
@testable import Aria

final class LocalWorkLimiterTests: XCTestCase {
    func testLimiterEnforcesCapacityAndAdmitsAfterRelease() async {
        let limiter = LocalWorkLimiter()

        let first = await limiter.acquire(limit: 1)
        let second = await limiter.acquire(limit: 1)
        await limiter.release()
        let afterRelease = await limiter.acquire(limit: 1)

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertTrue(afterRelease)
    }

    func testLimiterAllowsPerformanceCapacity() async {
        let limiter = LocalWorkLimiter()

        let first = await limiter.acquire(limit: 2)
        let second = await limiter.acquire(limit: 2)
        let third = await limiter.acquire(limit: 2)

        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertFalse(third)
    }
}
