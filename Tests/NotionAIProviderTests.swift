import Foundation
import XCTest
@testable import Codenotch

@MainActor
final class NotionAIProviderTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NotionEndpoint.self]
        session = URLSession(configuration: config)
        NotionEndpoint.reset([])
    }

    override func tearDown() {
        session.invalidateAndCancel()
        NotionEndpoint.reset([])
    }

    private func sources(token: String? = "notion_test_token",
                         environment: [String: String] = [:],
                         forgetCached: @escaping () -> Void = {}) -> NotionCredentialSources {
        NotionCredentialSources(
            environment: environment,
            settingsToken: { token },
            settingsPresent: { token != nil },
            deleteSettingsToken: {},
            forgetCached: forgetCached
        )
    }

    private func provider(token: String? = "notion_test_token",
                          environment: [String: String] = [:],
                          forgetCached: @escaping () -> Void = {}) -> NotionAIProvider {
        NotionAIProvider(session: session,
                         sources: sources(token: token, environment: environment,
                                          forgetCached: forgetCached))
    }

    func testRequestUsesDocumentedAgentInsightsContract() async throws {
        NotionEndpoint.reset([.http(200, Data(NotionAIFixture.insights.utf8))])
        let provider = provider()
        let snapshot = try await provider.fetchSnapshot()

        XCTAssertEqual(snapshot.id, "notionai")
        XCTAssertEqual(snapshot.displayName, "Notion AI")
        XCTAssertEqual(snapshot.glyph, .notion)
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.fidelity, .official)
        XCTAssertEqual(snapshot.headlineID, "premium-credits")
        XCTAssertEqual(snapshot.headlineText, "25%")
        XCTAssertEqual(snapshot.windows.first?.detail, "250 credits · 3 runs")
        XCTAssertNotNil(provider.account())

        let request = try XCTUnwrap(NotionEndpoint.requests.first)
        XCTAssertEqual(request.url?.absoluteString,
                       "https://api.notion.com/v1/agents/notion_ai/insights")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer notion_test_token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Notion-Version"), "2026-03-11")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testNoTokenDoesNotTouchTheNetwork() async {
        let provider = provider(token: nil)
        do {
            _ = try await provider.fetchSnapshot()
            XCTFail("expected missing-token status")
        } catch UsageProviderError.needsAuth {
            XCTAssertTrue(NotionEndpoint.requests.isEmpty)
            XCTAssertNil(provider.account())
            XCTAssertTrue(provider.signInRoute.explanation.contains("Notion API token"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testUnauthorizedTokenClearsTheCredentialCache() async {
        var forgotten = 0
        NotionEndpoint.reset([.http(401, Data())])
        do {
            _ = try await provider(forgetCached: { forgotten += 1 }).fetchSnapshot()
            XCTFail("expected unauthorized status")
        } catch UsageProviderError.needsAuth {
            XCTAssertEqual(forgotten, 1)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testForbiddenTokenExplainsInsightsAccess() async {
        NotionEndpoint.reset([.http(403, Data())])
        do {
            _ = try await provider().fetchSnapshot()
            XCTFail("expected access error")
        } catch UsageProviderError.apiError(let message) {
            XCTAssertEqual(message, "This Notion token cannot read agent insights.")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testLiveNotionInsightsWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CODENOTCH_TEST_NOTION_LIVE"] == "1" else {
            throw XCTSkip("Opt-in live check requires NOTION_API_TOKEN")
        }
        guard ProcessInfo.processInfo.environment[NotionAICredentials.environmentKey] != nil else {
            throw XCTSkip("Set NOTION_API_TOKEN for the live check")
        }

        let liveProvider = NotionAIProvider()
        let snapshot = try await liveProvider.fetchSnapshot()
        XCTAssertEqual(snapshot.id, "notionai")
        XCTAssertEqual(snapshot.status, .ok)
        XCTAssertEqual(snapshot.fidelity, .official)
        print("Notion AI premium credits: \(snapshot.headlineText)")
        print(snapshot.windows.first?.detail ?? "No credit detail")
    }
}

private final class NotionEndpoint: URLProtocol {
    enum Result {
        case http(Int, Data, [String: String] = [:])
    }

    private static let lock = NSLock()
    private static var results: [Result] = []
    private static var recordedRequests: [URLRequest] = []

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    static func reset(_ next: [Result]) {
        lock.lock()
        defer { lock.unlock() }
        results = next
        recordedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.recordedRequests.append(request)
        let result = Self.results.isEmpty ? nil : Self.results.removeFirst()
        Self.lock.unlock()

        guard case let .http(status, body, headers)? = result else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
