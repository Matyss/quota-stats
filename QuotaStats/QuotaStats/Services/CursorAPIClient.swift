import Foundation
import SQLite3
import os.log

final class CursorAPIClient: Sendable {
    static let shared = CursorAPIClient()

    private let usageURL = "https://cursor.com/api/usage"
    private let log = Logger(subsystem: "com.matt.quotastats", category: "CursorAPI")

    func fetchUsage() async throws -> CursorQuota {
        let userId = try extractUserId()
        let accessToken = try extractAccessToken()
        let cookieValue = "\(userId)%3A%3A\(accessToken)"

        var request = URLRequest(url: URL(string: "\(usageURL)?user=\(userId)")!)
        request.setValue("WorkosCursorSessionToken=\(cookieValue)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw CursorError.invalidResponse
        }

        log.info("Cursor API returned \(http.statusCode)")

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            log.error("Cursor API error: \(http.statusCode) \(body)")
            throw CursorError.httpError(http.statusCode)
        }

        let usage = try JSONDecoder().decode(CursorUsageResponse.self, from: data)
        let quota = mapToQuota(usage)
        log.info("Cursor usage: \(quota.used)/\(quota.limit)")
        return quota
    }

    private func mapToQuota(_ response: CursorUsageResponse) -> CursorQuota {
        let model = response.gpt4
        let used = model?.numRequests ?? 0
        let limit = model?.maxRequestUsage ?? 500

        var resetDate: Date?
        if let start = parseISO8601(response.startOfMonth) {
            resetDate = Calendar.current.date(byAdding: .month, value: 1, to: start)
        }

        return CursorQuota(used: used, limit: limit, resetDate: resetDate)
    }

    // MARK: - Credential Extraction

    private func extractUserId() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let sentryPath = "\(home)/Library/Application Support/Cursor/sentry/scope_v3.json"
        if let data = FileManager.default.contents(atPath: sentryPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scope = json["scope"] as? [String: Any],
           let user = scope["user"] as? [String: Any],
           let oauthId = user["id"] as? String,
           let userId = extractUserIdFromOAuth(oauthId) {
            return userId
        }

        let sessionPath = "\(home)/Library/Application Support/Cursor/sentry/session.json"
        if let data = FileManager.default.contents(atPath: sessionPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let did = json["did"] as? String,
           let userId = extractUserIdFromOAuth(did) {
            return userId
        }

        log.error("Could not find Cursor user ID in sentry files")
        throw CursorError.userIdNotFound
    }

    private func extractUserIdFromOAuth(_ oauthId: String) -> String? {
        if oauthId.contains("|") {
            return oauthId.split(separator: "|").first(where: { $0.hasPrefix("user_") }).map(String.init)
        }
        if oauthId.hasPrefix("user_") { return oauthId }
        return nil
    }

    private func extractAccessToken() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

        guard FileManager.default.fileExists(atPath: dbPath) else {
            log.error("Cursor state.vscdb not found")
            throw CursorError.tokenDatabaseNotFound
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw CursorError.tokenDatabaseError
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw CursorError.tokenDatabaseError
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let cString = sqlite3_column_text(stmt, 0) else {
            throw CursorError.accessTokenNotFound
        }

        return String(cString: cString)
    }
}

enum CursorError: LocalizedError {
    case userIdNotFound
    case tokenDatabaseNotFound
    case tokenDatabaseError
    case accessTokenNotFound
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .userIdNotFound: "Could not find Cursor user ID. Make sure Cursor is installed and you're signed in."
        case .tokenDatabaseNotFound: "Cursor database not found. Make sure Cursor is installed."
        case .tokenDatabaseError: "Failed to read Cursor database."
        case .accessTokenNotFound: "Access token not found. Try signing out and back into Cursor."
        case .invalidResponse: "Invalid response from Cursor API."
        case .httpError(let code): "Cursor API returned HTTP \(code)."
        }
    }
}
