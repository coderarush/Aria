import XCTest
@testable import Aria

final class TaskClassifierTests: XCTestCase {

    func testClassifiesLocalEligibleTasks() {
        XCTAssertEqual(TaskClassifier.classify("rename the selected files"), .fileOps)
        XCTAssertEqual(TaskClassifier.classify("organize my downloads folder"), .fileOps)
        XCTAssertEqual(TaskClassifier.classify("what's on my calendar thursday"), .productivity)
        XCTAssertEqual(TaskClassifier.classify("check my email"), .productivity)
        XCTAssertEqual(TaskClassifier.classify("summarize this document"), .documentUnderstanding)
        XCTAssertEqual(TaskClassifier.classify("what did I copy"), .contextRetrieval)
        XCTAssertEqual(TaskClassifier.classify("remember that my sister is Mara"), .memory)
    }

    func testClassifiesCloudTasks() {
        XCTAssertEqual(TaskClassifier.classify("research the best USB microphones and compare prices"), .deepResearch)
        XCTAssertEqual(TaskClassifier.classify("analyze this codebase and refactor the auth module"), .complexReasoning)
        XCTAssertEqual(TaskClassifier.classify("write a competitive analysis of Linear vs Jira"), .deepResearch)
    }

    func testDefaultsToSimpleChat() {
        XCTAssertEqual(TaskClassifier.classify("tell me a joke"), .simpleChat)
        XCTAssertEqual(TaskClassifier.classify("hi"), .simpleChat)
    }
}

final class RoutingPolicyTests: XCTestCase {

    func testEverythingRoutesCloudWhenLocalFirstDisabled() {
        for cls in TaskClass.allCases {
            let d = RoutingPolicy.route(taskClass: cls, localFirstEnabled: false, localAvailable: true)
            XCTAssertEqual(d.tier, .cloud, "\(cls) must route cloud when local-first off")
            XCTAssertTrue(d.reason.contains("local-first off"), d.reason)
        }
    }

    func testLocalEligibleClassesRouteLocalWhenEnabledAndAvailable() {
        for cls: TaskClass in [.fileOps, .productivity, .contextRetrieval, .memory,
                               .documentUnderstanding, .planning] {
            let d = RoutingPolicy.route(taskClass: cls, localFirstEnabled: true, localAvailable: true)
            XCTAssertEqual(d.tier, .local, "\(cls) should prefer local")
        }
    }

    func testCloudClassesStayCloudEvenWhenLocalEnabled() {
        for cls: TaskClass in [.deepResearch, .complexReasoning, .vision, .simpleChat] {
            let d = RoutingPolicy.route(taskClass: cls, localFirstEnabled: true, localAvailable: true)
            XCTAssertEqual(d.tier, .cloud, "\(cls) must stay cloud")
        }
    }

    func testUnreachableLocalFallsBackToCloudWithReason() {
        let d = RoutingPolicy.route(taskClass: .fileOps, localFirstEnabled: true, localAvailable: false)
        XCTAssertEqual(d.tier, .cloud)
        XCTAssertTrue(d.reason.contains("unreachable"), d.reason)
    }
}
