import XCTest
@testable import Aria

final class LinearServiceTests: XCTestCase {

    // MARK: - Helpers

    private func mockResponse(statusCode: Int = 200) -> URLResponse {
        HTTPURLResponse(url: URL(string: "https://api.linear.app")!,
                        statusCode: statusCode,
                        httpVersion: nil,
                        headerFields: nil)!
    }

    private func mockFetch(data: Data, statusCode: Int = 200)
        -> @Sendable (URLRequest) async throws -> (Data, URLResponse)
    {
        let response = mockResponse(statusCode: statusCode)
        return { _ in (data, response) }
    }

    private func jsonData(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - Issues

    func testIssuesFormatsCorrectly() async throws {
        let payload: [String: Any] = [
            "data": [
                "issues": [
                    "nodes": [
                        ["title": "Fix login", "identifier": "ENG-42",
                         "url": "https://linear.app/team/issue/ENG-42",
                         "assignee": ["name": "Alice"]],
                        ["title": "Add dashboard", "identifier": "ENG-43",
                         "url": "https://linear.app/team/issue/ENG-43",
                         "assignee": NSNull()]
                    ]
                ]
            ]
        ]
        let svc = LinearService(apiKey: "key", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.issues(teamId: nil)
        XCTAssertTrue(result.hasPrefix("Open Linear issues:"))
        XCTAssertTrue(result.contains("ENG-42"))
        XCTAssertTrue(result.contains("Fix login"))
        XCTAssertTrue(result.contains("Alice"))
        XCTAssertTrue(result.contains("ENG-43"))
        XCTAssertTrue(result.contains("Add dashboard"))
        // ENG-43 has null assignee — assignee name should NOT appear
        XCTAssertFalse(result.contains("null"))
    }

    func testIssuesNullAssigneeFormatsWithoutAssigneeName() async throws {
        let payload: [String: Any] = [
            "data": [
                "issues": [
                    "nodes": [
                        ["title": "Add dashboard", "identifier": "ENG-43",
                         "url": "https://linear.app/team/issue/ENG-43",
                         "assignee": NSNull()]
                    ]
                ]
            ]
        ]
        let svc = LinearService(apiKey: "key", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.issues(teamId: nil)
        // Should be "ENG-43 Add dashboard — https://..." without assignee segment
        XCTAssertTrue(result.contains("ENG-43 Add dashboard — https://linear.app/team/issue/ENG-43"))
    }

    func testIssuesEmptyReturnsNoIssuesMessage() async throws {
        let payload: [String: Any] = [
            "data": ["issues": ["nodes": [] as [[String: Any]]]]
        ]
        let svc = LinearService(apiKey: "key", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.issues(teamId: nil)
        XCTAssertEqual(result, "No open issues found in Linear.")
    }

    func testIssuesWithTeamIdIncludesTeamFilter() async throws {
        // Captures the request to verify the query contains the teamId filter
        let payload: [String: Any] = [
            "data": ["issues": ["nodes": [] as [[String: Any]]]]
        ]
        var capturedBody: Data?
        let fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { req in
            capturedBody = req.httpBody
            return (self.jsonData(payload),
                    self.mockResponse(statusCode: 200))
        }
        let svc = LinearService(apiKey: "key", fetch: fetch)
        _ = try await svc.issues(teamId: "TEAM-1")
        let bodyStr = capturedBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        XCTAssertTrue(bodyStr.contains("TEAM-1"), "Request body should contain teamId")
    }

    // MARK: - Projects

    func testProjectsFormatsCorrectly() async throws {
        let payload: [String: Any] = [
            "data": [
                "projects": [
                    "nodes": [
                        ["name": "Apollo", "description": "Rocket project",
                         "url": "https://linear.app/team/project/apollo"]
                    ]
                ]
            ]
        ]
        let svc = LinearService(apiKey: "key", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.projects()
        XCTAssertTrue(result.hasPrefix("Linear projects:"))
        XCTAssertTrue(result.contains("Apollo"))
        XCTAssertTrue(result.contains("Rocket project"))
        XCTAssertTrue(result.contains("https://linear.app/team/project/apollo"))
    }

    func testProjectsEmptyDescriptionShowsNoDescription() async throws {
        let payload: [String: Any] = [
            "data": [
                "projects": [
                    "nodes": [
                        ["name": "Stealth", "description": "",
                         "url": "https://linear.app/team/project/stealth"]
                    ]
                ]
            ]
        ]
        let svc = LinearService(apiKey: "key", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.projects()
        XCTAssertTrue(result.contains("no description"))
    }

    func testProjectsEmptyReturnsNoProjectsMessage() async throws {
        let payload: [String: Any] = [
            "data": ["projects": ["nodes": [] as [[String: Any]]]]
        ]
        let svc = LinearService(apiKey: "key", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.projects()
        XCTAssertEqual(result, "No projects found in Linear.")
    }

    // MARK: - HTTP errors

    func testHTTPErrorThrows() async throws {
        let svc = LinearService(apiKey: "key",
                                fetch: mockFetch(data: Data(), statusCode: 401))
        do {
            _ = try await svc.issues(teamId: nil)
            XCTFail("Expected throw for 401")
        } catch let err as LinearServiceError {
            if case .httpError(let code) = err {
                XCTAssertEqual(code, 401)
            } else {
                XCTFail("Unexpected error type: \(err)")
            }
        }
    }

    func testHTTPErrorProjectsThrows() async throws {
        let svc = LinearService(apiKey: "key",
                                fetch: mockFetch(data: Data(), statusCode: 500))
        do {
            _ = try await svc.projects()
            XCTFail("Expected throw for 500")
        } catch let err as LinearServiceError {
            if case .httpError(let code) = err {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Unexpected error type: \(err)")
            }
        }
    }

    func testErrorDescriptionContainsStatusCode() {
        let err = LinearServiceError.httpError(403)
        XCTAssertTrue(err.localizedDescription.contains("403"))
        XCTAssertTrue(err.localizedDescription.lowercased().contains("linear"))
    }
}
