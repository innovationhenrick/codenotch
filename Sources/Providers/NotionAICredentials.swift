import Foundation

struct NotionCredentialSources {
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var settingsToken: () -> String? = NotionAICredentials.cachedSettingsToken
    var settingsPresent: () -> Bool = NotionAICredentials.isSettingsTokenPresent
    var deleteSettingsToken: () -> Void = NotionAICredentials.deleteSettingsToken
    var forgetCached: () -> Void = NotionAICredentials.forgetCached
}

/// The token used for Notion's documented Agent Insights endpoint. Codenotch
/// never reads a browser cookie store; the user either enters the token here or
/// provides NOTION_API_TOKEN in the environment.
enum NotionAICredentials {
    static let environmentKey = "NOTION_API_TOKEN"
    static let keychainService = "notion-ai-api-token"
    static let keychainAccount = "codenotch"

    private static let settingsCache = CredentialCache<String> { _ in false }

    static func load(_ sources: NotionCredentialSources = NotionCredentialSources()) throws -> String {
        if let token = nonEmpty(sources.environment[environmentKey]) { return token }
        if let token = nonEmpty(sources.settingsToken()) { return token }
        throw UsageProviderError.needsAuth
    }

    static func account(_ sources: NotionCredentialSources = NotionCredentialSources()) -> ProviderAccount? {
        guard nonEmpty(sources.environment[environmentKey]) != nil || sources.settingsPresent() else {
            return nil
        }
        return ProviderAccount(label: nil, plan: nil, source: L10n.t("Notion API"), manageURL: nil)
    }

    static func cachedSettingsToken() -> String? {
        try? settingsCache.value(
            itemModifiedAt: { KeychainItem.modifiedAt(service: keychainService, account: keychainAccount) },
            reload: {
                guard let token = KeychainItem.read(service: keychainService, account: keychainAccount) else {
                    throw UsageProviderError.needsAuth
                }
                return token
            }
        )
    }

    static func isSettingsTokenPresent() -> Bool {
        KeychainItem.modifiedAt(service: keychainService, account: keychainAccount) != nil
    }

    static func storeSettingsToken(_ token: String) {
        guard let trimmed = nonEmpty(token) else { return }
        settingsCache.forget()
        _ = KeychainItem.store(service: keychainService, account: keychainAccount, value: trimmed)
    }

    static func deleteSettingsToken() {
        settingsCache.forget()
        KeychainItem.delete(service: keychainService, account: keychainAccount)
    }

    static func forgetCached() { settingsCache.forget() }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}
