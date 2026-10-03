import Foundation
import os

/// Reads the personal Notion Agent's documented Insights endpoint. This is
/// premium-credit accounting only; Notion's included allowance and personal
/// chat-session lifecycle are not exposed by this endpoint.
actor NotionAIProvider: UsageProvider {
    nonisolated let id = "notionai"
    nonisolated let displayName = "Notion AI"
    nonisolated let glyph = ProviderGlyph.notion

    private let session: URLSession
    nonisolated private let sources: NotionCredentialSources

    init(session: URLSession = .shared,
         sources: NotionCredentialSources = NotionCredentialSources()) {
        self.session = session
        self.sources = sources
    }

    nonisolated var signInRoute: SignInRoute {
        .guidance(L10n.t("Paste a Notion API token in Settings to read premium AI credits."))
    }

    nonisolated func account() -> ProviderAccount? { NotionAICredentials.account(sources) }

    nonisolated func signOut() async { sources.deleteSettingsToken() }

    nonisolated func forgetCachedCredential() { sources.forgetCached() }

    func fetchSnapshot() async throws -> ProviderSnapshot {
        let token = try NotionAICredentials.load(sources)
        var request = URLRequest(url: NotionAIProvider.insightsURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2026-03-11", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw UsageProviderError.timedOut
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UsageProviderError.apiError(L10n.t("Couldn't reach Notion."))
        }

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        Log.usage.debug("notion AI insights answered \(status)")

        if status == 401 {
            sources.forgetCached()
            throw UsageProviderError.needsAuth
        }
        if status == 403 {
            throw UsageProviderError.apiError(L10n.t("This Notion token cannot read agent insights."))
        }
        if status == 429 {
            let retryAfter = http?.value(forHTTPHeaderField: "Retry-After")
                .flatMap(Double.init) ?? 60
            throw UsageProviderError.rateLimited(retryAfter: max(60, retryAfter))
        }
        guard (200..<300).contains(status) else {
            throw UsageProviderError.badResponse(status: status)
        }

        let windows = try NotionAIUsage.windows(from: data)
        return ProviderSnapshot(
            id: id,
            displayName: displayName,
            glyph: glyph,
            fidelity: .official,
            status: .ok,
            windows: windows,
            headlineID: "premium-credits"
        )
    }

    nonisolated static let insightsURL = URL(string: "https://api.notion.com/v1/agents/\(NotionAIUsage.agentID)/insights")!
}
