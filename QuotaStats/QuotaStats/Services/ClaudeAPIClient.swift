import Foundation
import Security
@preconcurrency import os.log

final class ClaudeAPIClient: @unchecked Sendable {
    static let shared = ClaudeAPIClient()

    private let usageURL = "https://api.anthropic.com/api/oauth/usage"
    private let tokenURL = "https://api.anthropic.com/v1/oauth/token"
    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let log = Logger(subsystem: "com.matt.quotastats", category: "ClaudeAPI")

    private var rateLimitedUntil: Date?
    private var cachedQuota: ClaudeQuota?
    private let lock = NSLock()

    func fetchUsage() async throws -> ClaudeQuota {
        if let blockedUntil = threadSafe({ rateLimitedUntil }), Date() < blockedUntil {
            let wait = Int(blockedUntil.timeIntervalSinceNow)
            log.info("Rate limited for \(wait)s more, returning cached data")
            if let cached = threadSafe({ cachedQuota }) { return cached }
            throw ClaudeError.rateLimited(retryAfter: wait)
        }

        var credentials = try readCredentials()
        let expiresIn = (Double(credentials.expiresAt) - Date().timeIntervalSince1970 * 1000) / 1000
        log.info("Token expires in \(Int(expiresIn))s")

        if expiresIn < 60 {
            log.info("Token expired or expiring soon, refreshing")
            credentials = try await refreshToken(credentials)
        }

        let result = try await callUsageAPI(token: credentials.accessToken)

        switch result {
        case .success(let quota):
            threadSafe { cachedQuota = quota }
            return quota
        case .needsRefresh:
            log.info("API returned 401, refreshing token")
            credentials = try await refreshToken(credentials)
            let retry = try await callUsageAPI(token: credentials.accessToken)
            if case .success(let quota) = retry {
                threadSafe { cachedQuota = quota }
                return quota
            }
            throw ClaudeError.httpError(401)
        case .rateLimited(let retryAfter):
            if let cached = threadSafe({ cachedQuota }) {
                log.info("Rate limited, returning cached data")
                return cached
            }
            throw ClaudeError.rateLimited(retryAfter: retryAfter)
        }
    }

    private enum UsageResult {
        case success(ClaudeQuota)
        case needsRefresh
        case rateLimited(Int)
    }

    private func callUsageAPI(token: String) async throws -> UsageResult {
        var request = URLRequest(url: URL(string: usageURL)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        log.info("Usage API returned \(http.statusCode)")

        if http.statusCode == 401 {
            return .needsRefresh
        }

        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "retry-after")
                .flatMap(Int.init) ?? 120
            log.warning("Rate limited, retry-after: \(retryAfter)s")
            threadSafe { rateLimitedUntil = Date().addingTimeInterval(TimeInterval(retryAfter)) }
            return .rateLimited(retryAfter)
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            log.error("Unexpected status \(http.statusCode): \(body)")
            throw ClaudeError.httpError(http.statusCode)
        }

        do {
            let usage = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
            threadSafe { rateLimitedUntil = nil }
            return .success(mapToQuota(usage))
        } catch {
            let body = String(data: data, encoding: .utf8) ?? ""
            log.error("Failed to decode usage response: \(error) body: \(body)")
            throw error
        }
    }

    // MARK: - Token Refresh

    private func refreshToken(_ creds: OAuthCredentials) async throws -> OAuthCredentials {
        log.info("Refreshing OAuth token")

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

        guard let http = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        log.info("Token refresh returned \(http.statusCode)")

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            log.error("Token refresh failed: \(http.statusCode) \(body)")
            throw ClaudeError.tokenRefreshFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw ClaudeError.tokenParseError
        }

        log.info("Token refreshed, expires in \(expiresIn)s")

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
        let quota = ClaudeQuota(
            fiveHourPct: response.fiveHour?.utilization ?? 0,
            fiveHourReset: parseISO8601(response.fiveHour?.resetsAt),
            sevenDayPct: response.sevenDay?.utilization ?? 0,
            sevenDayReset: parseISO8601(response.sevenDay?.resetsAt)
        )
        log.info("Claude usage: 5h=\(quota.fiveHourPct)% 7d=\(quota.sevenDayPct)%")
        return quota
    }

    // MARK: - Thread Safety

    @discardableResult
    private func threadSafe<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
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
            log.error("Keychain read failed: \(status)")
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

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials"
        ]
        let update: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Claude Code-credentials",
                kSecAttrAccount as String: NSUserName(),
                kSecValueData as String: data
            ]
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                log.error("Keychain add failed: \(addStatus)")
            }
        } else if status != errSecSuccess {
            log.error("Keychain update failed: \(status)")
        }
    }
}

enum ClaudeError: LocalizedError {
    case credentialsNotFound
    case tokenParseError
    case tokenRefreshFailed
    case invalidResponse
    case httpError(Int)
    case rateLimited(retryAfter: Int)

    var errorDescription: String? {
        switch self {
        case .credentialsNotFound: "Claude Code credentials not found. Make sure Claude Code is installed and you're signed in."
        case .tokenParseError: "Failed to parse Claude Code credentials."
        case .tokenRefreshFailed: "Token refresh failed. Restart Claude Code to re-authenticate."
        case .invalidResponse: "Invalid response from Anthropic API."
        case .httpError(let code): "Anthropic API returned HTTP \(code)."
        case .rateLimited(let seconds): "Rate limited by Anthropic API. Retrying in \(seconds)s."
        }
    }
}
