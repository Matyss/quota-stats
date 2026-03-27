import Foundation
import Security

final class ClaudeAPIClient: Sendable {
    static let shared = ClaudeAPIClient()

    private let usageURL = "https://api.anthropic.com/api/oauth/usage"
    private let tokenURL = "https://api.anthropic.com/v1/oauth/token"
    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    func fetchUsage() async throws -> ClaudeQuota {
        var credentials = try readCredentials()

        let isExpired = Date().timeIntervalSince1970 * 1000 > Double(credentials.expiresAt)
        if isExpired {
            credentials = try await refreshToken(credentials)
        }

        let result = try await callUsageAPI(token: credentials.accessToken)

        switch result {
        case .success(let quota):
            return quota
        case .needsRefresh:
            credentials = try await refreshToken(credentials)
            let retry = try await callUsageAPI(token: credentials.accessToken)
            if case .success(let quota) = retry { return quota }
            throw ClaudeError.httpError(401)
        }
    }

    private enum UsageResult {
        case success(ClaudeQuota)
        case needsRefresh
    }

    private func callUsageAPI(token: String) async throws -> UsageResult {
        var request = URLRequest(url: URL(string: usageURL)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            return .needsRefresh
        }

        guard httpResponse.statusCode == 200 else {
            throw ClaudeError.httpError(httpResponse.statusCode)
        }

        let usage = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        return .success(mapToQuota(usage))
    }

    // MARK: - Token Refresh

    private func refreshToken(_ creds: OAuthCredentials) async throws -> OAuthCredentials {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": creds.refreshToken,
            "client_id": clientId
        ]

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClaudeError.tokenRefreshFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw ClaudeError.tokenParseError
        }

        let expiresAt = Int(Date().timeIntervalSince1970 * 1000) + expiresIn * 1000
        let newCreds = OAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scopes: creds.scopes,
            subscriptionType: creds.subscriptionType,
            rateLimitTier: creds.rateLimitTier
        )

        try saveCredentials(newCreds)
        return newCreds
    }

    // MARK: - Mapping

    private func mapToQuota(_ response: ClaudeUsageResponse) -> ClaudeQuota {
        ClaudeQuota(
            fiveHourPct: response.fiveHour?.utilization ?? 0,
            fiveHourReset: parseISO8601(response.fiveHour?.resetsAt),
            sevenDayPct: response.sevenDay?.utilization ?? 0,
            sevenDayReset: parseISO8601(response.sevenDay?.resetsAt)
        )
    }

    // MARK: - Keychain

    struct OAuthCredentials {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int
        let scopes: [String]
        let subscriptionType: String
        let rateLimitTier: String
    }

    private func readCredentials() throws -> OAuthCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw ClaudeError.credentialsNotFound
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              let refreshToken = oauth["refreshToken"] as? String,
              let expiresAt = oauth["expiresAt"] as? Int else {
            throw ClaudeError.tokenParseError
        }

        return OAuthCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scopes: oauth["scopes"] as? [String] ?? [],
            subscriptionType: oauth["subscriptionType"] as? String ?? "",
            rateLimitTier: oauth["rateLimitTier"] as? String ?? ""
        )
    }

    private func saveCredentials(_ creds: OAuthCredentials) throws {
        let oauthDict: [String: Any] = [
            "accessToken": creds.accessToken,
            "refreshToken": creds.refreshToken,
            "expiresAt": creds.expiresAt,
            "scopes": creds.scopes,
            "subscriptionType": creds.subscriptionType,
            "rateLimitTier": creds.rateLimitTier
        ]
        let wrapper: [String: Any] = ["claudeAiOauth": oauthDict]
        let data = try JSONSerialization.data(withJSONObject: wrapper)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials"
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecAttrAccount as String: NSUserName(),
            kSecValueData as String: data
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("Failed to save credentials to Keychain: \(addStatus)")
        }
    }
}

enum ClaudeError: LocalizedError {
    case credentialsNotFound
    case tokenParseError
    case tokenRefreshFailed
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .credentialsNotFound: "Claude Code credentials not found. Make sure Claude Code is installed and you're signed in."
        case .tokenParseError: "Failed to parse Claude Code credentials."
        case .tokenRefreshFailed: "Token refresh failed. Restart Claude Code to re-authenticate."
        case .invalidResponse: "Invalid response from Anthropic API."
        case .httpError(let code): "Anthropic API returned HTTP \(code)."
        }
    }
}
