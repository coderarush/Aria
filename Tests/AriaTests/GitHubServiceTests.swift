import XCTest
@testable import Aria

final class GitHubServiceTests: XCTestCase {

    // MARK: - Helpers

    private func mockResponse(statusCode: Int = 200) -> URLResponse {
        HTTPURLResponse(url: URL(string: "https://api.github.com")!,
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
        let payload: [[String: Any]] = [
            ["number": 42, "title": "Fix the bug",
             "html_url": "https://github.com/owner/repo/issues/42",
             "user": ["login": "alice"]],
            ["number": 43, "title": "Add feature",
             "html_url": "https://github.com/owner/repo/issues/43",
             "user": ["login": "bob"]]
        ]
        let svc = GitHubService(token: "tok", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.issues(repo: "owner/repo")
        XCTAssertTrue(result.hasPrefix("Open issues in owner/repo:"))
        XCTAssertTrue(result.contains("#42"))
        XCTAssertTrue(result.contains("Fix the bug"))
        XCTAssertTrue(result.contains("alice"))
        XCTAssertTrue(result.contains("#43"))
        XCTAssertTrue(result.contains("bob"))
    }

    func testPRsFormatsCorrectly() async throws {
        let payload: [[String: Any]] = [
            ["number": 7, "title": "Update readme",
             "html_url": "https://github.com/owner/repo/pull/7",
             "user": ["login": "carol"]]
        ]
        let svc = GitHubService(token: "tok", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.pullRequests(repo: "owner/repo")
        XCTAssertTrue(result.hasPrefix("Open PRs in owner/repo:"))
        XCTAssertTrue(result.contains("#7"))
        XCTAssertTrue(result.contains("Update readme"))
        XCTAssertTrue(result.contains("carol"))
    }

    func testIssuesEmptyReturnsNoIssuesMessage() async throws {
        let payload: [[String: Any]] = []
        let svc = GitHubService(token: "tok", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.issues(repo: "owner/repo")
        XCTAssertEqual(result, "No open issues in owner/repo.")
    }

    func testPRsEmptyReturnsNoPRsMessage() async throws {
        let payload: [[String: Any]] = []
        let svc = GitHubService(token: "tok", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.pullRequests(repo: "owner/repo")
        XCTAssertEqual(result, "No open pull requests in owner/repo.")
    }

    func testIssuesHTTPErrorThrows() async throws {
        let svc = GitHubService(token: "tok",
                                fetch: mockFetch(data: Data(), statusCode: 401))
        do {
            _ = try await svc.issues(repo: "owner/repo")
            XCTFail("Expected throw for 401")
        } catch let err as GitHubServiceError {
            if case .httpError(let code) = err {
                XCTAssertEqual(code, 401)
            } else {
                XCTFail("Unexpected error type: \(err)")
            }
        }
    }

    func testIssuesMissingUserLoginFallsBackToUnknown() async throws {
        // user key present but login is absent — should fall back to "unknown"
        let payload: [[String: Any]] = [
            ["number": 1, "title": "Orphan issue",
             "html_url": "https://github.com/owner/repo/issues/1",
             "user": ["id": 99]]   // no "login" key
        ]
        let svc = GitHubService(token: "tok", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.issues(repo: "owner/repo")
        XCTAssertTrue(result.contains("unknown"))
    }

    func testIssuesMissingUserKeyFallsBackToUnknown() async throws {
        // user key entirely absent
        let payload: [[String: Any]] = [
            ["number": 2, "title": "No user",
             "html_url": "https://github.com/owner/repo/issues/2"]
        ]
        let svc = GitHubService(token: "tok", fetch: mockFetch(data: jsonData(payload)))
        let result = try await svc.issues(repo: "owner/repo")
        XCTAssertTrue(result.contains("unknown"))
    }

    func testIssuesErrorDescriptionContainsStatusCode() {
        let err = GitHubServiceError.httpError(403)
        XCTAssertTrue(err.localizedDescription.contains("403"))
        XCTAssertTrue(err.localizedDescription.lowercased().contains("github"))
    }
}
